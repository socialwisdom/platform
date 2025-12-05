// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OrderBook} from "../src/OrderBook.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract OrderBookTest is Test {
    using DappExt for Dapp;
    using LevelTestExt for Level;
    using OrderTestExt for Order;

    Dapp public dapp;

    struct Dapp {
        OrderBook orderBook;
        Vm vm;
    }

    struct Level {
        uint8 price;
        bool isBuy;
        OrderBook orderBook;
        Vm vm;
    }

    struct Order {
        uint256 id;
        OrderBook orderBook;
        Vm vm;
    }

    function setUp() public {
        vm.startPrank(address(0x42));

        dapp.orderBook = new OrderBook();
        dapp.vm = vm;

        assert(dapp.orderBook.bestBuyPrice() == 0);
        assert(dapp.orderBook.bestSellPrice() == 0);
        assert(dapp.orderBook.nextOrderId() == 1);
        assert(dapp.orderBook.MIN_VOLUME() <= DappExt.DEFAULT_VOLUME);
    }

    function test_buy_sample() public {
        for (uint8 price = 10; price <= 30; price++) {
            for (uint8 i = 0; i < 10; i++) {
                dapp.sell(price);
            }
        }

        dapp.buy(50, DappExt.DEFAULT_VOLUME * 1_000);
    }
}

library DappExt {
    using DappExt for OrderBookTest.Dapp;

    uint256 constant DEFAULT_VOLUME = 12_345;

    function buy(OrderBookTest.Dapp memory self, uint8 price) internal returns (OrderBookTest.Order memory) {
        return self.buy(price, DEFAULT_VOLUME);
    }

    function buy(OrderBookTest.Dapp memory self, uint8 price, uint256 volume)
        internal
        returns (OrderBookTest.Order memory)
    {
        uint256 orderId = self.orderBook.buy(price, volume);

        return OrderBookTest.Order({id: orderId, orderBook: self.orderBook, vm: self.vm});
    }

    function sell(OrderBookTest.Dapp memory self, uint8 price) internal returns (OrderBookTest.Order memory) {
        return self.sell(price, DEFAULT_VOLUME);
    }

    function sell(OrderBookTest.Dapp memory self, uint8 price, uint256 volume)
        internal
        returns (OrderBookTest.Order memory)
    {
        uint256 orderId = self.orderBook.sell(price, volume);

        return OrderBookTest.Order({id: orderId, orderBook: self.orderBook, vm: self.vm});
    }
}

library LevelTestExt {
    using LevelTestExt for OrderBookTest.Level;

    modifier onlyActive(OrderBookTest.Level memory self) {
        require(self.active(), "misuse: inactive level");
        _;
    }

    modifier withInvariantsChecking(OrderBookTest.Level memory self) {
        (bool _active,,, uint256 _headOrder, uint256 _tailOrder) = self.data();

        require((_headOrder != 0) == _active, "invariant: headOrder mismatch with activeness");
        require((_tailOrder != 0) == _active, "invariant: tailOrder mismatch with activeness");

        _;
    }

    // --- Level getters --- //

    function active(OrderBookTest.Level memory self) internal view returns (bool) {
        (bool _active,,,,) = self.data();
        return _active;
    }

    function prevLevel(OrderBookTest.Level memory self) internal view returns (uint8) {
        (, uint8 _prevLevel,,,) = self.data();
        return _prevLevel;
    }

    function nextLevel(OrderBookTest.Level memory self) internal view returns (uint8) {
        (,, uint8 _nextLevel,,) = self.data();
        return _nextLevel;
    }

    function headOrder(OrderBookTest.Level memory self) internal view returns (uint256) {
        (,,, uint256 _headOrder,) = self.data();
        return _headOrder;
    }

    function tailOrder(OrderBookTest.Level memory self) internal view returns (uint256) {
        (,,,, uint256 _tailOrder) = self.data();
        return _tailOrder;
    }

    function data(OrderBookTest.Level memory self) internal view returns (bool, uint8, uint8, uint256, uint256) {
        if (self.isBuy) return self.orderBook.buyLevels(self.price);

        return self.orderBook.sellLevels(self.price);
    }
}

