// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Platform} from "../src/Platform.sol";
import {ITradingView} from "../src/interfaces/ITradingView.sol";
import {Side} from "../src/types/Enums.sol";
import {DeployPlatform} from "../script/lib/DeployPlatform.sol";

contract OrderBookGasTest is Test {
    Platform internal platform;
    ITradingView internal tradingView;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA901);
    address internal dave = address(0xDA8E);

    uint64 internal constant MARKET = 1;
    uint8 internal constant OUTCOME = 0;

    uint128 internal constant POINTS = 1e6;
    uint128 internal constant SHARES = 1e6;

    function setUp() public {
        platform = DeployPlatform.deploy(address(this));
        tradingView = ITradingView(address(platform));
        _initMarket();
        _setupUsers();
    }

    function _initMarket() internal {
        string[] memory labels = new string[](2);
        labels[0] = "Yes";
        labels[1] = "No";
        platform.createMarket(
            address(this), 2, 0, true, 0, 0, 0, bytes32(0), bytes32(0), "Test market", labels, "Test rules"
        );
    }

    function _setupUsers() internal {
        address[4] memory users = [alice, bob, carol, dave];
        for (uint256 i = 0; i < 4; i++) {
            address u = users[i];
            vm.startPrank(u);
            platform.register();
            platform.deposit(1_000_000_000_000_000 * POINTS);
            platform.depositShares(MARKET, OUTCOME, 1_000_000_000 * SHARES);
            vm.stopPrank();
        }
    }

    // -------------------------
    // Helpers
    // -------------------------

    function _place(address user, uint8 side, uint8 tick, uint128 shares)
        internal
        returns (uint32 orderId, uint128 filled, uint256 pts)
    {
        vm.prank(user);
        return platform.placeLimit(MARKET, OUTCOME, side, tick, shares);
    }

    function _take(address user, uint8 side, uint8 limitTick, uint128 sharesRequested, uint128 minFill)
        internal
        returns (uint128 filled, uint256 pts)
    {
        vm.prank(user);
        return platform.take(MARKET, OUTCOME, side, limitTick, sharesRequested, minFill);
    }

    function _seedAsksAtTick(uint8 tick, uint256 nOrders, uint128 sharesEach) internal returns (uint32[] memory ids) {
        ids = new uint32[](nOrders);
        for (uint256 i = 0; i < nOrders; i++) {
            address maker = (i % 2 == 0) ? alice : bob;
            (uint32 id, uint128 filled,) = _place(maker, uint8(Side.Ask), tick, sharesEach);
            assertEq(filled, 0);
            ids[i] = id;
        }
    }

    function _seedAsksManyLevels(uint8 fromTick, uint8 toTick, uint256 ordersPerLevel, uint128 sharesEach)
        internal
        returns (uint256 totalShares)
    {
        for (uint8 t = fromTick; t <= toTick; t++) {
            _seedAsksAtTick(t, ordersPerLevel, sharesEach);
            totalShares += uint256(ordersPerLevel) * uint256(sharesEach);
        }
    }

    /// @dev Counts how many seeded maker orders were touched by matching.
    /// fullFill: remaining == 0
    /// partialFill: 0 < remaining < requested
    function _countMatchesFromSeeded(uint32[] memory makerIds, uint8 makerSide)
        internal
        view
        returns (uint256 touched, uint256 fullFill, uint256 partialFill)
    {
        uint256 len = makerIds.length;
        for (uint256 i = 0; i < len; i++) {
            (uint128 rem, uint128 req) =
                tradingView.getOrderRemainingAndRequested(MARKET, OUTCOME, makerSide, makerIds[i]);

            // if req==0 it was never created (shouldn't happen in these tests), ignore
            if (req == 0) continue;

            if (rem == 0) {
                fullFill++;
            } else if (rem < req) {
                partialFill++;
            }
        }
        touched = fullFill + partialFill;
    }

    // -------------------------
    // Gas: placeLimit
    // -------------------------

    function testGas_placeLimit_noMatch_rest() public {
        uint256 g0 = gasleft();
        (uint32 id, uint128 filled,) = _place(carol, uint8(Side.Ask), 10, 100 * SHARES);
        uint256 used = g0 - gasleft();

        assertTrue(id != 0);
        assertEq(filled, 0);

        emit log_named_uint("gas.placeLimit.noMatch.rest", used);
    }

    function testGas_placeLimit_matchThenRest() public {
        uint32[] memory asks = _seedAsksAtTick(10, 5, 20 * SHARES);

        uint256 g0 = gasleft();
        (uint32 id, uint128 filled,) = _place(dave, uint8(Side.Bid), 10, 150 * SHARES);
        uint256 used = g0 - gasleft();

        assertTrue(id != 0);
        assertEq(filled, 100 * SHARES);

        (uint256 touched, uint256 fullFill, uint256 partialFill) = _countMatchesFromSeeded(asks, uint8(Side.Ask));
        emit log_named_uint("match.placeLimit.touched", touched);
        emit log_named_uint("match.placeLimit.fullFill", fullFill);
        emit log_named_uint("match.placeLimit.partialFill", partialFill);

        emit log_named_uint("gas.placeLimit.matchThenRest", used);
    }

    // -------------------------
    // Gas: take
    // -------------------------

    function testGas_take_singleLevel_fullFill() public {
        uint32[] memory asks = _seedAsksAtTick(10, 5, 20 * SHARES);

        uint256 g0 = gasleft();
        (uint128 filled,) = _take(carol, uint8(Side.Bid), 10, 60 * SHARES, 60 * SHARES);
        uint256 used = g0 - gasleft();

        assertEq(filled, 60 * SHARES);

        (uint256 touched, uint256 fullFill, uint256 partialFill) = _countMatchesFromSeeded(asks, uint8(Side.Ask));
        emit log_named_uint("match.take.singleLevel.touched", touched);
        emit log_named_uint("match.take.singleLevel.fullFill", fullFill);
        emit log_named_uint("match.take.singleLevel.partialFill", partialFill);

        emit log_named_uint("gas.take.singleLevel.fullFill", used);
    }

    function testGas_take_walkManyLevels_fullFill() public {
        uint256 total = _seedAsksManyLevels(10, 20, 10, 5 * SHARES);

        assertLe(total, type(uint128).max);

        uint256 g0 = gasleft();
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint128 filled,) = _take(dave, uint8(Side.Bid), 20, uint128(total), uint128(total));
        uint256 used = g0 - gasleft();

        assertEq(uint256(filled), total);

        emit log_named_uint("match.take.walkManyLevels.filledShares", filled);
        emit log_named_uint("gas.take.walkManyLevels.fullFill", used);
    }

    // -------------------------
    // Gas: cancel
    // -------------------------

    function testGas_cancel_head_O1() public {
        uint32[] memory ids = _seedAsksAtTick(10, 5, 20 * SHARES);

        uint256 g0 = gasleft();
        vm.prank(alice);
        uint128 cancelled = platform.cancel(MARKET, OUTCOME, uint8(Side.Ask), ids[0], new uint32[](0));
        uint256 used = g0 - gasleft();

        assertEq(cancelled, 20 * SHARES);
        emit log_named_uint("gas.cancel.head.O1", used);
    }

    function testGas_cancel_middle_withCandidates() public {
        uint32[] memory ids = _seedAsksAtTick(10, 20, 10 * SHARES);

        uint32 target = ids[14];

        uint32[] memory candidates = tradingView.getCancelCandidates(MARKET, OUTCOME, uint8(Side.Ask), target, 8);
        assertTrue(candidates.length > 0);

        uint256 g0 = gasleft();
        vm.prank(alice);
        uint128 cancelled = platform.cancel(MARKET, OUTCOME, uint8(Side.Ask), target, candidates);
        uint256 used = g0 - gasleft();

        assertEq(cancelled, 10 * SHARES);
        emit log_named_uint("gas.cancel.middle.withCandidates.N8", used);
    }

    function testGas_cancel_middle_candidatesCurve() public {
        uint32[] memory ids = _seedAsksAtTick(10, 60, 10 * SHARES);
        uint32 target = ids[40];

        uint32[] memory c2 = tradingView.getCancelCandidates(MARKET, OUTCOME, uint8(Side.Ask), target, 2);
        uint256 g0 = gasleft();
        vm.prank(alice);
        platform.cancel(MARKET, OUTCOME, uint8(Side.Ask), target, c2);
        uint256 used2 = g0 - gasleft();
        emit log_named_uint("gas.cancel.middle.candidates.N2", used2);

        // Re-seed
        platform = DeployPlatform.deploy(address(this));
        tradingView = ITradingView(address(platform));
        _initMarket();
        _setupUsers();
        ids = _seedAsksAtTick(10, 60, 10 * SHARES);
        target = ids[40];

        uint32[] memory c4 = tradingView.getCancelCandidates(MARKET, OUTCOME, uint8(Side.Ask), target, 4);
        g0 = gasleft();
        vm.prank(alice);
        platform.cancel(MARKET, OUTCOME, uint8(Side.Ask), target, c4);
        uint256 used4 = g0 - gasleft();
        emit log_named_uint("gas.cancel.middle.candidates.N4", used4);

        // Re-seed again
        platform = DeployPlatform.deploy(address(this));
        tradingView = ITradingView(address(platform));
        _initMarket();
        _setupUsers();
        ids = _seedAsksAtTick(10, 60, 10 * SHARES);
        target = ids[40];

        uint32[] memory c16 = tradingView.getCancelCandidates(MARKET, OUTCOME, uint8(Side.Ask), target, 16);
        g0 = gasleft();
        vm.prank(alice);
        platform.cancel(MARKET, OUTCOME, uint8(Side.Ask), target, c16);
        uint256 used16 = g0 - gasleft();
        emit log_named_uint("gas.cancel.middle.candidates.N16", used16);
    }

    function testGas_take_singleLevel_fifoWorstCase() public {
        uint32[] memory asks = _seedAsksAtTick(10, 200, 1 * SHARES);

        uint256 g0 = gasleft();
        (uint128 filled,) = _take(dave, uint8(Side.Bid), 10, 200 * SHARES, 200 * SHARES);
        uint256 used = g0 - gasleft();

        assertEq(filled, 200 * SHARES);

        (uint256 touched, uint256 fullFill, uint256 partialFill) = _countMatchesFromSeeded(asks, uint8(Side.Ask));
        emit log_named_uint("match.take.fifoWorstCase.touched", touched);
        emit log_named_uint("match.take.fifoWorstCase.fullFill", fullFill);
        emit log_named_uint("match.take.fifoWorstCase.partialFill", partialFill);

        emit log_named_uint("gas.take.singleLevel.fifoWorstCase.200orders", used);
    }
}
