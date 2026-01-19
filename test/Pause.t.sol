// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../src/Platform.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {DeployPlatform} from "../script/lib/DeployPlatform.sol";

contract PauseTest is Test {
    Platform internal platform;

    address internal alice = address(0xA11CE);
    address internal resolver = address(0xBEEF);

    function setUp() public {
        platform = DeployPlatform.deploy(address(this));
    }

    function test_AllStateChangingFunctionsPaused() public {
        platform.pause();
        assertTrue(platform.isPaused());

        vm.startPrank(alice);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.register();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.deposit(1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.withdraw(1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.depositShares(1, 0, 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.withdrawShares(1, 0, 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.placeLimit(1, 0, 0, 50, 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.take(1, 0, 0, 50, 1, 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.cancel(1, 0, 0, 1, new uint32[](0));

        string[] memory labels = new string[](2);
        labels[0] = "Yes";
        labels[1] = "No";

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.createMarket(resolver, 2, 0, true, 0, 0, 0, bytes32(0), bytes32(0), "Q", labels, "Rules");

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.resolveMarket(1, 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.finalizeMarket(1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.sweepMarketFees(1);

        vm.stopPrank();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.setFeeExempt(alice, true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        platform.setMarketCreator(alice, true);

        platform.unpause();
        assertFalse(platform.isPaused());
    }
}
