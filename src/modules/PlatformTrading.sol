// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITrading} from "../interfaces/ITrading.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {Market, Order, Level} from "../types/Structs.sol";
import {UserId, BookKey, Tick, OrderId} from "../types/IdTypes.sol";
import {Side, MarketState} from "../types/Enums.sol";
import {MinFillNotMet, InvalidInput, MarketNotFound, InvalidOutcomeId, MarketNotActive} from "../types/Errors.sol";

import {BookKeyLib} from "../encoding/BookKeyLib.sol";
import {Keys} from "../encoding/Keys.sol";

import {OrderBook} from "../core/OrderBook.sol";
import {Matching} from "../core/Matching.sol";
import {Accounting} from "../core/Accounting.sol";
import {Fees} from "../core/Fees.sol";
import {Markets} from "../core/Markets.sol";

/// @notice Internal trading and order book logic.
abstract contract PlatformTrading {
    // ==================== ITrading ====================

    // ==================== Write API ====================

    function _placeLimit(
        UserId uid,
        uint64 marketId,
        uint8 outcomeId,
        uint8 side,
        uint8 limitTick,
        uint128 sharesRequested
    ) internal returns (uint32 orderId, uint128 filledShares, uint256 pointsTraded) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _tradingRequireActiveMarket(marketId, outcomeId);

        (uint16 makerFeeBps, uint16 takerFeeBps) = _getMarketFeeBps(marketId);
        bool feeExempt = _isFeeExempt(uid);

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        if (Side(side) == Side.Bid) {
            uint16 reserveFeeBps = feeExempt ? 0 : (makerFeeBps >= takerFeeBps ? makerFeeBps : takerFeeBps);
            _reserveBidWithFee(s, uid, Tick.wrap(limitTick), sharesRequested, reserveFeeBps);
        } else {
            Accounting.reserveShares(s, uid, bookKey, sharesRequested);
        }

        OrderId placedOrderId = OrderBook.placeLimit(s, uid, bookKey, Tick.wrap(limitTick), sharesRequested);
        emit ITrading.OrderPlaced(
            marketId, outcomeId, UserId.unwrap(uid), side, OrderId.unwrap(placedOrderId), limitTick, sharesRequested
        );

        (filledShares, pointsTraded) =
            _matchOrder(marketId, outcomeId, Side(side), Tick.wrap(limitTick), placedOrderId, sharesRequested, uid);

        s.orders[Keys.orderKey(bookKey, placedOrderId)].sharesRemaining = sharesRequested - filledShares;

        if (filledShares < sharesRequested) {
            OrderBook.restLimit(s, bookKey, Tick.wrap(limitTick), placedOrderId, sharesRequested - filledShares);
        }

        orderId = OrderId.unwrap(placedOrderId);
    }

    function _take(
        UserId uid,
        uint64 marketId,
        uint8 outcomeId,
        uint8 side,
        uint8 limitTick,
        uint128 sharesRequested,
        uint128 minFill
    ) internal returns (uint128 filledShares, uint256 pointsTraded) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _tradingRequireActiveMarket(marketId, outcomeId);

        (, uint16 takerFeeBps) = _getMarketFeeBps(marketId);
        bool feeExempt = _isFeeExempt(uid);

        // Reserve principal upfront (market orders never rest).
        if (Side(side) == Side.Bid) {
            uint16 reserveFeeBps = feeExempt ? 0 : takerFeeBps;
            _reserveBidWithFee(s, uid, Tick.wrap(limitTick), sharesRequested, reserveFeeBps);
        } else {
            Accounting.reserveShares(s, uid, BookKeyLib.pack(marketId, outcomeId, Side(side)), sharesRequested);
        }

        (filledShares, pointsTraded) =
            _matchOrder(marketId, outcomeId, Side(side), Tick.wrap(limitTick), OrderId.wrap(0), sharesRequested, uid);

        if (filledShares < minFill) revert MinFillNotMet(filledShares, minFill);

        // Release unused principal reservations (market orders never rest).
        if (filledShares < sharesRequested) {
            uint128 unfilled = sharesRequested - filledShares;
            if (Side(side) == Side.Bid) {
                uint16 releaseFeeBps = feeExempt ? 0 : takerFeeBps;
                _releaseBidReservation(s, uid, Tick.wrap(limitTick), unfilled, releaseFeeBps);
            } else {
                Accounting.releaseShares(s, uid, BookKeyLib.pack(marketId, outcomeId, Side(side)), unfilled);
            }
        }

        emit ITrading.Take(marketId, outcomeId, UserId.unwrap(uid), side, limitTick, sharesRequested, filledShares);

        return (filledShares, pointsTraded);
    }

    function _cancel(
        UserId uid,
        uint64 marketId,
        uint8 outcomeId,
        uint8 side,
        uint32 orderId,
        uint32[] calldata prevCandidates
    ) internal returns (uint128 cancelledShares) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _tradingRequireMarketExistsAndOutcome(marketId, outcomeId);

        (uint16 makerFeeBps, uint16 takerFeeBps) = _getMarketFeeBps(marketId);
        bool feeExempt = _isFeeExempt(uid);

        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));

        Tick tick;
        (cancelledShares,, tick) = OrderBook.cancel(s, uid, bookKey, OrderId.wrap(orderId), prevCandidates);

        if (Side(side) == Side.Bid) {
            uint16 reservedFeeBps = feeExempt ? 0 : (makerFeeBps >= takerFeeBps ? makerFeeBps : takerFeeBps);
            _releaseBidReservation(s, uid, tick, cancelledShares, reservedFeeBps);
        } else {
            Accounting.releaseShares(s, uid, bookKey, cancelledShares);
        }

        emit ITrading.OrderCancelled(
            marketId, outcomeId, UserId.unwrap(uid), side, orderId, Tick.unwrap(tick), cancelledShares
        );
        return cancelledShares;
    }

    // ==================== Read API ====================

    function _getCancelCandidates(uint64 marketId, uint8 outcomeId, uint8 side, uint32 targetOrderId, uint256 maxN)
        internal
        view
        returns (uint32[] memory)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));

        uint256 n = maxN > 16 ? 16 : maxN;
        if (n == 0) return new uint32[](0);

        PlatformStorage.Layout storage s = PlatformStorage.layout();
        OrderId[] memory candidates = OrderBook.collectPrevCandidates(s, bookKey, OrderId.wrap(targetOrderId), n);

        // Cast result back to uint32[]
        uint32[] memory result = new uint32[](candidates.length);
        for (uint256 i = 0; i < candidates.length; i++) {
            result[i] = OrderId.unwrap(candidates[i]);
        }
        return result;
    }

    function _getOrderRemainingAndRequested(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        internal
        view
        returns (uint128 remaining, uint128 requested)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Order storage o = s.orders[Keys.orderKey(bookKey, OrderId.wrap(orderId))];
        return (o.sharesRemaining, o.requestedShares);
    }

    function _getBookMask(uint64 marketId, uint8 outcomeId, uint8 side) internal view returns (uint128 mask) {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();

        return Side(side) == Side.Bid ? s.books[bookKey].bidsMask : s.books[bookKey].asksMask;
    }

    function _getLevel(uint64 marketId, uint8 outcomeId, uint8 side, uint8 tick)
        internal
        view
        returns (uint32 headOrderId, uint32 tailOrderId, uint128 totalShares)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();

        Level storage lvl = s.levels[Keys.levelKey(bookKey, Tick.wrap(tick))];
        return (lvl.headOrderId, lvl.tailOrderId, lvl.totalShares);
    }

    function _getOrder(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        internal
        view
        returns (uint64 ownerId, uint32 nextOrderId, uint8 tick, uint128 sharesRemaining, uint128 requestedShares)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();

        Order storage o = s.orders[Keys.orderKey(bookKey, OrderId.wrap(orderId))];
        return (
            UserId.unwrap(o.ownerId),
            OrderId.unwrap(o.nextOrderId),
            Tick.unwrap(o.tick),
            o.sharesRemaining,
            o.requestedShares
        );
    }

    // ==================== Internal Matching Helpers ====================

    function _matchOrder(
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

        PlatformStorage.Layout storage s = PlatformStorage.layout();
        while (remaining > 0) {
            Matching.FillInfo memory fill =
                Matching.matchOneStep(s, makerBookKey, makerSide, takerOrderId, limitTick, remaining);
            if (fill.sharesFilled == 0) break;

            uint128 pointsExchanged = _processMatch(
                marketId, outcomeId, takerSide, limitTick, takerOrderId, takerUserId, makerBookKey, makerSide, fill
            );

            totalFilled += fill.sharesFilled;
            totalPointsTraded += pointsExchanged;
            remaining -= fill.sharesFilled;
        }
        return (totalFilled, totalPointsTraded);
    }

    function _processMatch(
        uint64 marketId,
        uint8 outcomeId,
        Side takerSide,
        Tick limitTick,
        OrderId placedOrderId,
        UserId takerUserId,
        BookKey makerBookKey,
        Side makerSide,
        Matching.FillInfo memory fill
    ) private returns (uint128 pointsExchanged) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Order storage makerOrder = s.orders[Keys.orderKey(makerBookKey, fill.makerId)];
        UserId makerId = makerOrder.ownerId;

        (uint16 makerFeeBps, uint16 takerFeeBps) = _getMarketFeeBps(marketId);
        uint16 maxFeeBps = makerFeeBps >= takerFeeBps ? makerFeeBps : takerFeeBps;

        bool makerExempt = _isFeeExempt(makerId);
        bool takerExempt = _isFeeExempt(takerUserId);

        // Precompute amounts used by both maker and taker (price math per spec)
        (uint128 sellerGross, uint128 buyerPaid, uint128 dust) = Fees.computeNotional(fill.sharesFilled, fill.tick);
        pointsExchanged = sellerGross;

        uint128 makerFee = makerExempt ? 0 : Fees.computeFee(sellerGross, makerFeeBps);
        uint128 takerFee = takerExempt ? 0 : Fees.computeFee(sellerGross, takerFeeBps);

        if (dust > 0) {
            uint256 newDust = uint256(s.protocolDustPoints) + uint256(dust);
            if (newDust > type(uint128).max) revert InvalidInput();
            // casting to 'uint128' is safe because of the bound check above
            // forge-lint: disable-next-line(unsafe-typecast)
            s.protocolDustPoints = uint128(newDust);
        }

        uint256 feeAccrual = uint256(makerFee) + uint256(takerFee);
        if (feeAccrual > 0) {
            uint256 newFees = uint256(s.markets[marketId].tradingFeesPoints) + feeAccrual;
            if (newFees > type(uint128).max) revert InvalidInput();
            // casting to 'uint128' is safe because of the bound check above
            // forge-lint: disable-next-line(unsafe-typecast)
            s.markets[marketId].tradingFeesPoints = uint128(newFees);
        }

        BookKey sharesKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);

        // Maker (Resting) - always settled at execution tick
        if (makerSide == Side.Bid) {
            Accounting.consumeReservedPoints(s, makerId, buyerPaid + makerFee);
            Accounting.addFreeShares(s, makerId, sharesKey, fill.sharesFilled);

            // Release excess fee reservation if maxFeeBps > makerFeeBps
            if (!makerExempt && maxFeeBps > makerFeeBps) {
                uint128 reservedFee = Fees.computeFee(sellerGross, maxFeeBps);
                if (reservedFee > makerFee) {
                    Accounting.releasePoints(s, makerId, reservedFee - makerFee);
                }
            }
        } else {
            Accounting.consumeReservedShares(s, makerId, makerBookKey, fill.sharesFilled);
            Accounting.addFreePoints(s, makerId, sellerGross - makerFee);
        }

        // Taker - logic is identical for limit and market orders
        if (takerSide == Side.Bid) {
            Accounting.consumeReservedPoints(s, takerUserId, buyerPaid + takerFee);

            // Release principal price improvement from limitTick to execution tick
            uint128 reservedPrincipal = Fees.computeBuyerPaid(fill.sharesFilled, limitTick);
            if (reservedPrincipal > buyerPaid) {
                Accounting.releasePoints(s, takerUserId, reservedPrincipal - buyerPaid);
            }

            // Release excess fee reservation (limit orders reserve maxFeeBps; takes reserve takerFeeBps)
            uint16 reservedFeeBps = 0;
            if (OrderId.unwrap(placedOrderId) == 0) {
                reservedFeeBps = takerExempt ? 0 : takerFeeBps;
            } else {
                reservedFeeBps = takerExempt ? 0 : maxFeeBps;
            }
            if (reservedFeeBps > 0) {
                uint128 reservedFee =
                    Fees.computeFee(Fees.computeSellerGross(fill.sharesFilled, limitTick), reservedFeeBps);
                if (reservedFee > takerFee) {
                    Accounting.releasePoints(s, takerUserId, reservedFee - takerFee);
                }
            }

            Accounting.addFreeShares(s, takerUserId, sharesKey, fill.sharesFilled);
        } else {
            BookKey takerBookKey = BookKeyLib.pack(marketId, outcomeId, takerSide);
            Accounting.consumeReservedShares(s, takerUserId, takerBookKey, fill.sharesFilled);
            Accounting.addFreePoints(s, takerUserId, sellerGross - takerFee);
        }

        emit ITrading.Trade(
            marketId,
            UserId.unwrap(makerId),
            UserId.unwrap(takerUserId),
            outcomeId,
            uint8(makerSide),
            OrderId.unwrap(fill.makerId),
            OrderId.unwrap(placedOrderId),
            Tick.unwrap(fill.tick),
            fill.sharesFilled,
            sellerGross,
            makerFee,
            takerFee
        );

        return pointsExchanged;
    }

    // ==================== Internal Checks & Registry ====================

    function _tradingRequireMarketExists(uint64 marketId) internal view {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        if (!Markets.exists(s, marketId)) revert MarketNotFound(marketId);
    }

    function _tradingRequireMarketExistsAndOutcome(uint64 marketId, uint8 outcomeId) internal view {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _tradingRequireMarketExists(marketId);
        Market storage m = s.markets[marketId];
        if (outcomeId >= m.outcomesCount) revert InvalidOutcomeId(outcomeId, m.outcomesCount);
    }

    function _tradingRequireActiveMarket(uint64 marketId, uint8 outcomeId) internal view {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _tradingRequireMarketExistsAndOutcome(marketId, outcomeId);
        Market storage m = s.markets[marketId];
        if (Markets.deriveState(m) != MarketState.Active) revert MarketNotActive(marketId);
    }

    function _getMarketFeeBps(uint64 marketId) internal view returns (uint16 makerFeeBps, uint16 takerFeeBps) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Market storage m = s.markets[marketId];
        makerFeeBps = m.makerFeeBps;
        takerFeeBps = m.takerFeeBps;
    }

    function _isFeeExempt(UserId userId) internal view returns (bool) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return s.feeExempt[userId];
    }

    function _reserveBidWithFee(
        PlatformStorage.Layout storage s,
        UserId userId,
        Tick limitTick,
        uint128 sharesRequested,
        uint16 feeBps
    ) internal {
        uint128 buyerPaid = Fees.computeBuyerPaid(sharesRequested, limitTick);
        uint128 fee = feeBps == 0 ? 0 : Fees.computeMaxFee(sharesRequested, limitTick, feeBps);
        Accounting.reservePoints(s, userId, buyerPaid + fee);
    }

    function _releaseBidReservation(
        PlatformStorage.Layout storage s,
        UserId userId,
        Tick limitTick,
        uint128 sharesRemaining,
        uint16 feeBps
    ) internal {
        uint128 buyerPaid = Fees.computeBuyerPaid(sharesRemaining, limitTick);
        uint128 fee = feeBps == 0 ? 0 : Fees.computeMaxFee(sharesRemaining, limitTick, feeBps);
        Accounting.releasePoints(s, userId, buyerPaid + fee);
    }
}