library OrderTestExt {
    using OrderTestExt for OrderBookTest.Order;

    function next(OrderBookTest.Order memory self, uint256 n)
        internal
        view
        onlyActive(self)
        returns (OrderBookTest.Order memory)
    {
        while (!self.isTail() && n > 0) {
            self = self.next();
            n--;
        }

        return self;
    }

    function next(OrderBookTest.Order memory self) internal view onlyActive(self) returns (OrderBookTest.Order memory) {
        uint256 nextOrderId = self.nextOrder();

        return OrderBookTest.Order({id: nextOrderId, orderBook: self.orderBook, vm: self.vm});
    }

    function prev(OrderBookTest.Order memory self, uint256 n)
        internal
        view
        onlyActive(self)
        returns (OrderBookTest.Order memory)
    {
        while (!self.isHead() && n > 0) {
            self = self.prev();
            n--;
        }

        return self;
    }

    function prev(OrderBookTest.Order memory self) internal view onlyActive(self) returns (OrderBookTest.Order memory) {
        uint256 prevOrderId = self.prevOrder();

        return OrderBookTest.Order({id: prevOrderId, orderBook: self.orderBook, vm: self.vm});
    }

    function level(OrderBookTest.Order memory self) internal view returns (OrderBookTest.Level memory) {
        (, uint8 _price, bool _isBuy,,,,) = self.data();
        return OrderBookTest.Level({price: _price, isBuy: _isBuy, orderBook: self.orderBook, vm: self.vm});
    }

    function isHead(OrderBookTest.Order memory self) internal view returns (bool) {
        (bool _active,,,,, uint256 _prevOrder,) = self.data();
        return _active && _prevOrder == 0;
    }

    function isTail(OrderBookTest.Order memory self) internal view returns (bool) {
        (bool _active,,,,,, uint256 _nextOrder) = self.data();
        return _active && _nextOrder == 0;
    }

    modifier onlyActive(OrderBookTest.Order memory self) {
        require(self.active(), "misuse: inactive order");
        _;
    }

    modifier withInvariantsChecking(OrderBookTest.Order memory self) {
        (bool _active,,,, uint256 _volume, uint256 _prevOrder, uint256 _nextOrder) = self.data();

        if (!_active) {
            require(_prevOrder == 0, "invariant: inactive order shouldn't have prevOrder");
            require(_nextOrder == 0, "invariant: inactive order shouldn't have nextOrder");
            require(_volume == 0, "invariant: inactive order shouldn't have volume");
        }

        _;
    }

    // --- Order getters --- //

    function active(OrderBookTest.Order memory self) internal view returns (bool) {
        (bool _active,,,,,,) = self.data();
        return _active;
    }

    function price(OrderBookTest.Order memory self) internal view returns (uint8) {
        (, uint8 _price,,,,,) = self.data();
        return _price;
    }

    function isBuy(OrderBookTest.Order memory self) internal view returns (bool) {
        (,, bool _isBuy,,,,) = self.data();
        return _isBuy;
    }

    function maker(OrderBookTest.Order memory self) internal view returns (address) {
        (,,, address _maker,,,) = self.data();
        return _maker;
    }

    function volume(OrderBookTest.Order memory self) internal view returns (uint256) {
        (,,,, uint256 _volume,,) = self.data();
        return _volume;
    }

    function prevOrder(OrderBookTest.Order memory self) internal view returns (uint256) {
        (,,,,, uint256 _prevOrder,) = self.data();
        return _prevOrder;
    }

    function nextOrder(OrderBookTest.Order memory self) internal view returns (uint256) {
        (,,,,,, uint256 _nextOrder) = self.data();
        return _nextOrder;
    }

    function data(OrderBookTest.Order memory self)
        internal
        view
        returns (bool, uint8, bool, address, uint256, uint256, uint256)
    {
        return self.orderBook.orders(self.id);
    }
}
