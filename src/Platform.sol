// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlatform} from "./interfaces/IPlatform.sol";

import {PlatformStorage} from "./storage/PlatformStorage.sol";
import {StorageSlot} from "./storage/StorageSlot.sol";
import {Order} from "./types/Structs.sol";
import {UserId, BookKey, Tick, OrderId} from "./types/IdTypes.sol";
import {Side} from "./types/Enums.sol";
import {MinFillNotMet, TooManyCancelCandidates, UnregisteredUser, InvalidInput} from "./types/Errors.sol";

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
        if (amount == 0) revert InvalidInput();

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        Deposits.doDeposit(s, uid, amount);

        emit PointsDeposited(UserId.unwrap(uid), msg.sender, amount);
    }

    function withdraw(uint128 amount) external {
        if (amount == 0) revert InvalidInput();

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = s.userIdOf[msg.sender];

        if (UserId.unwrap(uid) == 0) revert UnregisteredUser();

        Deposits.doWithdraw(s, uid, amount);

        emit PointsWithdrawn(UserId.unwrap(uid), msg.sender, amount);
    }

    // ==================== Shares Deposits & Withdrawals ====================

    function depositShares(uint64 marketId, uint8 outcomeId, uint128 amount) external {
        if (amount == 0) revert InvalidInput();

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        // FIXME: impl proper bookKey / positionId.
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);

        Deposits.doSharesDeposit(s, uid, bookKey, amount);

        emit SharesDeposited(UserId.unwrap(uid), marketId, outcomeId, amount);
    }

    function withdrawShares(uint64 marketId, uint8 outcomeId, uint128 amount) external {
        if (amount == 0) revert InvalidInput();

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = s.userIdOf[msg.sender];

        if (UserId.unwrap(uid) == 0) revert UnregisteredUser();

        // FIXME: impl proper bookKey / positionId.
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);

        Deposits.doSharesWithdraw(s, uid, bookKey, amount);

        emit SharesWithdrawn(UserId.unwrap(uid), marketId, outcomeId, amount);
    }

    // ==================== Trading APIs ====================

    function placeLimit(uint64 marketId, uint8 outcomeId, uint8 side, uint8 limitTick, uint128 sharesRequested)
        external
        returns (uint32 orderId, uint128 filledShares, uint256 pointsTraded)
    {
        if (sharesRequested == 0) revert InvalidInput();
        if (side > 1) revert InvalidInput();
        {
            Tick tick = Tick.wrap(limitTick);
            TickLib.check(tick);

            PlatformStorage storage s = StorageSlot.layout();
            UserId uid = _getOrRegister(s, msg.sender);

            OrderId placedOrderId =
                OrderBook.placeLimit(s, uid, BookKeyLib.pack(marketId, outcomeId, Side(side)), tick, sharesRequested);

            emit OrderPlaced(
                marketId, outcomeId, UserId.unwrap(uid), side, OrderId.unwrap(placedOrderId), limitTick, sharesRequested
            );

            (filledShares, pointsTraded) =
                _matchPlacedOrder(s, marketId, outcomeId, Side(side), tick, placedOrderId, sharesRequested, uid);

            orderId = OrderId.unwrap(placedOrderId);
        }
    }

    function take(
        uint64 marketId,
        uint8 outcomeId,
        uint8 side,
        uint8 limitTick,
        uint128 sharesRequested,
        uint128 minFill
    ) external returns (uint128 filledShares, uint256 pointsTraded) {
        if (sharesRequested == 0) revert InvalidInput();
        if (side > 1) revert InvalidInput();
        TickLib.check(Tick.wrap(limitTick));

        Side side_ = Side(side);
        Tick tick_ = Tick.wrap(limitTick);

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        uint128 totalFilled = _matchTakeOrder(s, marketId, outcomeId, side_, tick_, sharesRequested, uid);

        if (totalFilled < minFill) revert MinFillNotMet(totalFilled, minFill);

        uint256 totalPointsTraded = uint256(totalFilled) * uint256(limitTick);
        emit Take(marketId, outcomeId, UserId.unwrap(uid), side, limitTick, sharesRequested, totalFilled);
        return (totalFilled, totalPointsTraded);
    }

    function cancel(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId, uint32[] calldata prevCandidates)
        external
        returns (uint128 cancelledShares)
    {
        if (prevCandidates.length > 16) revert TooManyCancelCandidates();
        if (side > 1) revert InvalidInput();

        Side side_ = Side(side);
        OrderId orderId_ = OrderId.wrap(orderId);

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side_);

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        (uint128 cancelledShares,, Tick tick) = OrderBook.cancel(s, uid, bookKey, orderId_, prevCandidates);

        emit OrderCancelled(marketId, outcomeId, UserId.unwrap(uid), side, orderId, Tick.unwrap(tick), cancelledShares);
        return cancelledShares;
    }

    // ==================== Views ====================

    function getCancelCandidates(uint64 marketId, uint8 outcomeId, uint8 side, uint32 targetOrderId, uint256 maxN)
        external
        view
        returns (uint32[] memory)
    {
        if (side > 1) revert InvalidInput();

        Side side_ = Side(side);
        OrderId targetOrderId_ = OrderId.wrap(targetOrderId);

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side_);
        PlatformStorage storage s = StorageSlot.layout();

        uint256 n = maxN > 16 ? 16 : maxN;
        if (n == 0) return new uint32[](0);

        OrderId[] memory candidates = OrderBook.collectPrevCandidates(s, bookKey, targetOrderId_, n);

        // Cast result back to uint32[]
        uint32[] memory result = new uint32[](candidates.length);
        for (uint256 i = 0; i < candidates.length; i++) {
            result[i] = OrderId.unwrap(candidates[i]);
        }
        return result;
    }

    function getOrderRemainingAndRequested(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        external
        view
        returns (uint128 remaining, uint128 requested)
    {
        if (side > 1) revert InvalidInput();

        Side side_ = Side(side);
        OrderId orderId_ = OrderId.wrap(orderId);

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side_);
        PlatformStorage storage s = StorageSlot.layout();
        Order storage o = s.orders[Keys.orderKey(bookKey, orderId_)];
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
                uint8(makerSide),
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
                uint8(makerSide),
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
