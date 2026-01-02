// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Platform} from "../src/Platform.sol";
import {Side} from "../src/types/Enums.sol";
import {Tick, OrderId} from "../src/types/IdTypes.sol";

contract OrderBookGasTest is Test {
    Platform internal platform;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA901);
    address internal dave = address(0xDA8E);

    uint64 internal constant MARKET = 1;
    uint8 internal constant OUTCOME = 0;

    function setUp() public {
        platform = new Platform();

        vm.prank(alice);
        platform.register();
        vm.prank(bob);
        platform.register();
        vm.prank(carol);
        platform.register();
        vm.prank(dave);
        platform.register();
    }

    // -------------------------
    // Helpers
    // -------------------------

    function _place(address user, Side side, uint8 tick, uint128 shares)
        internal
        returns (uint32 orderIdOr0, uint128 filled, uint256 pts)
    {
        vm.prank(user);
        return platform.placeLimit(MARKET, OUTCOME, side, Tick.wrap(tick), shares);
    }

    function _take(address user, Side side, uint8 limitTick, uint128 sharesRequested, uint128 minFill)
        internal
        returns (uint128 filled, uint256 pts)
    {
        vm.prank(user);
        return platform.take(MARKET, OUTCOME, side, Tick.wrap(limitTick), sharesRequested, minFill);
    }

    function _seedAsksAtTick(uint8 tick, uint256 nOrders, uint128 sharesEach) internal returns (uint32[] memory ids) {
        ids = new uint32[](nOrders);
        for (uint256 i = 0; i < nOrders; i++) {
            address maker = (i % 2 == 0) ? alice : bob;
            (uint32 id, uint128 filled,) = _place(maker, Side.Ask, tick, sharesEach);
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
    function _countMatchesFromSeeded(uint32[] memory makerIds, Side makerSide)
        internal
        view
        returns (uint256 touched, uint256 fullFill, uint256 partialFill)
    {
        uint256 len = makerIds.length;
        for (uint256 i = 0; i < len; i++) {
            (uint128 rem, uint128 req) = platform.getOrderRemainingAndRequested(MARKET, OUTCOME, makerSide, makerIds[i]);

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
        (uint32 id, uint128 filled,) = _place(carol, Side.Ask, 10, 100);
        uint256 used = g0 - gasleft();

        assertTrue(id != 0);
        assertEq(filled, 0);

        emit log_named_uint("gas.placeLimit.noMatch.rest", used);
    }

    function testGas_placeLimit_matchThenRest() public {
        uint32[] memory asks = _seedAsksAtTick(10, 5, 20);

        uint256 g0 = gasleft();
        (uint32 id, uint128 filled,) = _place(dave, Side.Bid, 10, 150);
        uint256 used = g0 - gasleft();

        assertTrue(id != 0);
        assertEq(filled, 100);

        (uint256 touched, uint256 fullFill, uint256 partialFill) = _countMatchesFromSeeded(asks, Side.Ask);
        emit log_named_uint("match.placeLimit.touched", touched);
        emit log_named_uint("match.placeLimit.fullFill", fullFill);
        emit log_named_uint("match.placeLimit.partialFill", partialFill);

        emit log_named_uint("gas.placeLimit.matchThenRest", used);
    }

    // -------------------------
    // Gas: take
    // -------------------------

    function testGas_take_singleLevel_fullFill() public {
        uint32[] memory asks = _seedAsksAtTick(10, 5, 20);

        uint256 g0 = gasleft();
        (uint128 filled,) = _take(carol, Side.Bid, 10, 60, 60);
        uint256 used = g0 - gasleft();

        assertEq(filled, 60);

        (uint256 touched, uint256 fullFill, uint256 partialFill) = _countMatchesFromSeeded(asks, Side.Ask);
        emit log_named_uint("match.take.singleLevel.touched", touched);
        emit log_named_uint("match.take.singleLevel.fullFill", fullFill);
        emit log_named_uint("match.take.singleLevel.partialFill", partialFill);

        emit log_named_uint("gas.take.singleLevel.fullFill", used);
    }

    function testGas_take_walkManyLevels_fullFill() public {
        uint256 total = _seedAsksManyLevels(10, 20, 10, 5);

        assertLe(total, type(uint128).max);

        uint256 g0 = gasleft();
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint128 filled,) = _take(dave, Side.Bid, 20, uint128(total), uint128(total));
        uint256 used = g0 - gasleft();

        assertEq(uint256(filled), total);

        emit log_named_uint("match.take.walkManyLevels.filledShares", filled);
        emit log_named_uint("gas.take.walkManyLevels.fullFill", used);
    }

    // -------------------------
    // Gas: cancel
    // -------------------------

    function testGas_cancel_head_O1() public {
        uint32[] memory ids = _seedAsksAtTick(10, 5, 20);

        uint256 g0 = gasleft();
        vm.prank(alice);
        uint128 cancelled = platform.cancel(MARKET, OUTCOME, Side.Ask, OrderId.wrap(ids[0]), new OrderId[](0));
        uint256 used = g0 - gasleft();

        assertEq(cancelled, 20);
        emit log_named_uint("gas.cancel.head.O1", used);
    }

    function testGas_cancel_middle_withCandidates() public {
        uint32[] memory ids = _seedAsksAtTick(10, 20, 10);

        OrderId target = OrderId.wrap(ids[14]);

        OrderId[] memory candidates = platform.getCancelCandidates(MARKET, OUTCOME, Side.Ask, target, 8);
        assertTrue(candidates.length > 0);

        uint256 g0 = gasleft();
        vm.prank(alice);
        uint128 cancelled = platform.cancel(MARKET, OUTCOME, Side.Ask, target, candidates);
        uint256 used = g0 - gasleft();

        assertEq(cancelled, 10);
        emit log_named_uint("gas.cancel.middle.withCandidates.N8", used);
    }

    function testGas_cancel_middle_candidatesCurve() public {
        uint32[] memory ids = _seedAsksAtTick(10, 60, 10);
        OrderId target = OrderId.wrap(ids[40]);

        OrderId[] memory c2 = platform.getCancelCandidates(MARKET, OUTCOME, Side.Ask, target, 2);
        uint256 g0 = gasleft();
        vm.prank(alice);
        platform.cancel(MARKET, OUTCOME, Side.Ask, target, c2);
        uint256 used2 = g0 - gasleft();
        emit log_named_uint("gas.cancel.middle.candidates.N2", used2);

        // Re-seed
        platform = new Platform();
        vm.prank(alice);
        platform.register();
        vm.prank(bob);
        platform.register();
        vm.prank(carol);
        platform.register();
        vm.prank(dave);
        platform.register();
        ids = _seedAsksAtTick(10, 60, 10);
        target = OrderId.wrap(ids[40]);

        OrderId[] memory c4 = platform.getCancelCandidates(MARKET, OUTCOME, Side.Ask, target, 4);
        g0 = gasleft();
        vm.prank(alice);
        platform.cancel(MARKET, OUTCOME, Side.Ask, target, c4);
        uint256 used4 = g0 - gasleft();
        emit log_named_uint("gas.cancel.middle.candidates.N4", used4);

        // Re-seed again
        platform = new Platform();
        vm.prank(alice);
        platform.register();
        vm.prank(bob);
        platform.register();
        vm.prank(carol);
        platform.register();
        vm.prank(dave);
        platform.register();
        ids = _seedAsksAtTick(10, 60, 10);
        target = OrderId.wrap(ids[40]);

        OrderId[] memory c16 = platform.getCancelCandidates(MARKET, OUTCOME, Side.Ask, target, 16);
        g0 = gasleft();
        vm.prank(alice);
        platform.cancel(MARKET, OUTCOME, Side.Ask, target, c16);
        uint256 used16 = g0 - gasleft();
        emit log_named_uint("gas.cancel.middle.candidates.N16", used16);
    }

    function testGas_take_singleLevel_fifoWorstCase() public {
        uint32[] memory asks = _seedAsksAtTick(10, 200, 1);

        uint256 g0 = gasleft();
        (uint128 filled,) = _take(dave, Side.Bid, 10, 200, 200);
        uint256 used = g0 - gasleft();

        assertEq(filled, 200);

        (uint256 touched, uint256 fullFill, uint256 partialFill) = _countMatchesFromSeeded(asks, Side.Ask);
        emit log_named_uint("match.take.fifoWorstCase.touched", touched);
        emit log_named_uint("match.take.fifoWorstCase.fullFill", fullFill);
        emit log_named_uint("match.take.fifoWorstCase.partialFill", partialFill);

        emit log_named_uint("gas.take.singleLevel.fifoWorstCase.200orders", used);
    }
}
