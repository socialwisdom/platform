// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AppStorage} from "./storage/Storage.sol";
import {BookKeyLib} from "./lib/BookKeyLib.sol";
import {Keys} from "./lib/Keys.sol";
import {Order} from "./storage/Storage.sol";
import {StorageLib} from "./storage/StorageLib.sol";
import {TickLib} from "./lib/TickLib.sol";
import {UserId, BookKey, Tick, OrderId, Side, TooManyCancelCandidates} from "./types/Types.sol";

import {OrderBook} from "./core/OrderBook.sol";

contract Platform {
    event UserRegistered(address user, uint64 userId);

    event OrderPlaced(
        uint64 indexed marketId,
        uint8 indexed outcomeId,
        Side side,
        uint32 orderId,
        address indexed owner,
        uint8 tick,
        uint128 sharesAmount
    );

    event OrderCancelled(uint64 indexed marketId, uint32 orderId, address indexed owner, uint128 sharesCancelled);

    event Take(
        uint64 indexed marketId,
        uint8 indexed outcomeId,
        Side side,
        address indexed taker,
        uint128 sharesRequested,
        uint128 sharesFilled
    );

    function userIdOf(address user) external view returns (uint64) {
        AppStorage storage s = StorageLib.s();
        return UserId.unwrap(s.userIdOf[user]);
    }

    function userOfId(uint64 id) external view returns (address) {
        AppStorage storage s = StorageLib.s();
        return s.userOfId[UserId.wrap(id)];
    }

    function register() external returns (uint64 id) {
        AppStorage storage s = StorageLib.s();
        UserId uid = s.userIdOf[msg.sender];
        if (UserId.unwrap(uid) != 0) return UserId.unwrap(uid);

        uid = _register(s, msg.sender);
        return UserId.unwrap(uid);
    }

    function _getOrRegister(AppStorage storage s, address user) internal returns (UserId) {
        UserId uid = s.userIdOf[user];
        if (UserId.unwrap(uid) != 0) return uid;
        return _register(s, user);
    }

    function _register(AppStorage storage s, address user) internal returns (UserId uid) {
        UserId next = s.nextUserId;
        if (UserId.unwrap(next) == 0) next = UserId.wrap(1);

        uid = next;

        s.userIdOf[user] = uid;
        s.userOfId[uid] = user;
        s.nextUserId = UserId.wrap(UserId.unwrap(uid) + 1);

        emit UserRegistered(user, UserId.unwrap(uid));
    }

    function placeLimit(uint64 marketId, uint8 outcomeId, Side side, Tick limitTick, uint128 sharesRequested)
        external
        returns (uint32 orderIdOr0, uint128 filledShares, uint256 pointsTraded)
    {
        TickLib.check(limitTick);
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);

        AppStorage storage s = StorageLib.s();
        UserId uid = _getOrRegister(s, msg.sender);

        OrderBook.PlaceResult memory r = OrderBook.placeLimit(s, uid, bookKey, limitTick, sharesRequested);

        if (OrderId.unwrap(r.placedOrderId) != 0) {
            emit OrderPlaced(
                marketId,
                outcomeId,
                side,
                OrderId.unwrap(r.placedOrderId),
                msg.sender,
                Tick.unwrap(limitTick),
                r.restingShares
            );
        }

        return (OrderId.unwrap(r.placedOrderId), r.filledShares, r.pointsTraded);
    }

    function take(uint64 marketId, uint8 outcomeId, Side side, Tick limitTick, uint128 sharesRequested, uint128 minFill)
        external
        returns (uint128 filledShares, uint256 pointsTraded)
    {
        TickLib.check(limitTick);
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);

        AppStorage storage s = StorageLib.s();
        _getOrRegister(s, msg.sender);

        OrderBook.TakeResult memory r = OrderBook.take(s, bookKey, limitTick, sharesRequested, minFill);

        emit Take(marketId, outcomeId, side, msg.sender, sharesRequested, r.filledShares);
        return (r.filledShares, r.pointsTraded);
    }

    function cancel(uint64 marketId, uint8 outcomeId, Side side, OrderId orderId, OrderId[] calldata prevCandidates)
        external
        returns (uint128 cancelledShares)
    {
        if (prevCandidates.length > 16) revert TooManyCancelCandidates();

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);

        AppStorage storage s = StorageLib.s();
        UserId uid = _getOrRegister(s, msg.sender);

        OrderBook.CancelResult memory r = OrderBook.cancel(s, uid, bookKey, orderId, prevCandidates);

        emit OrderCancelled(marketId, OrderId.unwrap(orderId), msg.sender, r.cancelledShares);
        return r.cancelledShares;
    }

    function getCancelCandidates(uint64 marketId, uint8 outcomeId, Side side, OrderId targetOrderId, uint256 maxN)
        external
        view
        returns (OrderId[] memory)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);
        AppStorage storage s = StorageLib.s();

        uint256 n = maxN > 16 ? 16 : maxN;
        if (n == 0) return new OrderId[](0);

        return OrderBook.collectPrevCandidates(s, bookKey, targetOrderId, n);
    }

    /// @notice TEST/DEBUG helper: returns (remaining, requested) for a specific order in a given book.
    /// WARNING: intended for testing/indexing only; remove/guard for production.
    function getOrderRemainingAndRequested(uint64 marketId, uint8 outcomeId, Side side, uint32 orderId)
        external
        view
        returns (uint128 remaining, uint128 requested)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);
        AppStorage storage s = StorageLib.s();
        Order storage o = s.orders[Keys.orderKey(bookKey, OrderId.wrap(orderId))];
        return (o.sharesRemaining, o.requestedShares);
    }
}
