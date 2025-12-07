// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Platform} from "../src/Platform.sol";
import {Test} from "forge-std/Test.sol";
import {TestsLib, TestPlatform, TestMarket, TestLevel, TestOrder} from "../libraries/Tests.sol";

contract PlatformTest is Test {
    using TestsLib for TestPlatform;
    using TestsLib for TestMarket;
    using TestsLib for TestLevel;
    using TestsLib for TestOrder;

    TestPlatform public platform;

    function setUp() public {
        vm.startPrank(address(0x42));

        platform = TestPlatform({platform: new Platform(), vm: vm});
    }

    function test_buy_check() public {
        TestMarket memory market = platform.createMarket();

        for (uint8 price = 10; price <= 30; price++) {
            for (uint8 i = 0; i < 10; i++) {
                market.sell(price);
            }
        }

        uint256 orderVolume = 1_234_567;

        console2.log("Best sell price before buy:", market.bestSellPrice());
        console2.log("Order volume:", orderVolume);

        TestOrder memory order = market.buy(50, orderVolume);

        console2.log("Best sell price after buy:", market.bestSellPrice());
        console2.log("Order volume:", order.volume());
    }
}
