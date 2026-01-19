// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../src/Platform.sol";
import {StorageSlot} from "../src/storage/StorageSlot.sol";
import {PlatformStorage} from "../src/storage/PlatformStorage.sol";
import {DeployPlatform} from "./lib/DeployPlatform.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PlatformV2 is Platform {
    function getProtocolVersion() external view returns (uint8) {
        PlatformStorage storage s = StorageSlot.layout();
        return s.protocolVersion;
    }
}

contract UpgradeTest is Test {
    Platform internal platform;
    address internal owner = address(this);
    address internal alice = address(0xA11CE);

    function setUp() public {
        platform = DeployPlatform.deploy(owner);
    }

    function test_Initialize_RevertsOnSecondCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        platform.initialize(owner);
    }

    function test_UpgradeAndReinitialize() public {
        PlatformV2 implV2 = new PlatformV2();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        platform.upgradeToAndCall(address(implV2), abi.encodeCall(Platform.reinitializeV2, ()));

        platform.upgradeToAndCall(address(implV2), abi.encodeCall(Platform.reinitializeV2, ()));

        uint8 version = PlatformV2(address(platform)).getProtocolVersion();
        assertEq(version, 2);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        platform.reinitializeV2();
    }
}
