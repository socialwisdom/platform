// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Platform} from "../src/Platform.sol";
import {Side} from "../src/types/Enums.sol";
import {DeployPlatform} from "../script/lib/DeployPlatform.sol";

contract TradingViewTest is Test {
    Platform internal platform;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint64 internal marketId;

    uint128 internal constant POINTS = 1e6;
    uint128 internal constant SHARES = 1e6;

    function setUp() public {
        platform = DeployPlatform.deploy(address(this));
        marketId = _createMarket();
        _setupUser(alice);
        _setupUser(bob);
    }

    function _createMarket() internal returns (uint64) {
        string[] memory labels = new string[](3);
        labels[0] = "Yes";
        labels[1] = "No";
        labels[2] = "Maybe";

        return platform.createMarket(address(this), 3, 0, true, 0, 0, 0, bytes32(0), bytes32(0), "Q", labels, "Rules");
    }

    function _setupUser(address user) internal {
        vm.startPrank(user);
        platform.register();
        platform.deposit(1_000_000_000 * POINTS);
        platform.depositShares(marketId, 0, 1_000_000 * SHARES);
        platform.depositShares(marketId, 1, 1_000_000 * SHARES);
        platform.depositShares(marketId, 2, 1_000_000 * SHARES);
        vm.stopPrank();
    }

    function _place(address user, uint8 outcomeId, uint8 side, uint8 tick, uint128 shares)
        internal
        returns (uint32 orderId)
    {
        vm.prank(user);
        (orderId,,) = platform.placeLimit(marketId, outcomeId, side, tick, shares);
    }

    function _assertBook(
        uint8[] memory ticks,
        uint128[] memory totals,
        uint8[] memory expTicks,
        uint128[] memory expTotals
    ) internal pure {
        assertEq(ticks.length, expTicks.length);
        assertEq(totals.length, expTotals.length);
        for (uint256 i = 0; i < expTicks.length; i++) {
            assertEq(ticks[i], expTicks[i]);
            assertEq(totals[i], expTotals[i]);
        }
    }

    function test_TradingView_BookLevelsAndMarketBookLevels() public {
        // Outcome 0
        _place(alice, 0, uint8(Side.Ask), 60, 100 * SHARES);
        _place(bob, 0, uint8(Side.Ask), 60, 50 * SHARES);
        _place(alice, 0, uint8(Side.Ask), 70, 200 * SHARES);

        _place(bob, 0, uint8(Side.Bid), 40, 300 * SHARES);
        _place(alice, 0, uint8(Side.Bid), 30, 150 * SHARES);

        // Outcome 1
        _place(alice, 1, uint8(Side.Ask), 55, 80 * SHARES);
        _place(bob, 1, uint8(Side.Bid), 45, 60 * SHARES);

        // Outcome 2 has no orders

        // Per-book views
        (uint8[] memory o0AskTicks, uint128[] memory o0AskTotals) = platform.getBookLevels(marketId, 0, uint8(Side.Ask));
        (uint8[] memory o0BidTicks, uint128[] memory o0BidTotals) = platform.getBookLevels(marketId, 0, uint8(Side.Bid));

        uint8[] memory expO0AskTicks = new uint8[](2);
        expO0AskTicks[0] = 60;
        expO0AskTicks[1] = 70;
        uint128[] memory expO0AskTotals = new uint128[](2);
        expO0AskTotals[0] = 150 * SHARES;
        expO0AskTotals[1] = 200 * SHARES;

        uint8[] memory expO0BidTicks = new uint8[](2);
        expO0BidTicks[0] = 40;
        expO0BidTicks[1] = 30;
        uint128[] memory expO0BidTotals = new uint128[](2);
        expO0BidTotals[0] = 300 * SHARES;
        expO0BidTotals[1] = 150 * SHARES;

        _assertBook(o0AskTicks, o0AskTotals, expO0AskTicks, expO0AskTotals);
        _assertBook(o0BidTicks, o0BidTotals, expO0BidTicks, expO0BidTotals);

        (uint8[] memory o1AskTicks, uint128[] memory o1AskTotals) = platform.getBookLevels(marketId, 1, uint8(Side.Ask));
        (uint8[] memory o1BidTicks, uint128[] memory o1BidTotals) = platform.getBookLevels(marketId, 1, uint8(Side.Bid));

        uint8[] memory expO1AskTicks = new uint8[](1);
        expO1AskTicks[0] = 55;
        uint128[] memory expO1AskTotals = new uint128[](1);
        expO1AskTotals[0] = 80 * SHARES;

        uint8[] memory expO1BidTicks = new uint8[](1);
        expO1BidTicks[0] = 45;
        uint128[] memory expO1BidTotals = new uint128[](1);
        expO1BidTotals[0] = 60 * SHARES;

        _assertBook(o1AskTicks, o1AskTotals, expO1AskTicks, expO1AskTotals);
        _assertBook(o1BidTicks, o1BidTotals, expO1BidTicks, expO1BidTotals);

        (uint8[] memory o2AskTicks, uint128[] memory o2AskTotals) = platform.getBookLevels(marketId, 2, uint8(Side.Ask));
        (uint8[] memory o2BidTicks, uint128[] memory o2BidTotals) = platform.getBookLevels(marketId, 2, uint8(Side.Bid));

        assertEq(o2AskTicks.length, 0);
        assertEq(o2AskTotals.length, 0);
        assertEq(o2BidTicks.length, 0);
        assertEq(o2BidTotals.length, 0);

        // Market-wide view
        (
            uint8 outcomesCount,
            uint8[][] memory bidTicks,
            uint128[][] memory bidTotals,
            uint8[][] memory askTicks,
            uint128[][] memory askTotals
        ) = platform.getMarketBookLevels(marketId);

        assertEq(outcomesCount, 3);
        assertEq(bidTicks.length, 3);
        assertEq(bidTotals.length, 3);
        assertEq(askTicks.length, 3);
        assertEq(askTotals.length, 3);

        _assertBook(askTicks[0], askTotals[0], expO0AskTicks, expO0AskTotals);
        _assertBook(bidTicks[0], bidTotals[0], expO0BidTicks, expO0BidTotals);

        _assertBook(askTicks[1], askTotals[1], expO1AskTicks, expO1AskTotals);
        _assertBook(bidTicks[1], bidTotals[1], expO1BidTicks, expO1BidTotals);

        assertEq(askTicks[2].length, 0);
        assertEq(askTotals[2].length, 0);
        assertEq(bidTicks[2].length, 0);
        assertEq(bidTotals[2].length, 0);
    }
}
