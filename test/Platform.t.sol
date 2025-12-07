// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Platform} from "../src/Platform.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

contract PlatformTest is Test {
    Platform public platform;

    function setUp() public {
        vm.startPrank(address(0x42));

        platform = new Platform();
    }

    function test_buy_check() public {
        uint256 marketId = platform.createMarket();

        for (uint8 price = 10; price <= 30; price++) {
            for (uint8 i = 0; i < 10; i++) {
                platform.sell(marketId, price, 1_000);
            }
        }

        platform.buy(marketId, 50, 1_234_567);
    }
}
