// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlatform} from "./interfaces/IPlatform.sol";

import {PlatformStorage} from "./storage/PlatformStorage.sol";
import {StorageSlot} from "./storage/StorageSlot.sol";
import {Order} from "./types/Structs.sol";
import {UserId, BookKey, Tick, OrderId} from "./types/IdTypes.sol";
import {Side} from "./types/Enums.sol";
import {MinFillNotMet, TooManyCancelCandidates, UnregisteredUser} from "./types/Errors.sol";

import {BookKeyLib} from "./encoding/BookKeyLib.sol";
import {Keys} from "./encoding/Keys.sol";
import {TickLib} from "./encoding/TickLib.sol";

import {OrderBook} from "./core/OrderBook.sol";
import {Matching} from "./core/Matching.sol";
import {Deposits} from "./core/Deposits.sol";

contract Platform is IPlatform {
    // ==================== User Registry ====================

    function userIdOf(address user) external view returns (uint64) {
        PlatformStorage storage s = StorageSlot.layout();
        return UserId.unwrap(s.userIdOf[user]);
    }

    function userOfId(uint64 id) external view returns (address) {
        PlatformStorage storage s = StorageSlot.layout();
        return s.userOfId[UserId.wrap(id)];
    }

    function register() external returns (uint64 id) {
        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = s.userIdOf[msg.sender];
        if (UserId.unwrap(uid) != 0) return UserId.unwrap(uid);

        uid = _register(s, msg.sender);
        return UserId.unwrap(uid);
    }

    // ==================== Points Deposits & Withdrawals ====================

    function deposit(uint128 amount) external {
        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        Deposits.doDeposit(s, uid, amount);

        emit PointsDeposited(UserId.unwrap(uid), msg.sender, amount);
    }

    function withdraw(uint128 amount) external {
        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = s.userIdOf[msg.sender];

        if (UserId.unwrap(uid) == 0) revert UnregisteredUser();

        Deposits.doWithdraw(s, uid, amount);

        emit PointsWithdrawn(UserId.unwrap(uid), msg.sender, amount);
    }

    // ==================== Shares Deposits & Withdrawals ====================

    function depositShares(uint64 marketId, uint8 outcomeId, uint128 amount) external {
        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        // FIXME: impl proper bookKey / positionId.
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);

        Deposits.doSharesDeposit(s, uid, bookKey, amount);

        emit SharesDeposited(UserId.unwrap(uid), marketId, outcomeId, amount);
    }

    function withdrawShares(uint64 marketId, uint8 outcomeId, uint128 amount) external {
        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = s.userIdOf[msg.sender];

        if (UserId.unwrap(uid) == 0) revert UnregisteredUser();

        // FIXME: impl proper bookKey / positionId.
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);

        Deposits.doSharesWithdraw(s, uid, bookKey, amount);

        emit SharesWithdrawn(UserId.unwrap(uid), marketId, outcomeId, amount);
    }

    // ==================== Trading APIs ====================

    function placeLimit(uint64 marketId, uint8 outcomeId, Side side, Tick limitTick, uint128 sharesRequested)
        external
        returns (uint32 orderIdOr0, uint128 filledShares, uint256 pointsTraded)
    {
        // Validate inputs
        TickLib.check(limitTick);
        require(sharesRequested > 0, "sharesRequested must be > 0");

        BookKey takerBookKey = BookKeyLib.pack(marketId, outcomeId, side);
        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        OrderBook.PlaceResult memory r = OrderBook.placeLimit(s, uid, takerBookKey, limitTick, sharesRequested);
        emit OrderPlaced(
            marketId,
            outcomeId,
            UserId.unwrap(uid),
            side,
            OrderId.unwrap(r.placedOrderId),
            Tick.unwrap(limitTick),
            sharesRequested
        );

        // Match resting portion and get filled amounts
        (uint128 matchedFilled, uint256 matchedPoints) =
            _matchPlacedOrder(s, marketId, outcomeId, side, limitTick, r.placedOrderId, r.restingShares, uid);

        return (OrderId.unwrap(r.placedOrderId), matchedFilled, matchedPoints);
    }

    function take(uint64 marketId, uint8 outcomeId, Side side, Tick limitTick, uint128 sharesRequested, uint128 minFill)
        external
        returns (uint128 filledShares, uint256 pointsTraded)
    {
        // Validate inputs
        TickLib.check(limitTick);
        require(sharesRequested > 0, "sharesRequested must be > 0");

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        uint128 totalFilled = _matchTakeOrder(s, marketId, outcomeId, side, limitTick, sharesRequested, uid);

        if (totalFilled < minFill) revert MinFillNotMet(totalFilled, minFill);

        uint256 totalPointsTraded = uint256(totalFilled) * uint256(Tick.unwrap(limitTick));
        emit Take(marketId, outcomeId, UserId.unwrap(uid), side, Tick.unwrap(limitTick), sharesRequested, totalFilled);
        return (totalFilled, totalPointsTraded);
    }

    function cancel(uint64 marketId, uint8 outcomeId, Side side, OrderId orderId, OrderId[] calldata prevCandidates)
        external
        returns (uint128 cancelledShares)
    {
        if (prevCandidates.length > 16) revert TooManyCancelCandidates();

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        OrderBook.CancelResult memory r = OrderBook.cancel(s, uid, bookKey, orderId, prevCandidates);

        emit OrderCancelled(
            marketId,
            outcomeId,
            UserId.unwrap(uid),
            side,
            OrderId.unwrap(orderId),
            Tick.unwrap(r.tick),
            r.cancelledShares
        );
        return r.cancelledShares;
    }

    // ==================== Views ====================

    function getCancelCandidates(uint64 marketId, uint8 outcomeId, Side side, OrderId targetOrderId, uint256 maxN)
        external
        view
        returns (OrderId[] memory)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);
        PlatformStorage storage s = StorageSlot.layout();

        uint256 n = maxN > 16 ? 16 : maxN;
        if (n == 0) return new OrderId[](0);

        return OrderBook.collectPrevCandidates(s, bookKey, targetOrderId, n);
    }

    function getOrderRemainingAndRequested(uint64 marketId, uint8 outcomeId, Side side, uint32 orderId)
        external
        view
        returns (uint128 remaining, uint128 requested)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);
        PlatformStorage storage s = StorageSlot.layout();
        Order storage o = s.orders[Keys.orderKey(bookKey, OrderId.wrap(orderId))];
        return (o.sharesRemaining, o.requestedShares);
    }

    // ==================== Internal Helpers ====================

    function _getOrRegister(PlatformStorage storage s, address user) internal returns (UserId) {
        UserId uid = s.userIdOf[user];
        if (UserId.unwrap(uid) != 0) return uid;
        return _register(s, user);
    }

    function _register(PlatformStorage storage s, address user) internal returns (UserId uid) {
        UserId next = s.nextUserId;
        if (UserId.unwrap(next) == 0) next = UserId.wrap(1);

        uid = next;

        s.userIdOf[user] = uid;
        s.userOfId[uid] = user;
        s.nextUserId = UserId.wrap(UserId.unwrap(uid) + 1);

        emit UserRegistered(user, UserId.unwrap(uid));
    }

    function _matchPlacedOrder(
        PlatformStorage storage s,
        uint64 marketId,
        uint8 outcomeId,
        Side takerSide,
        Tick limitTick,
        OrderId placedOrderId,
        uint128 restingShares,
        UserId takerUserId
    ) internal returns (uint128 totalFilled, uint256 totalPointsTraded) {
        BookKey makerBookKey = BookKeyLib.pack(marketId, outcomeId, BookKeyLib.opposite(takerSide));
        Side makerSide = BookKeyLib.opposite(takerSide);
        uint128 remaining = restingShares;

        while (remaining > 0) {
            Matching.FillInfo memory fill =
                Matching.matchOneStep(s, makerBookKey, makerSide, placedOrderId, limitTick, remaining);
            if (fill.sharesFilled == 0) break;

            emit Trade(
                marketId,
                UserId.unwrap(s.orders[Keys.orderKey(makerBookKey, fill.makerId)].ownerId),
                UserId.unwrap(takerUserId),
                outcomeId,
                makerSide,
                OrderId.unwrap(fill.makerId),
                OrderId.unwrap(placedOrderId),
                Tick.unwrap(fill.tick),
                fill.sharesFilled,
                uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick))),
                0,
                0 // TODO: fees
            );

            totalFilled += fill.sharesFilled;
            remaining -= fill.sharesFilled;
        }

        totalPointsTraded = uint256(totalFilled) * uint256(Tick.unwrap(limitTick));
        return (totalFilled, totalPointsTraded);
    }

    function _matchTakeOrder(
        PlatformStorage storage s,
        uint64 marketId,
        uint8 outcomeId,
        Side takerSide,
        Tick limitTick,
        uint128 sharesRequested,
        UserId takerUserId
    ) internal returns (uint128 totalFilled) {
        // For take: we match against the opposite side
        Side makerSide = BookKeyLib.opposite(takerSide);
        BookKey makerBookKey = BookKeyLib.pack(marketId, outcomeId, makerSide);
        uint128 remaining = sharesRequested;

        while (remaining > 0) {
            Matching.FillInfo memory fill =
                Matching.matchOneStep(s, makerBookKey, makerSide, OrderId.wrap(0), limitTick, remaining);
            if (fill.sharesFilled == 0) break;

            Order storage makerOrder = s.orders[Keys.orderKey(makerBookKey, fill.makerId)];
            emit Trade(
                marketId,
                UserId.unwrap(makerOrder.ownerId),
                UserId.unwrap(takerUserId),
                outcomeId,
                makerSide,
                OrderId.unwrap(fill.makerId),
                0,
                Tick.unwrap(fill.tick),
                fill.sharesFilled,
                uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick))),
                0,
                0 // TODO: fees
            );

            remaining -= fill.sharesFilled;
        }

        return sharesRequested - remaining;
    }
}
