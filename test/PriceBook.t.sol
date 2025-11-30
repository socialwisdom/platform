// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceBook} from "../src/PriceBook.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

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
        assert(!priceBook.bestSellOrder().exists());
    }

    function test_buyLevelsCreation() public {
        Level memory level;

        // Levels: [25].
        level = priceBook.createBuyOrder(25).level;

        assertEq(priceBook.bestBuyPrice(), 25);
        assertLevels(25);

        // Levels: [30, 25].
        level = priceBook.createBuyOrder(30).level;

        assertEq(priceBook.bestBuyPrice(), 30);
        assertLevels(30, 25);

        // Levels: [30, 25, 20].
        level = priceBook.createBuyOrder(20).level;

        assertEq(priceBook.bestBuyPrice(), 30);
        assertLevels(30, 25, 20);

        // Levels: [30, 29, 25, 20].
        level = priceBook.createBuyOrder(29).level;

        assertEq(priceBook.bestBuyPrice(), 30);
        assertLevels(30, 29, 25, 20);

        // Levels: [30, 29, 25, 21, 20].
        level = priceBook.createBuyOrder(21).level;

        assertEq(priceBook.bestBuyPrice(), 30);
        assertLevels(30, 29, 25, 21, 20);
    }

    function assertLevels(uint8[] memory prices) internal view {
        require(prices.length > 0, "assertLevels: prices array must not be empty");

        for (uint256 i = 1; i < prices.length; i++) {
            require(prices[i - 1] > prices[i], "assertLevels: prices must be sorted in descending order");
        }

        Level memory level = PriceBookExt.level(priceBook, prices[0]);

        for (uint256 i = 0; i < prices.length; i++) {
            assertEq(level.price, prices[i]);
            console.log("> price: ", level.price);

            if (i < prices.length - 1) {
                level = level.next();
            } else {
                console.log(">> checked next doesn't exist after :", level.price);
                assert(!level.next().exists());
            }
        }

        for (uint256 i = prices.length; i > 0; i--) {
            assertEq(level.price, prices[i - 1]);
            console.log("< price: ", level.price);

            if (i > 1) {
                level = level.prev();
            } else {
                console.log("<< checked prev doesn't exist before :", level.price);
                assert(!level.prev().exists());
            }
        }
    }

    function assertLevels(uint8 i0) public view {
        uint8[] memory prices = new uint8[](1);
        prices[0] = i0;

        assertLevels(prices);
    }

    function assertLevels(uint8 i0, uint8 i1) public view {
        uint8[] memory prices = new uint8[](2);
        prices[0] = i0;
        prices[1] = i1;

        assertLevels(prices);
    }

    function assertLevels(uint8 i0, uint8 i1, uint8 i2) public view {
        uint8[] memory prices = new uint8[](3);
        prices[0] = i0;
        prices[1] = i1;
        prices[2] = i2;

        assertLevels(prices);
    }

    function assertLevels(uint8 i0, uint8 i1, uint8 i2, uint8 i3) public view {
        uint8[] memory prices = new uint8[](4);
        prices[0] = i0;
        prices[1] = i1;
        prices[2] = i2;
        prices[3] = i3;

        assertLevels(prices);
    }

    function assertLevels(uint8 i0, uint8 i1, uint8 i2, uint8 i3, uint8 i4) public view {
        uint8[] memory prices = new uint8[](5);
        prices[0] = i0;
        prices[1] = i1;
        prices[2] = i2;
        prices[3] = i3;
        prices[4] = i4;

        assertLevels(prices);
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

    function nextN(PriceBookTest.Level memory self, uint256 n)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        for (uint256 i = 0; i < n; i++) {
            self = next(self);
        }

        return self;
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

    function prevN(PriceBookTest.Level memory self, uint256 n)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        for (uint256 i = 0; i < n; i++) {
            self = prev(self);
        }

        return self;
    }

    function prev(PriceBookTest.Level memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        if (isBuy(self)) {
            return higher(self);
        } else {
            return lower(self);
        }
    }

    function higher(PriceBookTest.Level memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        PriceBookTest.Level memory higherLevel = PriceBookExt.level(self.priceBook, self.data.higherLevel);

        if (higherLevel.price != 0) {
            require(higherLevel.data.lowerLevel == self.price, "LevelExt: nonzero higher level's lowerLevel mismatch");
        }

        return higherLevel;
    }

    function lower(PriceBookTest.Level memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        PriceBookTest.Level memory lowerLevel = PriceBookExt.level(self.priceBook, self.data.lowerLevel);

        if (lowerLevel.price != 0) {
            require(lowerLevel.data.higherLevel == self.price, "LevelExt: nonzero lower level's higherLevel mismatch");
        }

        return lowerLevel;
    }

    modifier onlyExisting(PriceBookTest.Level memory self) {
        require(exists(self), "LevelExt: level does not exist");
        _;
    }
}

