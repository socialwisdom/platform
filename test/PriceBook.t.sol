// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceBook} from "../src/PriceBook.sol";
import {Test} from "forge-std/Test.sol";

contract PriceBookTest is Test {
    PriceBook public priceBook;

    function setUp() public {
        priceBook = new PriceBook();
    }
}
