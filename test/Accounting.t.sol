// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../src/Platform.sol";
import {Side} from "../src/types/Enums.sol";

contract AccountingTest is Test {
    Platform internal platform;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint64 internal constant MARKET = 1;
    uint8 internal constant OUTCOME = 0;

    function setUp() public {
        platform = new Platform();

        string[] memory labels = new string[](2);
        labels[0] = "Yes";
        labels[1] = "No";
        platform.createMarket(
            address(this), 2, 0, true, bytes32(0), bytes32(0), bytes32(0), "Test market", labels, "Test rules"
        );

        // Setup Alice
        vm.startPrank(alice);
        platform.register();
        platform.deposit(1_000_000); // 1M Points
        platform.depositShares(MARKET, OUTCOME, 1_000_000); // 1M Shares
        vm.stopPrank();

        // Setup Bob
        vm.startPrank(bob);
        platform.register();
        platform.deposit(1_000_000);
        platform.depositShares(MARKET, OUTCOME, 1_000_000);
        vm.stopPrank();
    }

    function test_Accounting_PlaceBid_ReservesPoints() public {
        vm.prank(alice);
        // Bid: Buy 100 shares at price 50. Cost = 100 * 50 = 5000.
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, 100);

        (uint128 free, uint128 reserved) = platform.getPointsBalance(alice);
        assertEq(free, 1_000_000 - 5000, "Free points should decrease");
        assertEq(reserved, 5000, "Reserved points should increase");
    }

    function test_Accounting_PlaceAsk_ReservesShares() public {
        vm.prank(alice);
        // Ask: Sell 100 shares at price 50.
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, 100);

        (uint128 free, uint128 reserved) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        assertEq(free, 1_000_000 - 100, "Free shares should decrease");
        assertEq(reserved, 100, "Reserved shares should increase");
    }

    function test_Accounting_CancelBid_ReleasesPoints() public {
        vm.startPrank(alice);
        (uint32 orderId,,) = platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, 100);

        (, uint128 reservedBefore) = platform.getPointsBalance(alice);
        assertEq(reservedBefore, 5000);

        platform.cancel(MARKET, OUTCOME, uint8(Side.Bid), orderId, new uint32[](0));
        vm.stopPrank();

        (uint128 freeAfter, uint128 reservedAfter) = platform.getPointsBalance(alice);
        assertEq(freeAfter, 1_000_000, "Free points should be restored");
        assertEq(reservedAfter, 0, "Reserved points should be released");
    }

    function test_Accounting_CancelAsk_ReleasesShares() public {
        vm.startPrank(alice);
        (uint32 orderId,,) = platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, 100);

        (, uint128 reservedBefore) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        assertEq(reservedBefore, 100);

        platform.cancel(MARKET, OUTCOME, uint8(Side.Ask), orderId, new uint32[](0));
        vm.stopPrank();

        (uint128 freeAfter, uint128 reservedAfter) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        assertEq(freeAfter, 1_000_000, "Free shares should be restored");
        assertEq(reservedAfter, 0, "Reserved shares should be released");
    }

    function test_Accounting_Trade_BidMaker_AskTakerLimit() public {
        // Alice places Bid (Maker)
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, 100); // Reserves 5000 points

        // Bob places Ask (Taker) matching Alice
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, 100); // Reserves 100 shares

        // Check Alice (Maker Bid)
        // Consumed 5000 reserved points. Gained 100 shares.
        (uint128 aFreePts, uint128 aResPts) = platform.getPointsBalance(alice);

        assertEq(aFreePts, 1_000_000 - 5000, "Alice points consumed");
        assertEq(aResPts, 0, "Alice reserved points consumed");

        // Alice bought shares. She should have them in her free balance.
        (uint128 aFreeSh,) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        // Alice started with 1M shares. She bought 100 more.
        assertEq(aFreeSh, 1_000_000 + 100, "Alice should receive shares");

        // Check Bob (Taker Ask)
        // Consumed 100 reserved shares. Gained 5000 points.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        (uint128 bFreeSh, uint128 bResSh) = platform.getSharesBalance(MARKET, OUTCOME, bob);

        assertEq(bFreePts, 1_000_000 + 5000, "Bob should gain points");
        assertEq(bResPts, 0, "Bob reserved points empty");
        assertEq(bFreeSh, 1_000_000 - 100, "Bob shares consumed");
        assertEq(bResSh, 0, "Bob reserved shares consumed");
    }

    function test_Accounting_Trade_AskMaker_BidTakerLimit() public {
        // Alice places Ask (Maker)
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, 100); // Reserves 100 shares (Ask side)

        // Bob places Bid (Taker) matching Alice
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, 100); // Reserves 5000 points

        // Check Alice (Maker Ask)
        // Consumed 100 reserved shares. Gained 5000 points.
        (uint128 aFreePts, uint128 aResPts) = platform.getPointsBalance(alice);
        (uint128 aFreeSh, uint128 aResSh) = platform.getSharesBalance(MARKET, OUTCOME, alice);

        assertEq(aFreePts, 1_000_000 + 5000, "Alice gains points");
        assertEq(aResPts, 0);
        assertEq(aFreeSh, 1_000_000 - 100, "Alice shares consumed");
        assertEq(aResSh, 0);

        // Check Bob (Taker Bid)
        // Consumed 5000 reserved points. Gained 100 shares.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        (uint128 bFreeSh,) = platform.getSharesBalance(MARKET, OUTCOME, bob);

        assertEq(bFreePts, 1_000_000 - 5000, "Bob points consumed");
        assertEq(bResPts, 0);
        assertEq(bFreeSh, 1_000_000 + 100, "Bob receives shares");
    }

    function test_Accounting_Trade_BidMaker_AskTakerMarket() public {
        // Alice places Bid (Maker) @ 50
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, 100);

        // Bob takes (Market Ask)
        vm.prank(bob);
        platform.take(MARKET, OUTCOME, uint8(Side.Ask), 50, 100, 100);

        // Check Alice (Maker Bid)
        (uint128 aFreePts,) = platform.getPointsBalance(alice);
        assertEq(aFreePts, 1_000_000 - 5000);

        // Check Bob (Taker Market Ask)
        // Should use FREE shares directly. Gain FREE points.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        (uint128 bFreeSh, uint128 bResSh) = platform.getSharesBalance(MARKET, OUTCOME, bob);

        assertEq(bFreePts, 1_000_000 + 5000, "Bob gains points");
        assertEq(bResPts, 0);
        assertEq(bFreeSh, 1_000_000 - 100, "Bob free shares decreased");
        assertEq(bResSh, 0, "Bob reserved shares untouched");
    }

    function test_Accounting_Trade_AskMaker_BidTakerMarket() public {
        // Alice places Ask (Maker) @ 50
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, 100);

        // Bob takes (Market Bid)
        vm.prank(bob);
        platform.take(MARKET, OUTCOME, uint8(Side.Bid), 50, 100, 100);

        // Check Alice (Maker Ask)
        (uint128 aFreeSh,) = platform.getSharesBalance(MARKET, OUTCOME, alice);
        assertEq(aFreeSh, 1_000_000 - 100);

        // Check Bob (Taker Market Bid)
        // Should use FREE points directly. Gain FREE shares.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        (uint128 bFreeSh,) = platform.getSharesBalance(MARKET, OUTCOME, bob);

        assertEq(bFreePts, 1_000_000 - 5000, "Bob free points decreased");
        assertEq(bResPts, 0);
        assertEq(bFreeSh, 1_000_000 + 100, "Bob receives shares");
    }

    function test_Accounting_Trade_BidMaker_AskTakerLimit_PriceImprovement() public {
        // Alice places Bid (Maker) @ 60
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 60, 100); // Reserves 6000

        // Bob places Ask (Taker) @ 50
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 50, 100);

        // Alice (Maker Bid @ 60): Pays 6000.
        (uint128 aFreePts,) = platform.getPointsBalance(alice);
        assertEq(aFreePts, 1_000_000 - 6000);

        // Bob (Taker Ask @ 50): Sells at 60. Gains 6000.
        (uint128 bFreePts,) = platform.getPointsBalance(bob);
        assertEq(bFreePts, 1_000_000 + 6000);
    }

    function test_Accounting_Trade_AskMaker_BidTakerLimit_PriceImprovement() public {
        // Alice places Ask (Maker) @ 40
        vm.prank(alice);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Ask), 40, 100);

        // Bob places Bid (Taker) @ 50
        vm.prank(bob);
        platform.placeLimit(MARKET, OUTCOME, uint8(Side.Bid), 50, 100);

        // Alice (Maker Ask @ 40): Sells at 40. Gains 4000.
        (uint128 aFreePts,) = platform.getPointsBalance(alice);
        assertEq(aFreePts, 1_000_000 + 4000);

        // Bob (Taker Bid @ 50): Buys at 40. Pays 4000.
        (uint128 bFreePts, uint128 bResPts) = platform.getPointsBalance(bob);
        assertEq(bFreePts, 1_000_000 - 4000, "Bob should get refund");
        assertEq(bResPts, 0);
    }
}
