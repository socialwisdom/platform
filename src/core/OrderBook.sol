// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AppStorage, BookState, Level, Order} from "../storage/Storage.sol";
import {
    BookKey,
    Tick,
    OrderId,
    UserId,
    Side,
    MinFillNotMet,
    NotOrderOwner,
    OrderNotFound,
    PrevCandidateNotFound
} from "../types/Types.sol";
import {BookKeyLib} from "../lib/BookKeyLib.sol";
import {Keys} from "../lib/Keys.sol";
import {MaskLib} from "../lib/MaskLib.sol";
import {LevelQueue} from "./LevelQueue.sol";
import {Matching} from "./Matching.sol";

library OrderBook {
    uint256 internal constant CANCEL_CANDIDATES_CAP = 16;

    struct PlaceResult {
        uint128 filledShares;
        uint256 pointsTraded; // sum(fill * tick)
        OrderId placedOrderId; // 0 if fully filled (no resting order)
        uint128 restingShares; // 0 if none
    }

    struct TakeResult {
        uint128 filledShares;
        uint256 pointsTraded;
    }

    struct CancelResult {
        Tick tick;
        uint128 cancelledShares;
        bool levelEmptied;
    }

    // -----------------------------
    // placeLimit
    // -----------------------------

    function placeLimit(
        AppStorage storage s,
        UserId userId,
        BookKey takerBookKey,
        Tick limitTick,
        uint128 sharesRequested
    ) internal returns (PlaceResult memory r) {
        if (sharesRequested == 0) return r;

        (uint128 filled, uint256 pts) = Matching.matchUpTo(s, takerBookKey, limitTick, sharesRequested);
        r.filledShares = filled;
        r.pointsTraded = pts;

        uint128 remaining = sharesRequested - filled;
        if (remaining == 0) return r;

        BookState storage book = s.books[takerBookKey];

        uint32 nextRaw = book.nextOrderId;
        if (nextRaw == 0) nextRaw = 1;

        OrderId newId = OrderId.wrap(nextRaw);
        book.nextOrderId = nextRaw + 1;

        Order storage ord = s.orders[Keys.orderKey(takerBookKey, newId)];

        // HOT slot
        ord.sharesRemaining = remaining;
        ord.ownerId = userId;
        ord.nextOrderId = OrderId.wrap(0);
        ord.tick = limitTick;

        // COLD slot (optional)
        ord.requestedShares = sharesRequested;

        LevelQueue.append(s, takerBookKey, limitTick, newId, remaining);

        Side side = BookKeyLib.sideOf(takerBookKey);
        if (side == Side.Bid) {
            book.bidsMask = MaskLib.set(book.bidsMask, limitTick);
        } else {
            book.asksMask = MaskLib.set(book.asksMask, limitTick);
        }

        r.placedOrderId = newId;
        r.restingShares = remaining;
        return r;
    }

    // -----------------------------
    // take
    // -----------------------------

    function take(AppStorage storage s, BookKey takerBookKey, Tick limitTick, uint128 sharesRequested, uint128 minFill)
        internal
        returns (TakeResult memory r)
    {
        if (sharesRequested == 0) return r;

        (uint128 filled, uint256 pts) = Matching.matchUpTo(s, takerBookKey, limitTick, sharesRequested);
        if (filled < minFill) revert MinFillNotMet(filled, minFill);

        r.filledShares = filled;
        r.pointsTraded = pts;
        return r;
    }

    // -----------------------------
    // cancel (with candidates)
    // -----------------------------

    function cancel(
        AppStorage storage s,
        UserId userId,
        BookKey bookKey,
        OrderId orderId,
        OrderId[] calldata prevCandidates
    ) internal returns (CancelResult memory r) {
        Order storage ord = s.orders[Keys.orderKey(bookKey, orderId)];

        if (UserId.unwrap(ord.ownerId) != UserId.unwrap(userId)) revert NotOrderOwner(orderId);

        Tick tick = ord.tick;
        r.tick = tick;

        uint128 remaining = ord.sharesRemaining;
        if (remaining == 0) {
            r.cancelledShares = 0;
            return r;
        }

        Level storage lvl = s.levels[Keys.levelKey(bookKey, tick)];

        uint32 headRaw = lvl.headOrderId;
        if (headRaw == 0) revert OrderNotFound(orderId);

        // Case 1: head cancel (O(1))
        if (headRaw == OrderId.unwrap(orderId)) {
            ord.sharesRemaining = 0;

            (, bool emptied) = LevelQueue.popHeadIfFilled(s, bookKey, tick);

            lvl.totalShares -= remaining;

            r.cancelledShares = remaining;
            r.levelEmptied = emptied;

            _maybeClearMaskIfEmpty(s, bookKey, tick, emptied);
            return r;
        }

        // Case 2: non-head cancel via candidates (O(N))
        {
            OrderId next = ord.nextOrderId;
            OrderId prevIdFound = _findPrevCandidate(s, bookKey, orderId, prevCandidates);
            if (OrderId.unwrap(prevIdFound) == 0) revert PrevCandidateNotFound(orderId);

            bool emptied2 = _unlinkNonHead(s, bookKey, tick, orderId, prevIdFound, next, remaining);

            r.cancelledShares = remaining;
            r.levelEmptied = emptied2;
            return r;
        }
    }

    function _findPrevCandidate(
        AppStorage storage s,
        BookKey bookKey,
        OrderId orderId,
        OrderId[] calldata prevCandidates
    ) private view returns (OrderId) {
        uint256 len = prevCandidates.length;

        for (uint256 i = 0; i < len; i++) {
            OrderId prevId = prevCandidates[i];
            if (OrderId.unwrap(prevId) == 0) continue;

            Order storage prev = s.orders[Keys.orderKey(bookKey, prevId)];
            if (prev.sharesRemaining == 0) continue;

            if (OrderId.unwrap(prev.nextOrderId) == OrderId.unwrap(orderId)) {
                return prevId;
            }
        }

        return OrderId.wrap(0);
    }

    /// @dev Unlinks a non-head node using its prevId and cached next pointer.
    /// Returns true iff the level became empty after removing remaining shares.
    function _unlinkNonHead(
        AppStorage storage s,
        BookKey bookKey,
        Tick tick,
        OrderId orderId,
        OrderId prevId,
        OrderId nextId,
        uint128 remaining
    ) private returns (bool levelEmptied) {
        Level storage lvl = s.levels[Keys.levelKey(bookKey, tick)];

        // prev.next = next
        s.orders[Keys.orderKey(bookKey, prevId)].nextOrderId = nextId;

        // fix tail if needed
        if (lvl.tailOrderId == OrderId.unwrap(orderId)) {
            lvl.tailOrderId = OrderId.unwrap(prevId);
        }

        // logical delete target
        Order storage ord = s.orders[Keys.orderKey(bookKey, orderId)];
        ord.sharesRemaining = 0;
        ord.nextOrderId = OrderId.wrap(0);

        // aggregates
        lvl.totalShares -= remaining;

        if (lvl.totalShares == 0) {
            lvl.headOrderId = 0;
            lvl.tailOrderId = 0;
            levelEmptied = true;
            _maybeClearMaskIfEmpty(s, bookKey, tick, true);
        }
    }

    // -----------------------------
    // view helper: collect N predecessors ("ancestors")
    // -----------------------------

    function collectPrevCandidates(AppStorage storage s, BookKey bookKey, OrderId targetOrderId, uint256 maxN)
        internal
        view
        returns (OrderId[] memory out)
    {
        if (maxN == 0) return new OrderId[](0);
        if (maxN > CANCEL_CANDIDATES_CAP) maxN = CANCEL_CANDIDATES_CAP;

        Tick tick = s.orders[Keys.orderKey(bookKey, targetOrderId)].tick;
        if (Tick.unwrap(tick) == 0) return new OrderId[](0);

        Level storage lvl = s.levels[Keys.levelKey(bookKey, tick)];

        uint32 headRaw = lvl.headOrderId;
        if (headRaw == 0) return new OrderId[](0);
        if (headRaw == OrderId.unwrap(targetOrderId)) return new OrderId[](0);

        OrderId[] memory ring = new OrderId[](maxN);
        uint256 count = 0;
        uint256 pos = 0;

        uint32 curRaw = headRaw;

        while (curRaw != 0) {
            if (curRaw == OrderId.unwrap(targetOrderId)) {
                uint256 n = count < maxN ? count : maxN;
                out = new OrderId[](n);
                if (n == 0) return out;

                for (uint256 i = 0; i < n; i++) {
                    uint256 idx = (pos + maxN - 1 - i) % maxN;
                    out[i] = ring[idx];
                }
                return out;
            }

            OrderId curId = OrderId.wrap(curRaw);
            Order storage cur = s.orders[Keys.orderKey(bookKey, curId)];

            if (cur.sharesRemaining != 0) {
                ring[pos] = curId;
                pos = (pos + 1) % maxN;
                if (count < maxN) count++;
            }

            curRaw = OrderId.unwrap(cur.nextOrderId);
        }

        return new OrderId[](0);
    }

    function _maybeClearMaskIfEmpty(AppStorage storage s, BookKey bookKey, Tick tick, bool emptied) private {
        if (!emptied) return;

        BookState storage book = s.books[bookKey];
        Side side = BookKeyLib.sideOf(bookKey);

        if (side == Side.Bid) {
            book.bidsMask = MaskLib.clear(book.bidsMask, tick);
        } else {
            book.asksMask = MaskLib.clear(book.asksMask, tick);
        }
    }
}
