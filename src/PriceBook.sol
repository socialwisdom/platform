// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract PriceBook {
    error BadPrice();
    error BadVolume();

    enum OrderType {
        NONE,
        BUY,
        SELL
    }

    struct PriceLevel {
        uint8 higherLevel;
        uint8 lowerLevel;
        OrderType ty;
        uint256 totalVolume;
        uint256 headOrder;
        uint256 tailOrder;
    }

    struct Order {
        address maker;
        uint256 volume;
        uint256 prevOrder;
        uint256 nextOrder;
    }

    mapping(uint8 => PriceLevel) public priceLevels;
    mapping(uint256 => Order) public orders;

    uint256 public nextOrderId = 1;
    uint256 public minVolume = 10;

    uint8 public bestBuyPrice;
    uint8 public bestSellPrice;

    function createOrder(address maker, uint8 price, bool isBuyOrder, uint256 volume) external returns (uint256) {
        createPriceLevel(price, isBuyOrder);

        if (volume < minVolume) {
            revert BadVolume();
        }

        return createOrderAtLevelUnchecked(price, maker, volume);
    }

    function createOrderAtLevelUnchecked(uint8 price, address maker, uint256 volume) internal returns (uint256) {
        uint256 id = nextOrderId++;

        PriceLevel storage level = priceLevels[price];

        if (level.headOrder == 0) {
            require(level.tailOrder == 0, "bug(createOrderAtLevelUnchecked): headOrder == 0 but tailOrder != 0");
            require(level.totalVolume == 0, "bug(createOrderAtLevelUnchecked): totalVolume != 0 when empty");

            level.headOrder = id;
        } else {
            require(level.tailOrder != 0, "bug(createOrderAtLevelUnchecked): headOrder != 0 but tailOrder == 0");
            require(level.totalVolume != 0, "bug(createOrderAtLevelUnchecked): totalVolume == 0 when not empty");
        }

        if (level.tailOrder != 0) {
            orders[level.tailOrder].nextOrder = id;
        }

        orders[id] = Order({maker: maker, volume: volume, prevOrder: level.tailOrder, nextOrder: 0});

        level.totalVolume += volume;
        level.tailOrder = id;

        return id;
    }

    function removeOrderAtLevelUnchecked(uint8 price, uint256 orderId) internal {
        PriceLevel storage level = priceLevels[price];
        Order storage order = orders[orderId];

        if (order.prevOrder != 0) {
            orders[order.prevOrder].nextOrder = order.nextOrder;
        } else {
            require(level.headOrder == orderId, "bug(removeOrderAtLevelUnchecked): headOrder mismatch");
            level.headOrder = order.nextOrder;
        }

        if (order.nextOrder != 0) {
            orders[order.nextOrder].prevOrder = order.prevOrder;
        } else {
            require(level.tailOrder == orderId, "bug(removeOrderAtLevelUnchecked): tailOrder mismatch");
            level.tailOrder = order.prevOrder;
        }

        level.totalVolume -= order.volume;

        if (level.totalVolume == 0) {
            require(level.headOrder == 0, "bug(removeOrderAtLevelUnchecked): headOrder != 0 when totalVolume == 0");
            require(level.tailOrder == 0, "bug(removeOrderAtLevelUnchecked): tailOrder != 0 when totalVolume == 0");
            removePriceLevel(price);
        }

        delete orders[orderId];
    }

    function createPriceLevel(uint8 price, bool isBuyOrder) internal {
        if (price == 0 || price >= 100) {
            revert BadPrice();
        }

        if (priceLevels[price].ty != OrderType.NONE) {
            return;
        }

        if (isBuyOrder) {
            require(bestSellPrice == 0 || price < bestSellPrice, "unimplemented: Buy price crosses the best sell price");
            createBuyLevelUnchecked(price);
        } else {
            require(bestBuyPrice == 0 || price > bestBuyPrice, "unimplemented: Sell price crosses the best buy price");
            createSellLevelUnchecked(price);
        }
    }

    function createBuyLevelUnchecked(uint8 price) internal {
        if (price > bestBuyPrice) {
            priceLevels[price] = PriceLevel({
                higherLevel: 0,
                lowerLevel: bestBuyPrice,
                ty: OrderType.BUY,
                totalVolume: 0,
                headOrder: 0,
                tailOrder: 0
            });

            if (bestBuyPrice != 0) {
                require(priceLevels[bestBuyPrice].higherLevel == 0, "bug");
                priceLevels[bestBuyPrice].higherLevel = price;
            }

            bestBuyPrice = price;

            return;
        }

        // TODO: use `PriceLevel storage level = priceLevels[price];`
        uint8 higherLevel = bestBuyPrice;
        uint8 lowerLevel = 0;
        while (true) {
            lowerLevel = priceLevels[higherLevel].lowerLevel;

            if (lowerLevel < price) {
                break;
            } else {
                higherLevel = lowerLevel;
                lowerLevel = 0;
            }
        }

        createPriceLevelBetween(price, higherLevel, lowerLevel, OrderType.BUY);
    }

    function createSellLevelUnchecked(uint8 price) internal {
        if (price < bestSellPrice || bestSellPrice == 0) {
            priceLevels[price] = PriceLevel({
                higherLevel: bestSellPrice,
                lowerLevel: 0,
                ty: OrderType.SELL,
                totalVolume: 0,
                headOrder: 0,
                tailOrder: 0
            });

            if (bestSellPrice != 0) {
                require(priceLevels[bestSellPrice].lowerLevel == 0, "bug");
                priceLevels[bestSellPrice].lowerLevel = price;
            }

            bestSellPrice = price;

            return;
        }

        // TODO: use `PriceLevel storage level = priceLevels[price];`
        uint8 higherLevel = 0;
        uint8 lowerLevel = bestSellPrice;
        while (true) {
            higherLevel = priceLevels[lowerLevel].higherLevel;

            if (higherLevel > price || higherLevel == 0) {
                break;
            } else {
                lowerLevel = higherLevel;
                higherLevel = 0;
            }
        }

        createPriceLevelBetween(price, higherLevel, lowerLevel, OrderType.SELL);
    }

    function createPriceLevelBetween(uint8 price, uint8 higherLevel, uint8 lowerLevel, OrderType ty) internal {
        require(price > lowerLevel, "bug(createPriceLevelBetween): price must be higher than lowerLevel");
        require(
            higherLevel == 0 || price < higherLevel,
            "bug(createPriceLevelBetween): price must be lower than higherLevel"
        );

        priceLevels[price] = PriceLevel({
            higherLevel: higherLevel,
            lowerLevel: lowerLevel,
            ty: ty,
            totalVolume: 0,
            headOrder: 0,
            tailOrder: 0
        });

        if (higherLevel != 0) {
            require(priceLevels[higherLevel].ty == ty, "bug(createPriceLevelBetween): higherLevel type mismatch");
            priceLevels[higherLevel].lowerLevel = price;
        }

        if (lowerLevel != 0) {
            require(priceLevels[lowerLevel].ty == ty, "bug(createPriceLevelBetween): lowerLevel type mismatch");
            priceLevels[lowerLevel].higherLevel = price;
        }
    }

    function removePriceLevel(uint8 price) internal {
        OrderType levelTy = priceLevels[price].ty;

        require(levelTy != OrderType.NONE, "bug(removePriceLevel): inexistent price level");

        if (levelTy == OrderType.BUY) {
            removeBuyLevelUnchecked(price);
        } else {
            removeSellLevelUnchecked(price);
        }
    }

    function removeBuyLevelUnchecked(uint8 price) internal {
        PriceLevel storage level = priceLevels[price];

        if (level.higherLevel == 0) {
            bestBuyPrice = level.lowerLevel;
        } else {
            priceLevels[level.higherLevel].lowerLevel = level.lowerLevel;
        }

        if (level.lowerLevel != 0) {
            priceLevels[level.lowerLevel].higherLevel = level.higherLevel;
        }
    }

    function removeSellLevelUnchecked(uint8 price) internal {
        PriceLevel storage level = priceLevels[price];

        if (level.lowerLevel == 0) {
            bestSellPrice = level.higherLevel;
        } else {
            priceLevels[level.lowerLevel].higherLevel = level.higherLevel;
        }

        if (level.higherLevel != 0) {
            priceLevels[level.higherLevel].lowerLevel = level.lowerLevel;
        }
    }
}
