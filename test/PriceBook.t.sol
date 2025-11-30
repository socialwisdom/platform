// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceBook} from "../src/PriceBook.sol";
import {Test} from "forge-std/Test.sol";

contract PriceBookTest is Test {
    using LevelExt for Level;
    using OrderExt for Order;
    using PriceBookExt for PriceBook;

    PriceBook public priceBook;

    struct Level {
        uint8 price;
        PriceBook.PriceLevel data;
        PriceBook priceBook;
    }

    struct Order {
        uint256 id;
        Level level;
        PriceBook.Order data;
        PriceBook priceBook;
    }

    function setUp() public {
        priceBook = new PriceBook();

        assert(!priceBook.bestBuyOrder().exists());
        // assert(!priceBook.bestSellOrder().exists());
    }

    function test_sample() public pure {
        assert(2 + 2 == 4);
    }
}

library LevelExt {
    function exists(PriceBookTest.Level memory self) internal pure returns (bool) {
        bool _exists = self.data.ty != PriceBook.OrderType.NONE;

        if (_exists) {
            require(self.data.totalVolume > 0, "LevelExt: existing level's totalVolume must be > 0");
            require(self.data.headOrder != 0, "LevelExt: existing level's headOrder must not be 0");
            require(self.data.tailOrder != 0, "LevelExt: existing level's tailOrder must not be 0");
        }

        return _exists;
    }

    function isBuy(PriceBookTest.Level memory self) internal pure onlyExisting(self) returns (bool) {
        return self.data.ty == PriceBook.OrderType.BUY;
    }

    function next(PriceBookTest.Level memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        if (isBuy(self)) {
            return lower(self);
        } else {
            return higher(self);
        }
    }

    function higher(PriceBookTest.Level memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        PriceBookTest.Level memory higherLevel = PriceBookExt.level(self.priceBook, self.data.higherLevel);

        require(higherLevel.data.lowerLevel == self.price, "LevelExt: higher level's lowerLevel mismatch");

        return higherLevel;
    }

    function lower(PriceBookTest.Level memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        PriceBookTest.Level memory lowerLevel = PriceBookExt.level(self.priceBook, self.data.lowerLevel);

        require(lowerLevel.data.higherLevel == self.price, "LevelExt: lower level's higherLevel mismatch");

        return lowerLevel;
    }

    modifier onlyExisting(PriceBookTest.Level memory self) {
        require(exists(self), "LevelExt: level does not exist");
        _;
    }
}

library OrderExt {
    function exists(PriceBookTest.Order memory self) internal pure returns (bool) {
        bool _exists = self.data.maker != address(0);

        if (_exists) {
            require(self.id != 0, "OrderExt: existing order's id must not be 0");
            require(LevelExt.exists(self.level), "OrderExt: order's level does not exist");
            require(self.data.volume > 0, "OrderExt: existing order's volume must be > 0");
        }

        return _exists;
    }

    function price(PriceBookTest.Order memory self) internal pure onlyExisting(self) returns (uint8) {
        return self.level.price;
    }

    function isBuy(PriceBookTest.Order memory self) internal pure onlyExisting(self) returns (bool) {
        return LevelExt.isBuy(self.level);
    }

    function next(PriceBookTest.Order memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Order memory nextOrder = PriceBookExt.order(self.priceBook, self.data.nextOrder);

        require(nextOrder.data.prevOrder == self.id, "OrderExt: next order's prevOrder mismatch");

        return nextOrder;
    }

    function prev(PriceBookTest.Order memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Order memory prevOrder = PriceBookExt.order(self.priceBook, self.data.prevOrder);

        require(prevOrder.data.nextOrder == self.id, "OrderExt: prev order's nextOrder mismatch");

        return prevOrder;
    }

    function isHead(PriceBookTest.Order memory self) internal pure onlyExisting(self) returns (bool) {
        return self.data.prevOrder == 0;
    }

    function isTail(PriceBookTest.Order memory self) internal pure onlyExisting(self) returns (bool) {
        return self.data.nextOrder == 0;
    }

    function head(PriceBookTest.Order memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        while (!isHead(self)) {
            self = prev(self);
        }

        return self;
    }

    function tail(PriceBookTest.Order memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        while (!isTail(self)) {
            self = next(self);
        }

        return self;
    }

    modifier onlyExisting(PriceBookTest.Order memory self) {
        require(exists(self), "OrderExt: order does not exist");
        _;
    }
}

