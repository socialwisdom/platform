// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlatform} from "./interfaces/IPlatform.sol";

import {PlatformStorage} from "./storage/PlatformStorage.sol";
import {StorageSlot} from "./storage/StorageSlot.sol";
import {Order, Level} from "./types/Structs.sol";
import {UserId, BookKey, Tick, OrderId} from "./types/IdTypes.sol";
import {Side} from "./types/Enums.sol";
import {MinFillNotMet, TooManyCancelCandidates, UnregisteredUser, InvalidInput} from "./types/Errors.sol";

import {BookKeyLib} from "./encoding/BookKeyLib.sol";
import {Keys} from "./encoding/Keys.sol";
import {TickLib} from "./encoding/TickLib.sol";

import {OrderBook} from "./core/OrderBook.sol";
import {Matching} from "./core/Matching.sol";
import {Deposits} from "./core/Deposits.sol";
import {Accounting} from "./core/Accounting.sol";

contract Platform is IPlatform {
    struct TakeArgs {
        uint64 marketId;
        uint8 outcomeId;
        Side side;
        uint8 limitTick;
        uint128 sharesRequested;
        uint128 minFill;
    }

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

            BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
            if (Side(side) == Side.Bid) {
                uint256 requiredPoints = uint256(sharesRequested) * uint256(limitTick);
                if (requiredPoints > type(uint128).max) revert InvalidInput();
                // casting to 'uint128' is safe because the value is checked against type(uint128).max above
                // forge-lint: disable-next-line(unsafe-typecast)
                Accounting.reservePoints(s, uid, uint128(requiredPoints));
            } else {
                Accounting.reserveShares(s, uid, bookKey, sharesRequested);
            }

            OrderId placedOrderId = OrderBook.placeLimit(s, uid, bookKey, tick, sharesRequested);

            emit OrderPlaced(
                marketId, outcomeId, UserId.unwrap(uid), side, OrderId.unwrap(placedOrderId), limitTick, sharesRequested
            );

            (filledShares, pointsTraded) =
                _matchPlacedOrder(s, marketId, outcomeId, Side(side), tick, placedOrderId, sharesRequested, uid);

            uint128 remainingShares = sharesRequested - filledShares;
            s.orders[Keys.orderKey(bookKey, placedOrderId)].sharesRemaining = remainingShares;

            if (remainingShares != 0) {
                OrderBook.restLimit(s, bookKey, tick, placedOrderId, remainingShares);
            }

            // A new orderId is always allocated and returned (even if fully filled immediately).
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

        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = _getOrRegister(s, msg.sender);

        TakeArgs memory args = TakeArgs({
            marketId: marketId,
            outcomeId: outcomeId,
            side: Side(side),
            limitTick: limitTick,
            sharesRequested: sharesRequested,
            minFill: minFill
        });

        return _take(s, uid, args);
    }

    function _take(PlatformStorage storage s, UserId uid, TakeArgs memory args)
        internal
        returns (uint128 filledShares, uint256 pointsTraded)
    {
        // Reserve principal upfront (market orders never rest).
        if (args.side == Side.Bid) {
            uint256 requiredPoints = uint256(args.sharesRequested) * uint256(args.limitTick);
            if (requiredPoints > type(uint128).max) revert InvalidInput();
            // casting to 'uint128' is safe because the value is checked against type(uint128).max above
            // forge-lint: disable-next-line(unsafe-typecast)
            Accounting.reservePoints(s, uid, uint128(requiredPoints));
        } else {
            BookKey takerBookKey = BookKeyLib.pack(args.marketId, args.outcomeId, args.side);
            Accounting.reserveShares(s, uid, takerBookKey, args.sharesRequested);
        }

        (filledShares, pointsTraded) = _matchTakeOrder(
            s, args.marketId, args.outcomeId, args.side, Tick.wrap(args.limitTick), args.sharesRequested, uid
        );

        if (filledShares < args.minFill) revert MinFillNotMet(filledShares, args.minFill);

        // Release unused principal reservations (market orders never rest).
        uint128 unfilled = args.sharesRequested - filledShares;
        if (unfilled != 0) {
            if (args.side == Side.Bid) {
                uint128 unused = uint128(uint256(unfilled) * uint256(args.limitTick));
                Accounting.releasePoints(s, uid, unused);
            } else {
                BookKey takerBookKey = BookKeyLib.pack(args.marketId, args.outcomeId, args.side);
                Accounting.releaseShares(s, uid, takerBookKey, unfilled);
            }
        }

        emit Take(
            args.marketId,
            args.outcomeId,
            UserId.unwrap(uid),
            uint8(args.side),
            args.limitTick,
            args.sharesRequested,
            filledShares
        );

        return (filledShares, pointsTraded);
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

        Tick tick;
        (cancelledShares,, tick) = OrderBook.cancel(s, uid, bookKey, orderId_, prevCandidates);

        if (side_ == Side.Bid) {
            uint256 reservedU256 = uint256(cancelledShares) * uint256(Tick.unwrap(tick));
            if (reservedU256 > type(uint128).max) revert InvalidInput();
            // casting to 'uint128' is safe because the value is checked against type(uint128).max above
            // forge-lint: disable-next-line(unsafe-typecast)
            Accounting.releasePoints(s, uid, uint128(reservedU256));
        } else {
            Accounting.releaseShares(s, uid, bookKey, cancelledShares);
        }

        emit OrderCancelled(marketId, outcomeId, UserId.unwrap(uid), side, orderId, Tick.unwrap(tick), cancelledShares);
        return cancelledShares;
    }

    function getPointsBalance(address user) external view returns (uint128 free, uint128 reserved) {
        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = s.userIdOf[user];
        if (UserId.unwrap(uid) == 0) return (0, 0);
        return Accounting.getPointsBalance(s, uid);
    }

    function getSharesBalance(uint64 marketId, uint8 outcomeId, address user)
        external
        view
        returns (uint128 free, uint128 reserved)
    {
        PlatformStorage storage s = StorageSlot.layout();
        UserId uid = s.userIdOf[user];
        if (UserId.unwrap(uid) == 0) return (0, 0);
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);
        return Accounting.getSharesBalance(s, uid, bookKey);
    }

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

    function getBookMask(uint64 marketId, uint8 outcomeId, uint8 side) external view returns (uint128 mask) {
        if (side > 1) revert InvalidInput();

        Side side_ = Side(side);
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side_);
        PlatformStorage storage s = StorageSlot.layout();

        return side_ == Side.Bid ? s.books[bookKey].bidsMask : s.books[bookKey].asksMask;
    }

    function getLevel(uint64 marketId, uint8 outcomeId, uint8 side, uint8 tick)
        external
        view
        returns (uint32 headOrderId, uint32 tailOrderId, uint128 totalShares)
    {
        if (side > 1) revert InvalidInput();
        TickLib.check(Tick.wrap(tick));

        Side side_ = Side(side);
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side_);
        PlatformStorage storage s = StorageSlot.layout();

        Level storage lvl = s.levels[Keys.levelKey(bookKey, Tick.wrap(tick))];
        return (lvl.headOrderId, lvl.tailOrderId, lvl.totalShares);
    }

    function getOrder(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        external
        view
        returns (uint64 ownerId, uint32 nextOrderId, uint8 tick, uint128 sharesRemaining, uint128 requestedShares)
    {
        if (side > 1) {
            revert InvalidInput();
        }

        Side side_ = Side(side);
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, side_);
        PlatformStorage storage s = StorageSlot.layout();

        Order storage o = s.orders[Keys.orderKey(bookKey, OrderId.wrap(orderId))];
        return (
            UserId.unwrap(o.ownerId),
            OrderId.unwrap(o.nextOrderId),
            Tick.unwrap(o.tick),
            o.sharesRemaining,
            o.requestedShares
        );
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

        Matching.MatchContext memory ctx = Matching.MatchContext({
            marketId: marketId,
            outcomeId: outcomeId,
            takerSide: takerSide,
            limitTick: limitTick,
            placedOrderId: placedOrderId,
            takerUserId: takerUserId,
            makerBookKey: makerBookKey,
            makerSide: makerSide,
            isTakerLimit: true
        });

        while (remaining > 0) {
            Matching.FillInfo memory fill =
                Matching.matchOneStep(s, makerBookKey, makerSide, placedOrderId, limitTick, remaining);
            if (fill.sharesFilled == 0) break;

            _processMatch(s, ctx, fill);

            totalFilled += fill.sharesFilled;
            totalPointsTraded += uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick));
            remaining -= fill.sharesFilled;
        }
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
    ) internal returns (uint128 totalFilled, uint256 totalPointsTraded) {
        // For take: we match against the opposite side
        Side makerSide = BookKeyLib.opposite(takerSide);
        BookKey makerBookKey = BookKeyLib.pack(marketId, outcomeId, makerSide);
        uint128 remaining = sharesRequested;

        Matching.MatchContext memory ctx = Matching.MatchContext({
            marketId: marketId,
            outcomeId: outcomeId,
            takerSide: takerSide,
            limitTick: limitTick,
            placedOrderId: OrderId.wrap(0),
            takerUserId: takerUserId,
            makerBookKey: makerBookKey,
            makerSide: makerSide,
            isTakerLimit: false
        });

        while (remaining > 0) {
            Matching.FillInfo memory fill =
                Matching.matchOneStep(s, makerBookKey, makerSide, OrderId.wrap(0), limitTick, remaining);
            if (fill.sharesFilled == 0) break;

            _processMatch(s, ctx, fill);

            totalPointsTraded += uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick));

            remaining -= fill.sharesFilled;
        }

        return (sharesRequested - remaining, totalPointsTraded);
    }

    function _processMatch(PlatformStorage storage s, Matching.MatchContext memory ctx, Matching.FillInfo memory fill)
        private
    {
        Order storage makerOrder = s.orders[Keys.orderKey(ctx.makerBookKey, fill.makerId)];
        UserId makerId = makerOrder.ownerId;

        // Maker (Resting)
        if (ctx.makerSide == Side.Bid) {
            uint128 cost = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick)));
            Accounting.consumeReservedPoints(s, makerId, cost);
            // Shares always credited to Ask side (canonical asset key)
            BookKey sharesKey = BookKeyLib.pack(ctx.marketId, ctx.outcomeId, Side.Ask);
            Accounting.addFreeShares(s, makerId, sharesKey, fill.sharesFilled);
        } else {
            Accounting.consumeReservedShares(s, makerId, ctx.makerBookKey, fill.sharesFilled);
            uint128 proceeds = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick)));
            Accounting.addFreePoints(s, makerId, proceeds);
        }

        // Taker
        if (ctx.isTakerLimit) {
            // Limit Order Logic
            if (ctx.takerSide == Side.Bid) {
                uint128 cost = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick)));
                uint128 reserved = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(ctx.limitTick)));

                Accounting.consumeReservedPoints(s, ctx.takerUserId, cost);
                if (reserved > cost) {
                    Accounting.releasePoints(s, ctx.takerUserId, reserved - cost);
                }
                // Shares always credited to Ask side (canonical asset key)
                BookKey sharesKey = BookKeyLib.pack(ctx.marketId, ctx.outcomeId, Side.Ask);
                Accounting.addFreeShares(s, ctx.takerUserId, sharesKey, fill.sharesFilled);
            } else {
                BookKey takerBookKey = BookKeyLib.pack(ctx.marketId, ctx.outcomeId, ctx.takerSide);
                Accounting.consumeReservedShares(s, ctx.takerUserId, takerBookKey, fill.sharesFilled);
                uint128 proceeds = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick)));
                Accounting.addFreePoints(s, ctx.takerUserId, proceeds);
            }
        } else {
            // Market Order Logic
            if (ctx.takerSide == Side.Bid) {
                uint128 cost = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick)));
                uint128 reserved = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(ctx.limitTick)));

                Accounting.consumeReservedPoints(s, ctx.takerUserId, cost);
                if (reserved > cost) {
                    Accounting.releasePoints(s, ctx.takerUserId, reserved - cost);
                }

                // Shares always credited to Ask side (canonical asset key)
                BookKey sharesKey = BookKeyLib.pack(ctx.marketId, ctx.outcomeId, Side.Ask);
                Accounting.addFreeShares(s, ctx.takerUserId, sharesKey, fill.sharesFilled);
            } else {
                BookKey takerBookKey = BookKeyLib.pack(ctx.marketId, ctx.outcomeId, ctx.takerSide);
                Accounting.consumeReservedShares(s, ctx.takerUserId, takerBookKey, fill.sharesFilled);

                uint128 proceeds = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick)));
                Accounting.addFreePoints(s, ctx.takerUserId, proceeds);
            }
        }

        emit Trade(
            ctx.marketId,
            UserId.unwrap(makerId),
            UserId.unwrap(ctx.takerUserId),
            ctx.outcomeId,
            uint8(ctx.makerSide),
            OrderId.unwrap(fill.makerId),
            OrderId.unwrap(ctx.placedOrderId),
            Tick.unwrap(fill.tick),
            fill.sharesFilled,
            uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick))),
            0,
            0 // TODO: fees
        );
    }
}
