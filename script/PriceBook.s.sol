// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceBook} from "../src/PriceBook.sol";
import {Script} from "forge-std/Script.sol";

contract PriceBookScript is Script {
    PriceBook public priceBook;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        priceBook = new PriceBook();

        vm.stopBroadcast();
    }
}