library PriceBookExt {
    uint256 constant DEFAULT_VOLUME = 1_000;

    function createDefaultBuyOrder(PriceBook priceBook, uint8 price) internal returns (PriceBookTest.Order memory) {
        return createBuyOrder(priceBook, price, DEFAULT_VOLUME);
    }

    function createBuyOrder(PriceBook priceBook, uint8 price, uint256 volume)
        internal
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Order memory _buyOrder =
            order(priceBook, priceBook.createOrder(address(0x42), price, true, volume));

        // TODO: check level consistency.
        require(OrderExt.isTail(_buyOrder), "PriceBookExt: created buy order is not tail");

        return _buyOrder;
    }

    function createDefaultSellOrder(PriceBook priceBook, uint8 price) internal returns (PriceBookTest.Order memory) {
        return createSellOrder(priceBook, price, DEFAULT_VOLUME);
    }

    function createSellOrder(PriceBook priceBook, uint8 price, uint256 volume)
        internal
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Order memory _sellOrder =
            order(priceBook, priceBook.createOrder(address(0x42), price, false, volume));

        // TODO: check level consistency.
        require(OrderExt.isTail(_sellOrder), "PriceBookExt: created sell order is not tail");

        return _sellOrder;
    }

    function bestBuyLevel(PriceBook priceBook) internal view returns (PriceBookTest.Level memory) {
        PriceBookTest.Level memory bestBuy = level(priceBook, priceBook.bestBuyPrice());

        if (LevelExt.exists(bestBuy)) {
            require(LevelExt.isBuy(bestBuy), "PriceBookExt: best buy level is not a buy level");
            require(bestBuy.data.higherLevel == 0, "PriceBookExt: best buy level's higherLevel is not 0");
        }

        return bestBuy;
    }

    function bestSellLevel(PriceBook priceBook) internal view returns (PriceBookTest.Level memory) {
        PriceBookTest.Level memory bestSell = level(priceBook, priceBook.bestSellPrice());

        if (LevelExt.exists(bestSell)) {
            require(!LevelExt.isBuy(bestSell), "PriceBookExt: best sell level is a buy level");
            require(bestSell.data.lowerLevel == 0, "PriceBookExt: best sell level's lowerLevel is not 0");
        }

        return bestSell;
    }

    function level(PriceBook priceBook, uint8 price) internal view returns (PriceBookTest.Level memory) {
        require(price < 100, "price must be < 100");

        (
            uint8 _higherLevel,
            uint8 _lowerLevel,
            PriceBook.OrderType _ty,
            uint256 _totalVolume,
            uint256 _headOrder,
            uint256 _tailOrder
        ) = priceBook.priceLevels(price);

        return PriceBookTest.Level(
            price, PriceBook.PriceLevel(_higherLevel, _lowerLevel, _ty, _totalVolume, _headOrder, _tailOrder), priceBook
        );
    }

    function bestBuyOrder(PriceBook priceBook) internal view returns (PriceBookTest.Order memory) {
        PriceBookTest.Order memory _bestBuyOrder = order(priceBook, bestBuyLevel(priceBook).data.headOrder);

        // TODO: check level consistency.
        if (OrderExt.exists(_bestBuyOrder)) {
            require(
                OrderExt.isHead(_bestBuyOrder),
                "PriceBookExt: best buy order is not head of best buy level's order list"
            );
        }

        return _bestBuyOrder;
    }

    function bestSellOrder(PriceBook priceBook) internal view returns (PriceBookTest.Order memory) {
        PriceBookTest.Order memory _bestSellOrder = order(priceBook, bestSellLevel(priceBook).data.headOrder);

        // TODO: check level consistency.
        if (OrderExt.exists(_bestSellOrder)) {
            require(
                OrderExt.isHead(_bestSellOrder),
                "PriceBookExt: best sell order is not head of best sell level's order list"
            );
        }

        return _bestSellOrder;
    }

    function order(PriceBook priceBook, uint256 orderId) internal view returns (PriceBookTest.Order memory) {
        (address _maker, uint256 _volume, uint256 _prevOrder, uint256 _nextOrder) = priceBook.orders(orderId);

        PriceBookTest.Order memory _order = PriceBookTest.Order(
            orderId, level(priceBook, 0), PriceBook.Order(_maker, _volume, _prevOrder, _nextOrder), priceBook
        );

        if (OrderExt.exists(_order)) {
            PriceBookTest.Order memory orderHead = OrderExt.head(_order);

            for (uint8 price = 1; price < 100; price++) {
                PriceBookTest.Level memory _level = level(priceBook, price);

                if (!LevelExt.exists(_level)) {
                    continue;
                }

                if (_level.data.headOrder == orderHead.id) {
                    _order.level = _level;
                    break;
                }
            }
        }

        return _order;
    }
}
