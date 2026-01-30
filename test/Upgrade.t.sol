// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../src/Platform.sol";
import {PlatformStorage} from "../src/storage/PlatformStorage.sol";
import {PlatformTradingViewModule} from "../src/modules/PlatformTradingViewModule.sol";
import {DeployPlatform} from "../script/lib/DeployPlatform.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PlatformV2 is Platform {
    function getProtocolVersion() external view returns (uint8) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
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
        address newTradingViewModule = address(new PlatformTradingViewModule());

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        platform.initialize(owner, newTradingViewModule);
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