library OrderExt {
    function refetch(PriceBookTest.Order memory self) internal view returns (PriceBookTest.Order memory) {
        return PriceBookExt.order(self.priceBook, self.id);
    }

    function exists(PriceBookTest.Order memory self) internal pure returns (bool) {
        bool _exists = self.data.maker != address(0);

        if (_exists) {
            require(self.id != 0, "OrderExt: existing order's id must not be 0");
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

    function nextN(PriceBookTest.Order memory self, uint256 n)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        for (uint256 i = 0; i < n; i++) {
            self = next(self);
        }

        return self;
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

    function prevN(PriceBookTest.Order memory self, uint256 n)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        for (uint256 i = 0; i < n; i++) {
            self = prev(self);
        }

        return self;
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

    function createBuyOrder(PriceBook priceBook, uint8 price) internal returns (PriceBookTest.Order memory) {
        return createBuyOrder(priceBook, price, DEFAULT_VOLUME);
    }

    function createBuyOrder(PriceBook priceBook, uint8 price, uint256 volume)
        internal
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Order memory _buyOrder =
            order(priceBook, priceBook.createOrder(address(0x42), price, true, volume));

        require(OrderExt.isTail(_buyOrder), "PriceBookExt: created buy order is not tail");
        require(_buyOrder.level.price == price, "PriceBookExt: created buy order's level price mismatch");
        require(LevelExt.isBuy(_buyOrder.level), "PriceBookExt: created buy order's level is not a buy level");

        return _buyOrder;
    }

    function createSellOrder(PriceBook priceBook, uint8 price) internal returns (PriceBookTest.Order memory) {
        return createSellOrder(priceBook, price, DEFAULT_VOLUME);
    }

    function createSellOrder(PriceBook priceBook, uint8 price, uint256 volume)
        internal
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Order memory _sellOrder =
            order(priceBook, priceBook.createOrder(address(0x42), price, false, volume));

        require(OrderExt.isTail(_sellOrder), "PriceBookExt: created sell order is not tail");
        require(_sellOrder.level.price == price, "PriceBookExt: created sell order's level price mismatch");
        require(!LevelExt.isBuy(_sellOrder.level), "PriceBookExt: created sell order's level is a buy level");

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

        if (priceBook.bestBuyPrice() != 0) {
            require(OrderExt.exists(_bestBuyOrder), "PriceBookExt: best buy order does not exist");
            require(
                OrderExt.isHead(_bestBuyOrder),
                "PriceBookExt: best buy order is not head of best buy level's order list"
            );
            require(
                !LevelExt.exists(LevelExt.higher(_bestBuyOrder.level)),
                "PriceBookExt: best buy level has a higher level"
            );
        }

        return _bestBuyOrder;
    }

    function bestSellOrder(PriceBook priceBook) internal view returns (PriceBookTest.Order memory) {
        PriceBookTest.Order memory _bestSellOrder = order(priceBook, bestSellLevel(priceBook).data.headOrder);

        if (priceBook.bestSellPrice() != 0) {
            require(OrderExt.exists(_bestSellOrder), "PriceBookExt: best sell order does not exist");
            require(
                OrderExt.isHead(_bestSellOrder),
                "PriceBookExt: best sell order is not head of best sell level's order list"
            );
            require(
                !LevelExt.exists(LevelExt.lower(_bestSellOrder.level)),
                "PriceBookExt: best sell level has a lower level"
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
