// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceBook} from "../src/PriceBook.sol";
import {Test} from "forge-std/Test.sol";

contract PriceBookTest is Test {
    PriceBook public priceBook;

    function setUp() public {
        priceBook = new PriceBook();
    }

    function test_AddPrice() public {
        priceBook.addPrice(50);

        uint8[] memory prices = new uint8[](1);
        prices[0] = 50;
        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(50);

        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(70);

        prices = new uint8[](2);
        prices[0] = 70;
        prices[1] = 50;
        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(70);

        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(60);

        prices = new uint8[](3);
        prices[0] = 70;
        prices[1] = 60;
        prices[2] = 50;
        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(30);

        prices = new uint8[](4);
        prices[0] = 70;
        prices[1] = 60;
        prices[2] = 50;
        prices[3] = 30;
        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(30);

        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(40);

        prices = new uint8[](5);
        prices[0] = 70;
        prices[1] = 60;
        prices[2] = 50;
        prices[3] = 40;
        prices[4] = 30;
        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(40);

        PriceBookTest.assertPrices(prices);
    }

    function test_RemovePrice() public {
        priceBook.addPrice(50);
        priceBook.removePrice(50);

        uint8[] memory prices = new uint8[](0);
        PriceBookTest.assertPrices(prices);

        priceBook.removePrice(50);
        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(70);
        priceBook.addPrice(50);
        priceBook.removePrice(70);

        prices = new uint8[](1);
        prices[0] = 50;
        PriceBookTest.assertPrices(prices);

        priceBook.removePrice(70);
        PriceBookTest.assertPrices(prices);

        priceBook.addPrice(60);
        priceBook.addPrice(40);
        priceBook.addPrice(30);
        priceBook.removePrice(50);

        prices = new uint8[](3);
        prices[0] = 60;
        prices[1] = 40;
        prices[2] = 30;
        PriceBookTest.assertPrices(prices);

        priceBook.removePrice(50);

        PriceBookTest.assertPrices(prices);

        priceBook.removePrice(30);

        prices = new uint8[](2);
        prices[0] = 60;
        prices[1] = 40;
        PriceBookTest.assertPrices(prices);

        priceBook.removePrice(30);

        PriceBookTest.assertPrices(prices);
    }

    function assertPrices(uint8[] memory expectedPrices) internal view {
        for (uint256 i = 1; i < expectedPrices.length; i++) {
            require(expectedPrices[i - 1] >= expectedPrices[i], "Prices are not sorted in descending order");
        }

        for (uint8 i = 1; i < 100; i++) {
            if (!arrayContains(expectedPrices, i)) {
                PriceBook.PriceLevel memory price = priceBook.priceLevelAt(i);
                require(price.higherLevel == 0, "Level should not exist");
                require(price.lowerLevel == 0, "Level should not exist");
                require(!price.exists, "Level should not exist");
            }
        }

        for (uint256 i = 0; i < expectedPrices.length; i++) {
            uint8 priceLevel = expectedPrices[i];
            PriceBook.PriceLevel memory price = priceBook.priceLevelAt(priceLevel);

            uint8 expectedHigherLevel = i == 0 ? 0 : expectedPrices[i - 1];
            uint8 expectedLowerLevel = i == expectedPrices.length - 1 ? 0 : expectedPrices[i + 1];

            require(price.higherLevel == expectedHigherLevel, "Higher level mismatch");
            require(price.lowerLevel == expectedLowerLevel, "Lower level mismatch");
        }

        if (expectedPrices.length == 0) {
            require(priceBook.bestPrice() == 0, "Best price should be 0");
        } else {
            require(priceBook.bestPrice() == expectedPrices[0], "Best price mismatch");
        }
    }

    function arrayContains(uint8[] memory array, uint8 value) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                return true;
            }
        }

        return false;
    }
}
