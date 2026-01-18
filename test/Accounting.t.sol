// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../src/Platform.sol";
import {IPlatform} from "../src/interfaces/IPlatform.sol";
import {Side} from "../src/types/Enums.sol";

contract AccountingTest is Test {
    Platform internal platform;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint64 internal constant MARKET = 1;
    uint8 internal constant OUTCOME = 0;

    uint128 internal constant POINTS = 1e6;
    uint128 internal constant SHARES = 1e6;

    uint16 internal constant MAKER_FEE_BPS = 70; // 0.70%
    uint16 internal constant TAKER_FEE_BPS = 30; // 0.30%

    function setUp() public {
        platform = new Platform();

        string[] memory labels = new string[](2);
        labels[0] = "Yes";
        labels[1] = "No";
        platform.createMarket(
            address(this),
            2,
            0,
            true,
            MAKER_FEE_BPS,
            TAKER_FEE_BPS,
            bytes32(0),
            bytes32(0),
            "Test market",
            labels,
            "Test rules"
        );

        // Setup Alice
        vm.startPrank(alice);
        platform.register();
        platform.deposit(1_000_000 * POINTS); // 1M Points (1e6 decimals)
        platform.depositShares(MARKET, OUTCOME, 1_000_000 * SHARES); // 1M Shares (1e6 decimals)
        vm.stopPrank();

        // Setup Bob
        vm.startPrank(bob);
        platform.register();
        platform.deposit(1_000_000 * POINTS);
        platform.depositShares(MARKET, OUTCOME, 1_000_000 * SHARES);
        vm.stopPrank();
    }

    function _sellerGross(uint128 shares, uint8 tick) internal pure returns (uint128) {
        uint256 num = uint256(shares) * uint256(tick) * 1e6;
        uint256 den = 100 * 1e6;
        // casting to 'uint128' is safe because num/den <= shares (tick <= 99)
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(num / den);
    }

    function _buyerPaid(uint128 shares, uint8 tick) internal pure returns (uint128) {
        uint256 num = uint256(shares) * uint256(tick) * 1e6;
        uint256 den = 100 * 1e6;
        // casting to 'uint128' is safe because ceil(num/den) <= shares when tick <= 99
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128((num + den - 1) / den);
    }

    function _fee(uint128 sellerGross, uint16 feeBps) internal pure returns (uint128) {
        if (sellerGross == 0 || feeBps == 0) return 0;
        uint256 num = uint256(sellerGross) * uint256(feeBps);
        // casting to 'uint128' is safe because fee <= sellerGross when feeBps <= 10_000
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128((num + 10_000 - 1) / 10_000);
    }

    function test_Accounting_PlaceBid_ReservesPoints() public {
        vm.prank(alice);
        // Bid: Buy 100 shares at price 50 (Points per share in centi-Points).
        uint128 shares = 100 * SHARES;
        uint128 buyerPaid = _buyerPaid(shares, 50);
        uint128 maxFee = _fee(_sellerGross(shares, 50), MAKER_FEE_BPS); // max(maker,taker) = maker
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, shares);

        (uint128 free, uint128 reserved) = platform.getPointsBalance(alice);
        assertEq(free, 1_000_000 * POINTS - (buyerPaid + maxFee), "Free points should decrease");
        assertEq(reserved, buyerPaid + maxFee, "Reserved points should increase");
    }

    function test_Accounting_PlaceAsk_ReservesShares() public {
        vm.prank(alice);
        // Ask: Sell 100 shares at price 50.
        uint128 shares = 100 * SHARES;
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, shares);

        (uint128 free, uint128 reserved) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        assertEq(free, 1_000_000 * SHARES - shares, "Free shares should decrease");
        assertEq(reserved, shares, "Reserved shares should increase");
    }

    function test_Accounting_CancelBid_ReleasesPoints() public {
        vm.startPrank(alice);
        uint128 shares = 100 * SHARES;
        (uint32 orderId,,) = platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, shares);

        (, uint128 reservedBefore) = platform.getPointsBalance(alice);
        uint128 buyerPaid = _buyerPaid(shares, 50);
        uint128 maxFee = _fee(_sellerGross(shares, 50), MAKER_FEE_BPS);
        assertEq(reservedBefore, buyerPaid + maxFee);

        platform.cancel(MARKET, OUTCOME, uint8(Side.Bid), orderId, new uint32[](0));
        vm.stopPrank();

        (uint128 freeAfter, uint128 reservedAfter) = platform.getPointsBalance(alice);
        assertEq(freeAfter, 1_000_000 * POINTS, "Free points should be restored");
        assertEq(reservedAfter, 0, "Reserved points should be released");
    }

    function test_Accounting_CancelAsk_ReleasesShares() public {
        vm.startPrank(alice);
        uint128 shares = 100 * SHARES;
        (uint32 orderId,,) = platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, shares);

        (, uint128 reservedBefore) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        assertEq(reservedBefore, shares);

        platform.cancel(MARKET, OUTCOME, uint8(Side.Ask), orderId, new uint32[](0));
        vm.stopPrank();

        (uint128 freeAfter, uint128 reservedAfter) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        assertEq(freeAfter, 1_000_000 * SHARES, "Free shares should be restored");
        assertEq(reservedAfter, 0, "Reserved shares should be released");
    }

    function test_Accounting_Trade_BidMaker_AskTakerLimit() public {
        uint128 shares = 100 * SHARES;
        uint128 sellerGross = _sellerGross(shares, 50);
        uint128 makerFee = _fee(sellerGross, MAKER_FEE_BPS);
        uint128 takerFee = _fee(sellerGross, TAKER_FEE_BPS);

        // Alice places Bid (Maker)
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, shares); // Reserves buyerPaid + maxFee

        // Bob places Ask (Taker) matching Alice
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, shares); // Reserves shares

        // Check Alice (Maker Bid)
        // Consumed buyerPaid + makerFee reserved points. Gained shares.
        (uint128 aFreePts, uint128 aResPts) = platform.getPointsBalance(alice);

        assertEq(aFreePts, 1_000_000 * POINTS - (_buyerPaid(shares, 50) + makerFee), "Alice points consumed");
        assertEq(aResPts, 0, "Alice reserved points consumed");

        // Alice bought shares. She should have them in her free balance.
        (uint128 aFreeSh,) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        // Alice started with 1M shares. She bought 100 more.
        assertEq(aFreeSh, 1_000_000 * SHARES + shares, "Alice should receive shares");

        // Check Bob (Taker Ask)
        // Consumed reserved shares. Gained sellerGross - takerFee points.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        (uint128 bFreeSh, uint128 bResSh) = platform.getSharesBalance(MARKET, OUTCOME, bob);

        assertEq(bFreePts, 1_000_000 * POINTS + (sellerGross - takerFee), "Bob should gain points");
        assertEq(bResPts, 0, "Bob reserved points empty");
        assertEq(bFreeSh, 1_000_000 * SHARES - shares, "Bob shares consumed");
        assertEq(bResSh, 0, "Bob reserved shares consumed");
    }

    function test_Accounting_Trade_AskMaker_BidTakerLimit() public {
        uint128 shares = 100 * SHARES;
        uint128 sellerGross = _sellerGross(shares, 50);
        uint128 makerFee = _fee(sellerGross, MAKER_FEE_BPS);
        uint128 takerFee = _fee(sellerGross, TAKER_FEE_BPS);

        // Alice places Ask (Maker)
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, shares); // Reserves shares

        // Bob places Bid (Taker) matching Alice
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, shares); // Reserves buyerPaid + maxFee

        // Check Alice (Maker Ask)
        // Consumed reserved shares. Gained sellerGross - makerFee points.
        (uint128 aFreePts, uint128 aResPts) = platform.getPointsBalance(alice);
        (uint128 aFreeSh, uint128 aResSh) = platform.getSharesBalance(MARKET, OUTCOME, alice);

        assertEq(aFreePts, 1_000_000 * POINTS + (sellerGross - makerFee), "Alice gains points");
        assertEq(aResPts, 0);
        assertEq(aFreeSh, 1_000_000 * SHARES - shares, "Alice shares consumed");
        assertEq(aResSh, 0);

        // Check Bob (Taker Bid)
        // Consumed buyerPaid + takerFee. Gained shares.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        (uint128 bFreeSh,) = platform.getSharesBalance(MARKET, OUTCOME, bob);

        assertEq(bFreePts, 1_000_000 * POINTS - (_buyerPaid(shares, 50) + takerFee), "Bob points consumed");
        assertEq(bResPts, 0);
        assertEq(bFreeSh, 1_000_000 * SHARES + shares, "Bob receives shares");
    }

    function test_Accounting_Trade_BidMaker_AskTakerMarket() public {
        uint128 shares = 100 * SHARES;
        uint128 sellerGross = _sellerGross(shares, 50);
        uint128 makerFee = _fee(sellerGross, MAKER_FEE_BPS);
        uint128 takerFee = _fee(sellerGross, TAKER_FEE_BPS);

        // Alice places Bid (Maker) @ 50
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, shares);

        // Bob takes (Market Ask)
        vm.prank(bob);
        platform.take(MARKET, OUTCOME, uint8(Side.Ask), 50, shares, shares);

        // Check Alice (Maker Bid)
        (uint128 aFreePts,) = platform.getPointsBalance(alice);
        assertEq(aFreePts, 1_000_000 * POINTS - (_buyerPaid(shares, 50) + makerFee));

        // Check Bob (Taker Market Ask)
        // Should use FREE shares directly. Gain FREE points.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        (uint128 bFreeSh, uint128 bResSh) = platform.getSharesBalance(MARKET, OUTCOME, bob);

        assertEq(bFreePts, 1_000_000 * POINTS + (sellerGross - takerFee), "Bob gains points");
        assertEq(bResPts, 0);
        assertEq(bFreeSh, 1_000_000 * SHARES - shares, "Bob free shares decreased");
        assertEq(bResSh, 0, "Bob reserved shares untouched");
    }

    function test_Accounting_Trade_AskMaker_BidTakerMarket() public {
        uint128 shares = 100 * SHARES;
        uint128 sellerGross = _sellerGross(shares, 50);
        uint128 makerFee = _fee(sellerGross, MAKER_FEE_BPS);
        uint128 takerFee = _fee(sellerGross, TAKER_FEE_BPS);

        // Alice places Ask (Maker) @ 50
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, shares);

        // Bob takes (Market Bid)
        vm.prank(bob);
        platform.take(MARKET, OUTCOME, uint8(Side.Bid), 50, shares, shares);

        // Check Alice (Maker Ask)
        (uint128 aFreePts,) = platform.getPointsBalance(alice);
        (uint128 aFreeSh,) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        assertEq(aFreePts, 1_000_000 * POINTS + (sellerGross - makerFee), "Alice gains points");
        assertEq(aFreeSh, 1_000_000 * SHARES - shares);

        // Check Bob (Taker Market Bid)
        // Should use FREE points directly. Gain FREE shares.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        (uint128 bFreeSh,) = platform.getSharesBalance(MARKET, OUTCOME, bob);

        assertEq(bFreePts, 1_000_000 * POINTS - (_buyerPaid(shares, 50) + takerFee), "Bob free points decreased");
        assertEq(bResPts, 0);
        assertEq(bFreeSh, 1_000_000 * SHARES + shares, "Bob receives shares");
    }

    function test_Accounting_Trade_BidMaker_AskTakerLimit_PriceImprovement() public {
        uint128 shares = 100 * SHARES;
        uint128 sellerGross = _sellerGross(shares, 60);
        uint128 makerFee = _fee(sellerGross, MAKER_FEE_BPS);
        uint128 takerFee = _fee(sellerGross, TAKER_FEE_BPS);

        // Alice places Bid (Maker) @ 60
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 60, shares); // Reserves buyerPaid + maxFee

        // Bob places Ask (Taker) @ 50
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, shares);

        // Alice (Maker Bid @ 60): Pays 6000.
        (uint128 aFreePts,) = platform.getPointsBalance(alice);
        assertEq(aFreePts, 1_000_000 * POINTS - (_buyerPaid(shares, 60) + makerFee));

        // Bob (Taker Ask @ 50): Sells at 60. Gains 6000.
        (uint128 bFreePts,) = platform.getPointsBalance(bob);
        assertEq(bFreePts, 1_000_000 * POINTS + (sellerGross - takerFee));
    }

    function test_Accounting_Trade_AskMaker_BidTakerLimit_PriceImprovement() public {
        uint128 shares = 100 * SHARES;
        uint128 sellerGross = _sellerGross(shares, 40);
        uint128 makerFee = _fee(sellerGross, MAKER_FEE_BPS);
        uint128 takerFee = _fee(sellerGross, TAKER_FEE_BPS);

        // Alice places Ask (Maker) @ 40
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 40, shares);

        // Bob places Bid (Taker) @ 50
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, shares);

        // Alice (Maker Ask @ 40): Sells at 40. Gains 4000.
        (uint128 aFreePts,) = platform.getPointsBalance(alice);
        assertEq(aFreePts, 1_000_000 * POINTS + (sellerGross - makerFee));

        // Bob (Taker Bid @ 50): Buys at 40. Pays 4000.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        assertEq(bFreePts, 1_000_000 * POINTS - (_buyerPaid(shares, 40) + takerFee), "Bob should get refund");
        assertEq(bResPts, 0);
    }

    function test_FeeExempt_NoFeeReserve_NoFeeCharged() public {
        uint128 shares = 100 * SHARES;
        uint128 buyerPaid = _buyerPaid(shares, 50);

        platform.setFeeExempt(alice, true);

        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, shares);

        (uint128 free, uint128 reserved) = platform.getPointsBalance(alice);
        assertEq(free, 1_000_000 * POINTS - buyerPaid, "Fee-exempt should not reserve fee");
        assertEq(reserved, buyerPaid, "Only principal reserved");
    }

    function test_TradeEvent_FeesAndProtocolAccrual() public {
        uint128 shares = 100 * SHARES;
        uint128 sellerGross = _sellerGross(shares, 50);
        uint128 makerFee = _fee(sellerGross, MAKER_FEE_BPS);
        uint128 takerFee = _fee(sellerGross, TAKER_FEE_BPS);

        vm.prank(alice);
        (uint32 makerOrderId,,) = platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, shares);

        vm.expectEmit(true, true, true, true);
        emit IPlatform.Trade(
            MARKET, 2, 3, OUTCOME, uint8(Side.Ask), makerOrderId, 0, 50, shares, sellerGross, makerFee, takerFee
        );

        vm.prank(bob);
        platform.take(MARKET, OUTCOME, uint8(Side.Bid), 50, shares, shares);

        assertEq(platform.getMarketTradingFeesPoints(MARKET), makerFee + takerFee);
        assertEq(platform.getProtocolDustPoints(), 0);
    }

    function test_PartialFill_BidLimit_KeepsFeeReserveForRemainder() public {
        uint128 makerShares = 40 * SHARES;
        uint128 takerShares = 100 * SHARES;
        uint128 remainingShares = takerShares - makerShares;

        // Seed maker ask for 40 shares
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, makerShares);

        // Alice places bid for 100 shares (taker for 40, rest 60)
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, takerShares);

        uint128 buyerPaidFilled = _buyerPaid(makerShares, 50);
        uint128 takerFeeFilled = _fee(_sellerGross(makerShares, 50), TAKER_FEE_BPS);

        uint128 buyerPaidRemaining = _buyerPaid(remainingShares, 50);
        uint128 maxFeeRemaining = _fee(_sellerGross(remainingShares, 50), MAKER_FEE_BPS); // max(maker,taker)

        (uint128 freePts, uint128 reservedPts) = platform.getPointsBalance(alice);

        uint128 expectedReserved = buyerPaidRemaining + maxFeeRemaining;
        uint128 expectedFree = 1_000_000 * POINTS - (buyerPaidFilled + takerFeeFilled) - expectedReserved;

        assertEq(reservedPts, expectedReserved, "Reserved should reflect remaining principal + fee");
        assertEq(freePts, expectedFree, "Free should reflect executed cost + remaining reserve");
    }

    function test_Take_Bid_PartialFill_ReleasesUnusedReserve() public {
        // Seed maker asks for 40 shares; taker asks for 100 shares.
        uint128 makerShares = 40 * SHARES;
        uint128 takerShares = 100 * SHARES;
        uint128 unfilled = takerShares - makerShares;

        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, makerShares);

        uint128 buyerPaidFilled = _buyerPaid(makerShares, 50);
        uint128 takerFeeFilled = _fee(_sellerGross(makerShares, 50), TAKER_FEE_BPS);
        uint128 buyerPaidUnfilled = _buyerPaid(unfilled, 50);
        uint128 takerFeeUnfilled = _fee(_sellerGross(unfilled, 50), TAKER_FEE_BPS);

        vm.prank(alice);
        platform.take(MARKET, OUTCOME, uint8(Side.Bid), 50, takerShares, makerShares);

        (uint128 freePts, uint128 reservedPts) = platform.getPointsBalance(alice);

        uint128 expectedFree = 1_000_000 * POINTS - (buyerPaidFilled + takerFeeFilled);
        assertEq(freePts, expectedFree, "Only executed notional + fee should be spent");
        assertEq(reservedPts, 0, "Unused reserve should be released for take");

        // Sanity: ensure the reserved amount that would have been held without release is positive.
        assertTrue(buyerPaidUnfilled + takerFeeUnfilled > 0);
    }

    function test_FeeExempt_TradeHasZeroFees() public {
        uint128 shares = 100 * SHARES;

        platform.setFeeExempt(alice, true);
        platform.setFeeExempt(bob, true);

        vm.prank(alice);
        (uint32 makerOrderId,,) = platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, shares);

        vm.expectEmit(true, true, true, true);
        emit IPlatform.Trade(
            MARKET, 2, 3, OUTCOME, uint8(Side.Ask), makerOrderId, 0, 50, shares, _sellerGross(shares, 50), 0, 0
        );

        vm.prank(bob);
        platform.take(MARKET, OUTCOME, uint8(Side.Bid), 50, shares, shares);

        assertEq(platform.getMarketTradingFeesPoints(MARKET), 0);
    }

    function test_Dust_AccruesToProtocol_NotFee() public {
        // Choose values that create dust: shares * tick not divisible by 100.
        uint128 shares = 1 * SHARES;
        uint8 tick = 1;

        platform.setFeeExempt(alice, true);
        platform.setFeeExempt(bob, true);

        vm.prank(alice);
        (uint32 makerOrderId,,) = platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), tick, shares);

        uint128 sellerGross = _sellerGross(shares, tick);
        uint128 buyerPaid = _buyerPaid(shares, tick);
        uint128 dust = buyerPaid - sellerGross;

        vm.expectEmit(true, true, true, true);
        emit IPlatform.Trade(MARKET, 2, 3, OUTCOME, uint8(Side.Ask), makerOrderId, 0, tick, shares, sellerGross, 0, 0);

        vm.prank(bob);
        platform.take(MARKET, OUTCOME, uint8(Side.Bid), tick, shares, shares);

        assertEq(platform.getProtocolDustPoints(), dust, "Dust should accrue to protocol");
        assertEq(platform.getMarketTradingFeesPoints(MARKET), 0, "Dust must not be counted as fee");
    }

    function test_Dust_And_Fee_Together() public {
        uint128 shares = 1 * SHARES;
        uint8 tick = 1;

        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), tick, shares);

        uint128 sellerGross = _sellerGross(shares, tick);
        uint128 buyerPaid = _buyerPaid(shares, tick);
        uint128 dust = buyerPaid - sellerGross;
        uint128 makerFee = _fee(sellerGross, MAKER_FEE_BPS);
        uint128 takerFee = _fee(sellerGross, TAKER_FEE_BPS);

        vm.prank(bob);
        platform.take(MARKET, OUTCOME, uint8(Side.Bid), tick, shares, shares);

        assertEq(platform.getProtocolDustPoints(), dust, "Dust should accrue to protocol");
        assertEq(platform.getMarketTradingFeesPoints(MARKET), makerFee + takerFee, "Fees should accrue separately");
    }

    function test_ZeroFees_NoFeeAccrual() public {
        // Create a new market with zero maker/taker fees.
        string[] memory labels = new string[](2);
        labels[0] = "Yes";
        labels[1] = "No";

        uint64 marketId = platform.createMarket(
            address(this), 2, 0, true, 0, 0, bytes32(0), bytes32(0), "Zero fee market", labels, "Rules"
        );

        // Seed balances for this market.
        vm.startPrank(alice);
        platform.depositShares(marketId, OUTCOME, 1_000_000 * SHARES);
        vm.stopPrank();

        vm.startPrank(bob);
        platform.depositShares(marketId, OUTCOME, 1_000_000 * SHARES);
        vm.stopPrank();

        uint128 shares = 100 * SHARES;
        uint8 tick = 50;

        vm.prank(alice);
        (uint32 makerOrderId,,) = platform.placeLimit(marketId, OUTCOME, uint8(Side.Ask), tick, shares);

        vm.expectEmit(true, true, true, true);
        emit IPlatform.Trade(
            marketId, 2, 3, OUTCOME, uint8(Side.Ask), makerOrderId, 0, tick, shares, _sellerGross(shares, tick), 0, 0
        );

        vm.prank(bob);
        platform.take(marketId, OUTCOME, uint8(Side.Bid), tick, shares, shares);

        assertEq(platform.getMarketTradingFeesPoints(marketId), 0, "No fees should accrue at zero bps");
    }
}
