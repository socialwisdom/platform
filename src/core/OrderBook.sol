// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {BookState, Level, Order} from "../types/Structs.sol";
import {BookKey, Tick, OrderId, UserId} from "../types/IdTypes.sol";
import {Side} from "../types/Enums.sol";
import {NotOrderOwner, OrderNotFound, PrevCandidateNotFound} from "../types/Errors.sol";
import {BookKeyLib} from "../encoding/BookKeyLib.sol";
import {Keys} from "../encoding/Keys.sol";
import {Masks} from "../encoding/Masks.sol";
import {LevelQueue} from "./LevelQueue.sol";

library OrderBook {
    uint256 internal constant CANCEL_CANDIDATES_CAP = 16;

    // -----------------------------
    // placeLimit
    // -----------------------------

    // TODO: fix book key usage
    function placeLimit(
        PlatformStorage storage s,
        UserId userId,
        BookKey takerBookKey,
        Tick limitTick,
        uint128 sharesRequested
    ) internal returns (OrderId placedOrderId) {
        uint128 remaining = sharesRequested;

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
            book.bidsMask = Masks.set(book.bidsMask, limitTick);
        } else {
            book.asksMask = Masks.set(book.asksMask, limitTick);
        }

        return newId;
    }

    // -----------------------------
    // cancel (with candidates)
    // -----------------------------

    // TODO: check cancellation status and/or update it
    function cancel(
        PlatformStorage storage s,
        UserId userId,
        BookKey bookKey,
        OrderId orderId,
        uint32[] calldata prevCandidates
    ) internal returns (uint128 cancelledShares, bool levelEmptied, Tick tick) {
        Order storage ord = s.orders[Keys.orderKey(bookKey, orderId)];

        if (UserId.unwrap(ord.ownerId) != UserId.unwrap(userId)) revert NotOrderOwner(orderId);

        tick = ord.tick;

        uint128 remaining = ord.sharesRemaining;
        if (remaining == 0) {
            cancelledShares = 0;
            return (cancelledShares, false, tick);
        }

        Level storage lvl = s.levels[Keys.levelKey(bookKey, tick)];

        uint32 headRaw = lvl.headOrderId;
        if (headRaw == 0) revert OrderNotFound(orderId);

        // Case 1: head cancel (O(1))
        if (headRaw == OrderId.unwrap(orderId)) {
            ord.sharesRemaining = 0;

            (, bool emptied) = LevelQueue.popHeadIfFilled(s, bookKey, tick);

            lvl.totalShares -= remaining;

            cancelledShares = remaining;
            levelEmptied = emptied;

            _maybeClearMaskIfEmpty(s, bookKey, tick, emptied);
            return (cancelledShares, levelEmptied, tick);
        }

        // Case 2: non-head cancel via candidates (O(N))
        {
            OrderId next = ord.nextOrderId;
            OrderId prevIdFound = _findPrevCandidate(s, bookKey, orderId, prevCandidates);
            if (OrderId.unwrap(prevIdFound) == 0) revert PrevCandidateNotFound(orderId);

            levelEmptied = _unlinkNonHead(s, bookKey, tick, orderId, prevIdFound, next, remaining);

            cancelledShares = remaining;
            return (cancelledShares, levelEmptied, tick);
        }
    }

    function _findPrevCandidate(
        PlatformStorage storage s,
        BookKey bookKey,
        OrderId orderId,
        uint32[] calldata prevCandidates
    ) private view returns (OrderId) {
        uint256 len = prevCandidates.length;

        for (uint256 i = 0; i < len; i++) {
            OrderId prevId = OrderId.wrap(prevCandidates[i]);
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
        PlatformStorage storage s,
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

    function collectPrevCandidates(PlatformStorage storage s, BookKey bookKey, OrderId targetOrderId, uint256 maxN)
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

    function _maybeClearMaskIfEmpty(PlatformStorage storage s, BookKey bookKey, Tick tick, bool emptied) private {
        if (!emptied) return;

        BookState storage book = s.books[bookKey];
        Side side = BookKeyLib.sideOf(bookKey);

        if (side == Side.Bid) {
            book.bidsMask = Masks.clear(book.bidsMask, tick);
        } else {
            book.asksMask = Masks.clear(book.asksMask, tick);
        }
    }
}
