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
        assert(!priceBook.bestSellOrder().exists());
    }

    function test_sample() public pure {
        assert(2 + 2 == 4);
    }
}

library LevelExt {
    function exists(PriceBookTest.Level memory self) internal pure returns (bool) {
        return self.data.ty != PriceBook.OrderType.NONE;
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
        return PriceBookExt.level(self.priceBook, self.data.higherLevel);
    }

    function lower(PriceBookTest.Level memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        return PriceBookExt.level(self.priceBook, self.data.lowerLevel);
    }

    modifier onlyExisting(PriceBookTest.Level memory self) {
        require(exists(self), "LevelExt: level does not exist");
        _;
    }
}

library OrderExt {
    function exists(PriceBookTest.Order memory self) internal pure returns (bool) {
        return self.data.maker != address(0);
    }

    function price(PriceBookTest.Order memory self) internal pure onlyExisting(self) returns (uint8) {
        return self.level.price;
    }

    function isBuy(PriceBookTest.Order memory self) internal pure onlyExisting(self) returns (bool) {
        return LevelExt.isBuy(self.level);
    }

    function level(PriceBookTest.Order memory self)
        internal
        pure
        onlyExisting(self)
        returns (PriceBookTest.Level memory)
    {
        return self.level;
    }

    function next(PriceBookTest.Order memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        return PriceBookExt.order(self.priceBook, self.data.nextOrder);
    }

    function prev(PriceBookTest.Order memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        return PriceBookExt.order(self.priceBook, self.data.prevOrder);
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
        return order(priceBook, priceBook.createOrder(address(0x42), price, true, volume));
    }

    function createDefaultSellOrder(PriceBook priceBook, uint8 price) internal returns (PriceBookTest.Order memory) {
        return createSellOrder(priceBook, price, DEFAULT_VOLUME);
    }

    function createSellOrder(PriceBook priceBook, uint8 price, uint256 volume)
        internal
        returns (PriceBookTest.Order memory)
    {
        return order(priceBook, priceBook.createOrder(address(0x42), price, false, volume));
    }

    function bestBuyLevel(PriceBook priceBook) internal view returns (PriceBookTest.Level memory) {
        return level(priceBook, priceBook.bestBuyPrice());
    }

    function bestSellLevel(PriceBook priceBook) internal view returns (PriceBookTest.Level memory) {
        return level(priceBook, priceBook.bestSellPrice());
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
        return order(priceBook, bestBuyLevel(priceBook).data.headOrder);
    }

    function bestSellOrder(PriceBook priceBook) internal view returns (PriceBookTest.Order memory) {
        return order(priceBook, bestSellLevel(priceBook).data.headOrder);
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
