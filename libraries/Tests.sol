// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPlatform} from "../interfaces/IPlatform.sol";
import {Level, LevelsLib} from "./Levels.sol";
import {Order, OrdersLib} from "./Orders.sol";
import {OrderBookParams} from "./OrderBook.sol";
import {Vm} from "forge-std/Vm.sol";

struct TestPlatform {
    IPlatform platform;
    Vm vm;
}

struct TestMarket {
    uint256 id;
    IPlatform platform;
    Vm vm;
}

struct TestLevel {
    uint256 marketId;
    uint8 price;
    bool isBuy;
    IPlatform platform;
    Vm vm;
}

struct TestOrder {
    uint256 marketId;
    uint256 id;
    IPlatform platform;
    Vm vm;
}

library TestsLib {
    using TestsLib for TestPlatform;
    using TestsLib for TestMarket;
    using TestsLib for TestLevel;
    using TestsLib for TestOrder;

    /* @dev Platform apis */
    function createMarket(TestPlatform storage self) internal returns (TestMarket memory) {
        return TestMarket({id: self.platform.createMarket(), platform: self.platform, vm: self.vm});
    }

    /* @dev: Market apis */

    uint256 public constant DEFAULT_VOLUME = 1_000;

    function close(TestMarket memory self) internal {
        self.platform.closeMarket(self.id);
    }

    function buy(TestMarket memory self, uint8 _price) internal returns (TestOrder memory) {
        return self.buy(_price, DEFAULT_VOLUME);
    }

    function buy(TestMarket memory self, uint8 _price, uint256 _volume) internal returns (TestOrder memory) {
        return self.order(self.platform.buy(self.id, _price, _volume));
    }

    function sell(TestMarket memory self, uint8 _price) internal returns (TestOrder memory) {
        return self.sell(_price, DEFAULT_VOLUME);
    }

    function sell(TestMarket memory self, uint8 _price, uint256 _volume) internal returns (TestOrder memory) {
        return self.order(self.platform.sell(self.id, _price, _volume));
    }

    function order(TestMarket memory self, uint256 orderId) internal pure returns (TestOrder memory) {
        return TestOrder({marketId: self.id, id: orderId, platform: self.platform, vm: self.vm});
    }

    function currentBestBuy(TestMarket memory self) internal view returns (TestOrder memory) {
        return self.currentBest(true);
    }

    function currentBestSell(TestMarket memory self) internal view returns (TestOrder memory) {
        return self.currentBest(false);
    }

    function currentBest(TestMarket memory self, bool _isBuy) internal view returns (TestOrder memory) {
        uint8 _bestPrice = self.bestPrice(_isBuy);

        TestLevel memory _level = TestLevel({
            marketId: self.id,
            price: _bestPrice,
            isBuy: _isBuy,
            platform: self.platform,
            vm: self.vm
        });

        return _level.headOrder();
    }

    function bestBuyPrice(TestMarket memory self) internal view returns (uint8) {
        return self.bestPrice(true);
    }

    function bestSellPrice(TestMarket memory self) internal view returns (uint8) {
        return self.bestPrice(false);
    }

    /* @dev: Market getters */

    function bestPrice(TestMarket memory self, bool _isBuy) internal view returns (uint8) {
        return self.platform.bestPrice(self.id, _isBuy);
    }

    function params(TestMarket memory self) internal view returns (OrderBookParams memory) {
        return self.platform.params(self.id);
    }

    /* @dev: Level apis */

    function headOrder(TestLevel memory self) internal view returns (TestOrder memory) {
        return TestOrder({marketId: self.marketId, id: self.headOrderId(), platform: self.platform, vm: self.vm});
    }

    function tailOrder(TestLevel memory self) internal view returns (TestOrder memory) {
        return TestOrder({marketId: self.marketId, id: self.tailOrderId(), platform: self.platform, vm: self.vm});
    }

    function next(TestLevel memory self, uint256 n)
        internal
        view
        returns (TestLevel memory)
    {
        while (n > 0) {
            self = self.next();
            n--;
        }

        return self;
    }

    function next(TestLevel memory self) internal view onlyActiveLevel(self) returns (TestLevel memory) {
        uint8 nextLevelPrice = self.nextLevel();

        return TestLevel({
            marketId: self.marketId,
            price: nextLevelPrice,
            isBuy: self.isBuy,
            platform: self.platform,
            vm: self.vm
        });
    }

    function prev(TestLevel memory self, uint256 n)
        internal
        view
        returns (TestLevel memory)
    {
        while (n > 0) {
            self = self.prev();
            n--;
        }

        return self;
    }

    function prev(TestLevel memory self) internal view onlyActiveLevel(self) returns (TestLevel memory) {
        uint8 prevLevelPrice = self.prevLevel();

        return TestLevel({
            marketId: self.marketId,
            price: prevLevelPrice,
            isBuy: self.isBuy,
            platform: self.platform,
            vm: self.vm
        });
    }

    modifier onlyActiveLevel(TestLevel memory self) {
        require(self.active(), "misuse: inactive level");
        _;
    }

    /* @dev: Level getters */

    function active(TestLevel memory self) internal view returns (bool) {
        return self.data().active;
    }

    function prevLevel(TestLevel memory self) internal view returns (uint8) {
        return self.data().prevLevel;
    }

    function nextLevel(TestLevel memory self) internal view returns (uint8) {
        return self.data().nextLevel;
    }

    function headOrderId(TestLevel memory self) internal view returns (uint256) {
        return self.data().headOrder;
    }

    function tailOrderId(TestLevel memory self) internal view returns (uint256) {
        return self.data().tailOrder;
    }

    function data(TestLevel memory self) internal view returns (Level memory) {
        return self.platform.level(self.marketId, self.price, self.isBuy);
    }

    /* @dev: Order apis */

    function cancel(TestOrder memory self) internal returns (uint256) {
        return self.platform.cancel(self.marketId, self.id);
    }

    function next(TestOrder memory self, uint256 n)
        internal
        view
        returns (TestOrder memory)
    {
        while (n > 0) {
            self = self.next();
            n--;
        }

        return self;
    }

    function next(TestOrder memory self) internal view onlyActiveOrder(self) returns (TestOrder memory) {
        uint256 nextOrderId = self.nextOrder();

        return TestOrder({marketId: self.marketId, id: nextOrderId, platform: self.platform, vm: self.vm});
    }

    function prev(TestOrder memory self, uint256 n)
        internal
        view
        returns (TestOrder memory)
    {
        while (n > 0) {
            self = self.prev();
            n--;
        }

        return self;
    }

    function prev(TestOrder memory self) internal view onlyActiveOrder(self) returns (TestOrder memory) {
        uint256 prevOrderId = self.prevOrder();

        return TestOrder({marketId: self.marketId, id: prevOrderId, platform: self.platform, vm: self.vm});
    }

    function level(TestOrder memory self) internal view returns (TestLevel memory) {
        Order memory _data = self.data();

        return TestLevel({
            marketId: self.marketId,
            price: _data.price,
            isBuy: _data.isBuy,
            platform: self.platform,
            vm: self.vm
        });
    }

    function isHead(TestOrder memory self) internal view returns (bool) {
        Order memory _data = self.data();

        return _data.prevOrder == 0 && _data.active;
    }

    function isTail(TestOrder memory self) internal view returns (bool) {
        Order memory _data = self.data();

        return _data.nextOrder == 0 && _data.active;
    }

    modifier onlyActiveOrder(TestOrder memory self) {
        require(self.active(), "misuse: inactive order");
        _;
    }

    /* @dev: Order getters */

    function active(TestOrder memory self) internal view returns (bool) {
        return self.data().active;
    }

    function price(TestOrder memory self) internal view returns (uint8) {
        return self.data().price;
    }

    function isBuy(TestOrder memory self) internal view returns (bool) {
        return self.data().isBuy;
    }

    function maker(TestOrder memory self) internal view returns (address) {
        return self.data().maker;
    }

    function volume(TestOrder memory self) internal view returns (uint256) {
        return self.data().volume;
    }

    function prevOrder(TestOrder memory self) internal view returns (uint256) {
        return self.data().prevOrder;
    }

    function nextOrder(TestOrder memory self) internal view returns (uint256) {
        return self.data().nextOrder;
    }

    function data(TestOrder memory self) internal view returns (Order memory) {
        return self.platform.order(self.marketId, self.id);
    }
}
