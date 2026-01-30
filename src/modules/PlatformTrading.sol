// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITrading} from "../interfaces/ITrading.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {Market, Order} from "../types/Structs.sol";
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
    struct MatchParams {
        uint64 marketId;
        uint8 outcomeId;
        Side takerSide;
        Tick limitTick;
        OrderId placedOrderId;
        UserId takerUserId;
        BookKey makerBookKey;
        Side makerSide;
    }

    struct MatchFees {
        uint128 sellerGross;
        uint128 buyerPaid;
        uint128 dust;
        uint128 makerFee;
        uint128 takerFee;
        uint16 makerFeeBps;
        uint16 takerFeeBps;
        uint16 maxFeeBps;
        bool makerExempt;
        bool takerExempt;
    }
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

            MatchParams memory params = MatchParams({
                marketId: marketId,
                outcomeId: outcomeId,
                takerSide: takerSide,
                limitTick: limitTick,
                placedOrderId: takerOrderId,
                takerUserId: takerUserId,
                makerBookKey: makerBookKey,
                makerSide: makerSide
            });
            uint128 pointsExchanged = _processMatch(params, fill);

            totalFilled += fill.sharesFilled;
            totalPointsTraded += pointsExchanged;
            remaining -= fill.sharesFilled;
        }
        return (totalFilled, totalPointsTraded);
    }

    function _processMatch(MatchParams memory params, Matching.FillInfo memory fill)
        private
        returns (uint128 pointsExchanged)
    {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Order storage makerOrder = s.orders[Keys.orderKey(params.makerBookKey, fill.makerId)];
        UserId makerId = makerOrder.ownerId;

        MatchFees memory fees = _computeMatchFees(params.marketId, makerId, params.takerUserId, fill);
        pointsExchanged = fees.sellerGross;

        _accrueDustAndFees(s, params.marketId, fees.dust, fees.makerFee, fees.takerFee);

        BookKey sharesKey = BookKeyLib.pack(params.marketId, params.outcomeId, Side.Ask);

        _settleMaker(s, makerId, params.makerSide, params.makerBookKey, sharesKey, fill.sharesFilled, fees);
        _settleTaker(s, params, sharesKey, fill.sharesFilled, fees);

        emit ITrading.Trade(
            params.marketId,
            UserId.unwrap(makerId),
            UserId.unwrap(params.takerUserId),
            params.outcomeId,
            uint8(params.makerSide),
            OrderId.unwrap(fill.makerId),
            OrderId.unwrap(params.placedOrderId),
            Tick.unwrap(fill.tick),
            fill.sharesFilled,
            fees.sellerGross,
            fees.makerFee,
            fees.takerFee
        );

        return pointsExchanged;
    }

    function _accrueDustAndFees(
        PlatformStorage.Layout storage s,
        uint64 marketId,
        uint128 dust,
        uint128 makerFee,
        uint128 takerFee
    ) private {
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
    }

    function _computeMatchFees(uint64 marketId, UserId makerId, UserId takerUserId, Matching.FillInfo memory fill)
        private
        view
        returns (MatchFees memory fees)
    {
        (uint16 makerFeeBps, uint16 takerFeeBps) = _getMarketFeeBps(marketId);
        uint16 maxFeeBps = makerFeeBps >= takerFeeBps ? makerFeeBps : takerFeeBps;

        bool makerExempt = _isFeeExempt(makerId);
        bool takerExempt = _isFeeExempt(takerUserId);

        (uint128 sellerGross, uint128 buyerPaid, uint128 dust) = Fees.computeNotional(fill.sharesFilled, fill.tick);

        uint128 makerFee = makerExempt ? 0 : Fees.computeFee(sellerGross, makerFeeBps);
        uint128 takerFee = takerExempt ? 0 : Fees.computeFee(sellerGross, takerFeeBps);

        fees = MatchFees({
            sellerGross: sellerGross,
            buyerPaid: buyerPaid,
            dust: dust,
            makerFee: makerFee,
            takerFee: takerFee,
            makerFeeBps: makerFeeBps,
            takerFeeBps: takerFeeBps,
            maxFeeBps: maxFeeBps,
            makerExempt: makerExempt,
            takerExempt: takerExempt
        });
    }

    function _settleMaker(
        PlatformStorage.Layout storage s,
        UserId makerId,
        Side makerSide,
        BookKey makerBookKey,
        BookKey sharesKey,
        uint128 sharesFilled,
        MatchFees memory fees
    ) private {
        // Maker (Resting) - always settled at execution tick
        if (makerSide == Side.Bid) {
            Accounting.consumeReservedPoints(s, makerId, fees.buyerPaid + fees.makerFee);
            Accounting.addFreeShares(s, makerId, sharesKey, sharesFilled);

            // Release excess fee reservation if maxFeeBps > makerFeeBps
            if (!fees.makerExempt && fees.maxFeeBps > fees.makerFeeBps) {
                uint128 reservedFee = Fees.computeFee(fees.sellerGross, fees.maxFeeBps);
                if (reservedFee > fees.makerFee) {
                    Accounting.releasePoints(s, makerId, reservedFee - fees.makerFee);
                }
            }
        } else {
            Accounting.consumeReservedShares(s, makerId, makerBookKey, sharesFilled);
            Accounting.addFreePoints(s, makerId, fees.sellerGross - fees.makerFee);
        }
    }

    function _settleTaker(
        PlatformStorage.Layout storage s,
        MatchParams memory params,
        BookKey sharesKey,
        uint128 sharesFilled,
        MatchFees memory fees
    ) private {
        // Taker - logic is identical for limit and market orders
        if (params.takerSide == Side.Bid) {
            Accounting.consumeReservedPoints(s, params.takerUserId, fees.buyerPaid + fees.takerFee);

            // Release principal price improvement from limitTick to execution tick
            uint128 reservedPrincipal = Fees.computeBuyerPaid(sharesFilled, params.limitTick);
            if (reservedPrincipal > fees.buyerPaid) {
                Accounting.releasePoints(s, params.takerUserId, reservedPrincipal - fees.buyerPaid);
            }

            // Release excess fee reservation (limit orders reserve maxFeeBps; takes reserve takerFeeBps)
            uint16 reservedFeeBps = 0;
            if (OrderId.unwrap(params.placedOrderId) == 0) {
                reservedFeeBps = fees.takerExempt ? 0 : fees.takerFeeBps;
            } else {
                reservedFeeBps = fees.takerExempt ? 0 : fees.maxFeeBps;
            }
            if (reservedFeeBps > 0) {
                uint128 reservedFee =
                    Fees.computeFee(Fees.computeSellerGross(sharesFilled, params.limitTick), reservedFeeBps);
                if (reservedFee > fees.takerFee) {
                    Accounting.releasePoints(s, params.takerUserId, reservedFee - fees.takerFee);
                }
            }

            Accounting.addFreeShares(s, params.takerUserId, sharesKey, sharesFilled);
        } else {
            BookKey takerBookKey = BookKeyLib.pack(params.marketId, params.outcomeId, params.takerSide);
            Accounting.consumeReservedShares(s, params.takerUserId, takerBookKey, sharesFilled);
            Accounting.addFreePoints(s, params.takerUserId, fees.sellerGross - fees.takerFee);
        }
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
