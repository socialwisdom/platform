// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract PriceBook {
    struct PriceLevel {
        uint8 higherLevel;
        uint8 lowerLevel;
        bool exists;
    }

    mapping(uint8 => PriceLevel) public priceLevels;

    uint8 public bestPrice;

    // TODO: impl addPriceAt function and shortcut for both addPriceAt and addPrice on failure.
    function addPrice(uint8 price) external {
        require(price < 100 && price > 0, "Price must be in [1, 99]");

        if (priceLevels[price].exists) {
            return;
        }

        if (bestPrice == 0) {
            bestPrice = price;

            priceLevels[price] = PriceLevel({higherLevel: 0, lowerLevel: 0, exists: true});

            return;
        }

        if (price > bestPrice) {
            priceLevels[price] = PriceLevel({higherLevel: 0, lowerLevel: bestPrice, exists: true});

            priceLevels[bestPrice].higherLevel = price;

            bestPrice = price;
        } else {
            uint8 currentLevel = bestPrice;

            uint8 higherLevel = 0;
            uint8 lowerLevel = 0;

            while (true) {
                uint8 nextLevel = priceLevels[currentLevel].lowerLevel;

                if (nextLevel == 0) {
                    higherLevel = currentLevel;
                    break;
                } else if (nextLevel < price) {
                    higherLevel = currentLevel;
                    lowerLevel = nextLevel;
                    break;
                } else {
                    currentLevel = nextLevel;
                }
            }

            priceLevels[price] = PriceLevel({higherLevel: higherLevel, lowerLevel: lowerLevel, exists: true});

            if (higherLevel != 0) {
                priceLevels[higherLevel].lowerLevel = price;
            }

            if (lowerLevel != 0) {
                priceLevels[lowerLevel].higherLevel = price;
            }
        }
    }

    function priceLevelAt(uint8 price) external view returns (PriceLevel memory) {
        return priceLevels[price];
    }

    function removePrice(uint8 price) external {
        PriceLevel memory priceLevel = priceLevels[price];

        if (!priceLevel.exists) {
            return;
        }

        if (priceLevel.higherLevel != 0) {
            priceLevels[priceLevel.higherLevel].lowerLevel = priceLevel.lowerLevel;
        } else {
            bestPrice = priceLevel.lowerLevel;
        }

        if (priceLevel.lowerLevel != 0) {
            priceLevels[priceLevel.lowerLevel].higherLevel = priceLevel.higherLevel;
        }

        delete priceLevels[price];
    }
}
