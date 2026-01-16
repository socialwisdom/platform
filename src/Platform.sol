// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlatform} from "./interfaces/IPlatform.sol";

import {PlatformStorage} from "./storage/PlatformStorage.sol";
import {StorageSlot} from "./storage/StorageSlot.sol";
import {Order, Level, Market} from "./types/Structs.sol";
import {UserId, BookKey, Tick, OrderId} from "./types/IdTypes.sol";
import {Side, MarketState} from "./types/Enums.sol";
import {
    MinFillNotMet,
    TooManyCancelCandidates,
    UnregisteredUser,
    InvalidInput,
    Unauthorized,
    MarketNotFound,
    InvalidOutcomeId,
    MarketNotActive
} from "./types/Errors.sol";

import {BookKeyLib} from "./encoding/BookKeyLib.sol";
import {Keys} from "./encoding/Keys.sol";
import {TickLib} from "./encoding/TickLib.sol";

import {OrderBook} from "./core/OrderBook.sol";
import {Matching} from "./core/Matching.sol";
import {Deposits} from "./core/Deposits.sol";
import {Accounting} from "./core/Accounting.sol";
import {Markets} from "./core/Markets.sol";

contract Platform is IPlatform {
    uint64 public constant RESOLVE_FINALIZE_DELAY = 1 hours;

    constructor() {
        PlatformStorage storage s = StorageSlot.layout();
        if (s.owner == address(0)) {
            s.owner = msg.sender;
        }
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
        TickLib.check(Tick.wrap(limitTick));

        PlatformStorage storage s = StorageSlot.layout();
        _requireActiveMarket(s, marketId, outcomeId);
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

        OrderId placedOrderId = OrderBook.placeLimit(s, uid, bookKey, Tick.wrap(limitTick), sharesRequested);

        emit OrderPlaced(
            marketId, outcomeId, UserId.unwrap(uid), side, OrderId.unwrap(placedOrderId), limitTick, sharesRequested
        );

        (filledShares, pointsTraded) =
            _matchOrder(s, marketId, outcomeId, Side(side), Tick.wrap(limitTick), placedOrderId, sharesRequested, uid);

        s.orders[Keys.orderKey(bookKey, placedOrderId)].sharesRemaining = sharesRequested - filledShares;

        if (filledShares < sharesRequested) {
            OrderBook.restLimit(s, bookKey, Tick.wrap(limitTick), placedOrderId, sharesRequested - filledShares);
        }

        orderId = OrderId.unwrap(placedOrderId);
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
        _requireActiveMarket(s, marketId, outcomeId);
        UserId uid = _getOrRegister(s, msg.sender);

        // Reserve principal upfront (market orders never rest).
        if (Side(side) == Side.Bid) {
            uint256 requiredPoints = uint256(sharesRequested) * uint256(limitTick);
            if (requiredPoints > type(uint128).max) revert InvalidInput();
            // casting to 'uint128' is safe because the value is checked against type(uint128).max above
            // forge-lint: disable-next-line(unsafe-typecast)
            Accounting.reservePoints(s, uid, uint128(requiredPoints));
        } else {
            Accounting.reserveShares(s, uid, BookKeyLib.pack(marketId, outcomeId, Side(side)), sharesRequested);
        }

        (filledShares, pointsTraded) = _matchOrder(
            s, marketId, outcomeId, Side(side), Tick.wrap(limitTick), OrderId.wrap(0), sharesRequested, uid
        );

        if (filledShares < minFill) revert MinFillNotMet(filledShares, minFill);

        // Release unused principal reservations (market orders never rest).
        if (filledShares < sharesRequested) {
            uint128 unfilled = sharesRequested - filledShares;
            if (Side(side) == Side.Bid) {
                Accounting.releasePoints(s, uid, uint128(uint256(unfilled) * uint256(limitTick)));
            } else {
                Accounting.releaseShares(s, uid, BookKeyLib.pack(marketId, outcomeId, Side(side)), unfilled);
            }
        }

        emit Take(marketId, outcomeId, UserId.unwrap(uid), side, limitTick, sharesRequested, filledShares);

        return (filledShares, pointsTraded);
    }

    function cancel(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId, uint32[] calldata prevCandidates)
        external
        returns (uint128 cancelledShares)
    {
        if (prevCandidates.length > 16) revert TooManyCancelCandidates();
        if (side > 1) revert InvalidInput();

        PlatformStorage storage s = StorageSlot.layout();
        _requireMarketExistsAndOutcome(s, marketId, outcomeId);
        UserId uid = _getOrRegister(s, msg.sender);

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));

        Tick tick;
        (cancelledShares,, tick) = OrderBook.cancel(s, uid, bookKey, OrderId.wrap(orderId), prevCandidates);

        if (Side(side) == Side.Bid) {
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

    // ==================== Market APIs ====================

    function createMarket(
        address resolver,
        uint8 outcomesCount,
        uint64 expirationAt,
        bool allowEarlyResolve,
        bytes32 feeParams,
        bytes32 questionHash,
        bytes32 outcomesHash,
        string calldata question,
        string[] calldata outcomeLabels,
        string calldata resolutionRules
    ) external returns (uint64 marketId) {
        PlatformStorage storage s = StorageSlot.layout();
        _onlyOwner(s);

        UserId creatorId = _getOrRegister(s, msg.sender);
        UserId resolverId = _getOrRegister(s, resolver);

        marketId = Markets.createMarket(
            s,
            creatorId,
            resolverId,
            outcomesCount,
            expirationAt,
            allowEarlyResolve,
            feeParams,
            questionHash,
            outcomesHash
        );

        emit MarketCreated(
            marketId,
            UserId.unwrap(creatorId),
            UserId.unwrap(resolverId),
            expirationAt,
            allowEarlyResolve,
            questionHash,
            outcomesHash,
            question,
            outcomeLabels,
            resolutionRules
        );
    }

    function resolveMarket(uint64 marketId, uint8 winningOutcomeId) external {
        PlatformStorage storage s = StorageSlot.layout();
        _requireMarketExistsAndOutcome(s, marketId, winningOutcomeId);

        Market storage m = s.markets[marketId];
        _onlyResolver(s, m);

        Markets.resolveMarket(s, marketId, winningOutcomeId);
        emit MarketResolved(marketId, winningOutcomeId, uint64(block.timestamp));
    }

    function finalizeMarket(uint64 marketId) external {
        PlatformStorage storage s = StorageSlot.layout();
        _requireMarketExists(s, marketId);

        Market storage m = s.markets[marketId];
        _onlyResolver(s, m);

        Markets.finalizeMarket(s, marketId, RESOLVE_FINALIZE_DELAY);
        emit MarketFinalized(marketId, uint64(block.timestamp));
    }

    // ==================== Market Views ====================

    function getMarket(uint64 marketId)
        external
        view
        returns (
            uint64 creatorId,
            uint64 resolverId,
            uint8 outcomesCount,
            uint64 expirationAt,
            bool allowEarlyResolve,
            bytes32 feeParams,
            bytes32 questionHash,
            bytes32 outcomesHash,
            bool resolved,
            bool finalized,
            uint8 winningOutcomeId
        )
    {
        PlatformStorage storage s = StorageSlot.layout();
        _requireMarketExists(s, marketId);

        Market storage m = s.markets[marketId];
        return (
            m.creatorId,
            m.resolverId,
            m.outcomesCount,
            m.expirationAt,
            m.allowEarlyResolve,
            m.feeParams,
            m.questionHash,
            m.outcomesHash,
            m.resolved,
            m.finalized,
            m.winningOutcomeId
        );
    }

    function getMarketState(uint64 marketId) external view returns (uint8) {
        PlatformStorage storage s = StorageSlot.layout();
        _requireMarketExists(s, marketId);

        Market storage m = s.markets[marketId];
        return uint8(Markets.deriveState(m));
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

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage storage s = StorageSlot.layout();

        uint256 n = maxN > 16 ? 16 : maxN;
        if (n == 0) return new uint32[](0);

        OrderId[] memory candidates = OrderBook.collectPrevCandidates(s, bookKey, OrderId.wrap(targetOrderId), n);

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

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage storage s = StorageSlot.layout();
        Order storage o = s.orders[Keys.orderKey(bookKey, OrderId.wrap(orderId))];
        return (o.sharesRemaining, o.requestedShares);
    }

    function getBookMask(uint64 marketId, uint8 outcomeId, uint8 side) external view returns (uint128 mask) {
        if (side > 1) revert InvalidInput();

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage storage s = StorageSlot.layout();

        return Side(side) == Side.Bid ? s.books[bookKey].bidsMask : s.books[bookKey].asksMask;
    }

    function getLevel(uint64 marketId, uint8 outcomeId, uint8 side, uint8 tick)
        external
        view
        returns (uint32 headOrderId, uint32 tailOrderId, uint128 totalShares)
    {
        if (side > 1) revert InvalidInput();
        TickLib.check(Tick.wrap(tick));

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
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

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
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

    function _onlyOwner(PlatformStorage storage s) internal view {
        if (s.owner != msg.sender) revert Unauthorized();
    }

    function _onlyResolver(PlatformStorage storage s, Market storage m) internal view {
        UserId uid = s.userIdOf[msg.sender];
        if (UserId.unwrap(uid) == 0 || m.resolverId != UserId.unwrap(uid)) {
            revert Unauthorized();
        }
    }

    function _requireMarketExists(PlatformStorage storage s, uint64 marketId) internal view {
        if (!Markets.exists(s, marketId)) revert MarketNotFound(marketId);
    }

    function _requireMarketExistsAndOutcome(PlatformStorage storage s, uint64 marketId, uint8 outcomeId) internal view {
        _requireMarketExists(s, marketId);
        Market storage m = s.markets[marketId];
        if (outcomeId >= m.outcomesCount) revert InvalidOutcomeId(outcomeId, m.outcomesCount);
    }

    function _requireActiveMarket(PlatformStorage storage s, uint64 marketId, uint8 outcomeId) internal view {
        _requireMarketExistsAndOutcome(s, marketId, outcomeId);
        Market storage m = s.markets[marketId];
        if (Markets.deriveState(m) != MarketState.Active) revert MarketNotActive(marketId);
    }

    function _matchOrder(
        PlatformStorage storage s,
        uint64 marketId,
        uint8 outcomeId,
        Side takerSide,
        Tick limitTick,
        OrderId takerOrderId,
        uint128 sharesRequested,
        UserId takerUserId
    ) internal returns (uint128 totalFilled, uint256 totalPointsTraded) {
        Side makerSide = BookKeyLib.opposite(takerSide);
        BookKey makerBookKey = BookKeyLib.pack(marketId, outcomeId, makerSide);
        uint128 remaining = sharesRequested;

        while (remaining > 0) {
            Matching.FillInfo memory fill =
                Matching.matchOneStep(s, makerBookKey, makerSide, takerOrderId, limitTick, remaining);
            if (fill.sharesFilled == 0) break;

            _processMatch(
                s, marketId, outcomeId, takerSide, limitTick, takerOrderId, takerUserId, makerBookKey, makerSide, fill
            );

            totalFilled += fill.sharesFilled;
            totalPointsTraded += uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick));
            remaining -= fill.sharesFilled;
        }
        return (totalFilled, totalPointsTraded);
    }

    function _processMatch(
        PlatformStorage storage s,
        uint64 marketId,
        uint8 outcomeId,
        Side takerSide,
        Tick limitTick,
        OrderId placedOrderId,
        UserId takerUserId,
        BookKey makerBookKey,
        Side makerSide,
        Matching.FillInfo memory fill
    ) private {
        Order storage makerOrder = s.orders[Keys.orderKey(makerBookKey, fill.makerId)];
        UserId makerId = makerOrder.ownerId;

        // Precompute amounts used by both maker and taker
        uint128 executionValue = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(fill.tick)));
        BookKey sharesKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);

        // Maker (Resting) - always settled at execution tick
        if (makerSide == Side.Bid) {
            Accounting.consumeReservedPoints(s, makerId, executionValue);
            Accounting.addFreeShares(s, makerId, sharesKey, fill.sharesFilled);
        } else {
            Accounting.consumeReservedShares(s, makerId, makerBookKey, fill.sharesFilled);
            Accounting.addFreePoints(s, makerId, executionValue);
        }

        // Taker - logic is identical for limit and market orders
        if (takerSide == Side.Bid) {
            uint128 reserved = uint128(uint256(fill.sharesFilled) * uint256(Tick.unwrap(limitTick)));
            Accounting.consumeReservedPoints(s, takerUserId, executionValue);
            if (reserved > executionValue) {
                Accounting.releasePoints(s, takerUserId, reserved - executionValue);
            }
            Accounting.addFreeShares(s, takerUserId, sharesKey, fill.sharesFilled);
        } else {
            BookKey takerBookKey = BookKeyLib.pack(marketId, outcomeId, takerSide);
            Accounting.consumeReservedShares(s, takerUserId, takerBookKey, fill.sharesFilled);
            Accounting.addFreePoints(s, takerUserId, executionValue);
        }

        emit Trade(
            marketId,
            UserId.unwrap(makerId),
            UserId.unwrap(takerUserId),
            outcomeId,
            uint8(makerSide),
            OrderId.unwrap(fill.makerId),
            OrderId.unwrap(placedOrderId),
            Tick.unwrap(fill.tick),
            fill.sharesFilled,
            executionValue,
            0,
            0 // TODO: fees
        );
    }
}
