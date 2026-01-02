// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlatform} from "./interfaces/IPlatform.sol";

import {PlatformStorage} from "./storage/PlatformStorage.sol";
import {StorageSlot} from "./storage/StorageSlot.sol";
import {Order} from "./types/Structs.sol";
import {UserId, BookKey, Tick, OrderId} from "./types/IdTypes.sol";
import {Side} from "./types/Enums.sol";
import {TooManyCancelCandidates} from "./types/Errors.sol";

import {BookKeyLib} from "./encoding/BookKeyLib.sol";
import {Keys} from "./encoding/Keys.sol";
import {TickLib} from "./encoding/TickLib.sol";

import {OrderBook} from "./core/OrderBook.sol";

contract Platform is IPlatform {

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

    function placeLimit(uint64 marketId, uint8 outcomeId, Side side, Tick limitTick, uint128 sharesRequested)
        external
        returns (uint32 orderIdOr0, uint128 filledShares, uint256 pointsTraded)
    {
        TickLib.check(limitTick);
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side);

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        OrderBook.PlaceResult memory r = OrderBook.placeLimit(s, uid, bookKey, limitTick, sharesRequested);

        if (OrderId.unwrap(r.placedOrderId) != 0) {
            emit OrderPlaced(
                marketId,
                outcomeId,
                UserId.unwrap(uid),
                side,
                OrderId.unwrap(r.placedOrderId),
                Tick.unwrap(limitTick),
                sharesRequested
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

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        OrderBook.TakeResult memory r = OrderBook.take(s, bookKey, limitTick, sharesRequested, minFill);

        emit Take(marketId, outcomeId, UserId.unwrap(uid), side, Tick.unwrap(limitTick), sharesRequested, r.filledShares);
        return (r.filledShares, r.pointsTraded);
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

        emit OrderCancelled(marketId, outcomeId, UserId.unwrap(uid), side, OrderId.unwrap(orderId), Tick.unwrap(r.tick), r.cancelledShares);
        return r.cancelledShares;
    }

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

    /// @notice TEST/DEBUG helper: returns (remaining, requested) for a specific order in a given book.
    /// WARNING: intended for testing/indexing only; remove/guard for production.
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
}
