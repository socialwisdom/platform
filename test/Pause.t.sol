// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../src/Platform.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract PauseTest is Test {
    Platform internal platform;

    address internal alice = address(0xA11CE);
    address internal resolver = address(0xBEEF);

    function setUp() public {
        platform = new Platform();
    }

    function test_AllStateChangingFunctionsPaused() public {
        platform.pause();
        assertTrue(platform.isPaused());

        vm.startPrank(alice);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.register();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.deposit(1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.withdraw(1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.depositShares(1, 0, 1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.withdrawShares(1, 0, 1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.placeLimit(1, 0, 0, 50, 1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.take(1, 0, 0, 50, 1, 1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.cancel(1, 0, 0, 1, new uint32[](0));

        string[] memory labels = new string[](2);
        labels[0] = "Yes";
        labels[1] = "No";

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.createMarket(resolver, 2, 0, true, 0, 0, 0, bytes32(0), bytes32(0), "Q", labels, "Rules");

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.resolveMarket(1, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.finalizeMarket(1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.sweepMarketFees(1);

        vm.stopPrank();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.setFeeExempt(alice, true);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        platform.setMarketCreator(alice, true);

        platform.unpause();
        assertFalse(platform.isPaused());
    }
}
