// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {PriceBook} from "../src/PriceBook.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract PriceBookTest is Test {
    using LevelExt for Level;
    using OrderExt for Order;
    using PlatformExt for Platform;

    Platform public platform;

    struct Platform {
        PriceBook inner;
        Vm vm;
    }

    struct Level {
        uint8 price;
        PriceBook.PriceLevel data;
        Platform platform;
    }

    struct Order {
        uint256 id;
        Level level;
        PriceBook.Order data;
        Platform platform;
        uint256 unfilledVolume;
    }

    function setUp() public {
        vm.startPrank(address(0x42));

        platform = Platform({inner: new PriceBook(), vm: vm});

        assert(!platform.bestBuyOrder().exists());
        assert(!platform.bestSellOrder().exists());
    }

    function test_buyLevelsCreation() public {
        // Levels: [25].
        platform.buyAt(25);
        assertLevels(25, true);

        // Levels: [30, 25].
        platform.buyAt(30);
        assertLevels(30, 25);

        // Levels: [30, 25, 20].
        platform.buyAt(20);
        assertLevels(30, 25, 20);

        // Levels: [30, 29, 25, 20].
        platform.buyAt(29);
        assertLevels(30, 29, 25, 20);

        // Levels: [30, 29, 25, 21, 20].
        platform.buyAt(21);
        assertLevels(30, 29, 25, 21, 20);
    }

    function test_buyLevelsCreationUniqueness() public {
        // Levels: [25].
        platform.buyAt(25);
        platform.buyAt(25);
        assertLevels(25, true);

        // Levels: [30, 25].
        platform.buyAt(30);
        platform.buyAt(30);
        assertLevels(30, 25);

        // Levels: [30, 25, 20].
        platform.buyAt(20);
        platform.buyAt(20);
        assertLevels(30, 25, 20);

        // Levels: [30, 25, 20].
        platform.buyAt(25);
        assertLevels(30, 25, 20);
    }

    function test_buyLevelsRemoval() public {
        // Levels: [50].
        Order memory order50 = platform.buyAt(50);

        // Levels: [].
        order50 = order50.cancel();
        assertLevels(new uint8[](0));

        assert(!order50.exists());
        assert(order50.cancelled());
        assertEq(order50.unfilledVolume, PlatformExt.DEFAULT_VOLUME);

        // Levels: [50].
        order50 = platform.buyAt(50);
        assertLevels(50, true);

        // Levels: [60, 50, 40, 30, 20].
        Order memory order60 = platform.buyAt(60);
        Order memory order40 = platform.buyAt(40);
        platform.buyAt(30);
        Order memory order20 = platform.buyAt(20);
        assertLevels(60, 50, 40, 30, 20);

        // Levels: [50, 40, 30, 20].
        order60 = order60.cancel();
        assertLevels(50, 40, 30, 20);

        // Levels: [50, 40, 30].
        order20 = order20.cancel();
        assertLevels(50, 40, 30);

        // Levels: [50, 30].
        order40 = order40.cancel();
        assertLevels(50, 30);
    }

    function test_buyLevelsRemovalReasonableness() public {
        // Levels: [50].
        Order memory order50 = platform.buyAt(50);
        Order memory secondOrder50 = platform.buyAt(50);

        // Levels: [50].
        secondOrder50.cancel();
        assertLevels(50, true);

        // Levels: [60, 50, 40].
        Order memory order60 = platform.buyAt(60);
        Order memory order40 = platform.buyAt(40);

        platform.buyAt(60).cancel();
        assertLevels(60, 50, 40);

        platform.buyAt(40).cancel();
        assertLevels(60, 50, 40);

        // Levels: [60, 40].
        order50.cancel();
        assertLevels(60, 40);

        // Levels: [60].
        order40.cancel();
        assertLevels(60, true);

        // Levels: [].
        order60.cancel();
        assertLevels(new uint8[](0));
    }

    function test_sellLevelsCreation() public {
        // Levels: [75].
        platform.sellAt(75);
        assertLevels(75, false);

        // Levels: [70, 75].
        platform.sellAt(70);
        assertLevels(70, 75);

        // Levels: [70, 75, 80].
        platform.sellAt(80);
        assertLevels(70, 75, 80);

        // Levels: [70, 71, 75, 80].
        platform.sellAt(71);
        assertLevels(70, 71, 75, 80);

        // Levels: [70, 71, 75, 79, 80].
        platform.sellAt(79);
        assertLevels(70, 71, 75, 79, 80);
    }

    function test_sellLevelsCreationUniqueness() public {
        // Levels: [75].
        platform.sellAt(75);
        platform.sellAt(75);
        assertLevels(75, false);

        // Levels: [70, 75].
        platform.sellAt(70);
        platform.sellAt(70);
        assertLevels(70, 75);

        // Levels: [70, 75, 80].
        platform.sellAt(80);
        platform.sellAt(80);
        assertLevels(70, 75, 80);

        // Levels: [70, 75, 80].
        platform.sellAt(75);
        assertLevels(70, 75, 80);
    }

    function test_sellLevelsRemoval() public {
        // Levels: [71].
        Order memory order71 = platform.sellAt(71);

        // Levels: [].
        order71 = order71.cancel();
        assertLevels(new uint8[](0));

        assert(!order71.exists());
        assert(order71.cancelled());
        assertEq(order71.unfilledVolume, PlatformExt.DEFAULT_VOLUME);

        // Levels: [71].
        order71 = platform.sellAt(71);
        assertLevels(71, false);

        // Levels: [70, 71, 75, 79, 80].
        Order memory order70 = platform.sellAt(70);
        Order memory order75 = platform.sellAt(75);
        platform.sellAt(79);
        Order memory order80 = platform.sellAt(80);
        assertLevels(70, 71, 75, 79, 80);

        // Levels: [71, 75, 79, 80].
        order70 = order70.cancel();
        assertLevels(71, 75, 79, 80);

        // Levels: [71, 75, 79].
        order80 = order80.cancel();
        assertLevels(71, 75, 79);

        // Levels: [71, 79].
        order75 = order75.cancel();
        assertLevels(71, 79);
    }

    function test_sellLevelsRemovalReasonableness() public {
        // Levels: [75].
        Order memory order75 = platform.sellAt(75);
        Order memory secondOrder75 = platform.sellAt(75);

        // Levels: [75].
        secondOrder75.cancel();
        assertLevels(75, false);

        // Levels: [70, 75, 80].
        Order memory order70 = platform.sellAt(70);
        Order memory order80 = platform.sellAt(80);

        platform.sellAt(80).cancel();
        assertLevels(70, 75, 80);

        platform.sellAt(70).cancel();
        assertLevels(70, 75, 80);

        // Levels: [70, 80].
        order75.cancel();
        assertLevels(70, 80);

        // Levels: [80].
        order70.cancel();
        assertLevels(80, false);

        // Levels: [].
        order80.cancel();
        assertLevels(new uint8[](0));
    }

    function assertLevels(uint8[] memory prices) internal view {
        assertAllLevels(prices);

        if (prices.length == 0) {
            console.log("Asserting best buy price is zero");
            assertEq(platform.inner.bestBuyPrice(), 0);

            console.log("Asserting best sell price is zero");
            assertEq(platform.inner.bestSellPrice(), 0);

            return;
        }

        bool isAscending = true;
        bool isDescending = true;

        for (uint256 i = 1; i < prices.length; i++) {
            if (prices[i - 1] < prices[i]) {
                isDescending = false;
            } else if (prices[i - 1] > prices[i]) {
                isAscending = false;
            } else {
                revert("assertLevels: prices must be strictly increasing or decreasing");
            }
        }

        require(
            isAscending || isDescending, "assertLevels: prices must be sorted in either ascending or descending order"
        );

        Level memory level = platform.level(prices[0]);

        if (isDescending) {
            console.log("Asserting best buy price: ", prices[0]);
            assertEq(platform.inner.bestBuyPrice(), prices[0]);
            assert(level.data.ty == PriceBook.OrderType.BUY);
        } else {
            console.log("Asserting best sell price: ", prices[0]);
            assertEq(platform.inner.bestSellPrice(), prices[0]);
            assert(level.data.ty == PriceBook.OrderType.SELL);
        }

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

    function assertAllLevels(uint8[] memory existing) public view {
        bool[] memory slots = new bool[](100);

        for (uint256 i = 0; i < existing.length; i++) {
            slots[existing[i]] = true;
        }

        for (uint8 price = 0; price < 100; price++) {
            Level memory level = platform.level(price);

            require(level.exists() == slots[price], "Level existence does not match expected");
        }
    }

    function assertLevels(uint8 i0, bool isBuy) public view {
        Level memory level = platform.level(i0);

        assertEq(level.price, i0);

        if (isBuy) {
            console.log("Asserting best buy price: ", i0);
            assertEq(platform.inner.bestBuyPrice(), i0);
            assert(level.data.ty == PriceBook.OrderType.BUY);
        } else {
            console.log("Asserting best sell price: ", i0);
            assertEq(platform.inner.bestSellPrice(), i0);
            assert(level.data.ty == PriceBook.OrderType.SELL);
        }

        console.log("<< checked prev doesn't exist before :", level.price);
        assert(!level.prev().exists());

        console.log(">> checked next doesn't exist after :", level.price);
        assert(!level.next().exists());
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
    using PlatformExt for PriceBookTest.Platform;

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

    function next(PriceBookTest.Level memory self, uint256 n)
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

    function prev(PriceBookTest.Level memory self, uint256 n)
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
        PriceBookTest.Level memory higherLevel = self.platform.level(self.data.higherLevel);

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
        PriceBookTest.Level memory lowerLevel = self.platform.level(self.data.lowerLevel);

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
    using PlatformExt for PriceBookTest.Platform;
    using LevelExt for PriceBookTest.Level;

    function refetch(PriceBookTest.Order memory self)
        internal
        view
        onlyExisting(self)
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Order memory _order = self.platform.order(self.id);

        _order.id = self.id;
        _order.data.maker = self.data.maker;
        _order.data.price = self.level.price;
        _order.level = self.platform.level(self.level.price);

        return _order;
    }

    function exists(PriceBookTest.Order memory self) internal view returns (bool) {
        bool _exists = !cancelled(self) && self.data.maker != address(0);

        if (_exists) {
            require(self.id != 0, "OrderExt: existing order's id must not be 0");
            require(self.data.volume > 0, "OrderExt: existing order's volume must be > 0");
            require(self.level.exists(), "OrderExt: existing order's level must exist");
        } else if (cancelled(self)) {
            PriceBookTest.Order memory _order = self.platform.order(self.id);
            require(_order.data.maker == address(0), "OrderExt: cancelled order must not exist in PriceBook");
        }

        return _exists;
    }

    function cancelled(PriceBookTest.Order memory self) internal pure returns (bool) {
        return self.unfilledVolume != 0;
    }

    function cancel(PriceBookTest.Order memory self) internal onlyExisting(self) returns (PriceBookTest.Order memory) {
        return PlatformExt.cancelOrder(self.platform, self.id);
    }

    function isBuy(PriceBookTest.Order memory self) internal view onlyExisting(self) returns (bool) {
        return self.level.isBuy();
    }

    function next(PriceBookTest.Order memory self, uint256 n)
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
        PriceBookTest.Order memory nextOrder = self.platform.order(self.data.nextOrder);

        require(nextOrder.data.prevOrder == self.id, "OrderExt: next order's prevOrder mismatch");

        return nextOrder;
    }

    function prev(PriceBookTest.Order memory self, uint256 n)
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
        PriceBookTest.Order memory prevOrder = self.platform.order(self.data.prevOrder);

        require(prevOrder.data.nextOrder == self.id, "OrderExt: prev order's nextOrder mismatch");

        return prevOrder;
    }

    function isHead(PriceBookTest.Order memory self) internal view onlyExisting(self) returns (bool) {
        return self.data.prevOrder == 0;
    }

    function isTail(PriceBookTest.Order memory self) internal view onlyExisting(self) returns (bool) {
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

library PlatformExt {
    using LevelExt for PriceBookTest.Level;
    using OrderExt for PriceBookTest.Order;

    uint256 constant DEFAULT_VOLUME = 1_000;

    function cancelOrder(PriceBookTest.Platform memory platform, uint256 orderId)
        internal
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Order memory _order = order(platform, orderId);

        if (_order.level.data.totalVolume == _order.data.volume && _order.level.exists()) {
            if (_order.level.isBuy()) {
                console.log(" *** Cancelling order that will remove buy level at price: ", _order.level.price);
            } else {
                console.log(" *** Cancelling order that will remove sell level at price: ", _order.level.price);
            }

            platform.vm.expectEmit();
            emit PriceBook.PriceLevelRemoved(_order.level.price, _order.level.isBuy());
        }

        uint256 unfilledVolume = platform.inner.cancelOrder(orderId);

        _order = _order.refetch();
        _order.unfilledVolume = unfilledVolume;

        assert(_order.cancelled());
        assert(!_order.exists());

        return _order;
    }

    function buyAt(PriceBookTest.Platform memory platform, uint8 price) internal returns (PriceBookTest.Order memory) {
        return buyAt(platform, price, DEFAULT_VOLUME);
    }

    function buyAt(PriceBookTest.Platform memory platform, uint8 price, uint256 volume)
        internal
        returns (PriceBookTest.Order memory)
    {
        return createOrder(platform, price, volume, true);
    }

    function sellAt(PriceBookTest.Platform memory platform, uint8 price)
        internal
        returns (PriceBookTest.Order memory)
    {
        return sellAt(platform, price, DEFAULT_VOLUME);
    }

    function sellAt(PriceBookTest.Platform memory platform, uint8 price, uint256 volume)
        internal
        returns (PriceBookTest.Order memory)
    {
        return createOrder(platform, price, volume, false);
    }

    function createOrder(PriceBookTest.Platform memory platform, uint8 price, uint256 volume, bool isBuy)
        internal
        returns (PriceBookTest.Order memory)
    {
        PriceBookTest.Level memory _level = level(platform, price);

        if (!_level.exists()) {
            if (isBuy) {
                console.log(" *** Buy level will be created at price: ", price);
            } else {
                console.log(" *** Sell level will be created at price: ", price);
            }

            platform.vm.expectEmit();
            emit PriceBook.PriceLevelCreated(price, isBuy);
        }

        PriceBookTest.Order memory _order = order(platform, platform.inner.createOrder(price, isBuy, volume));

        require(_order.isTail(), "PlatformExt: created order is not tail");
        require(_order.data.price == price, "PlatformExt: created order's price mismatch");
        require(_order.level.price == price, "PlatformExt: created order's level price mismatch");
        require(_order.level.isBuy() == isBuy, "PlatformExt: created order's level type mismatch");
        require(
            _level.data.totalVolume + volume == _order.level.data.totalVolume, "PlatformExt: level totalVolume mismatch"
        );

        return _order;
    }

    function bestBuyLevel(PriceBookTest.Platform memory platform) internal view returns (PriceBookTest.Level memory) {
        PriceBookTest.Level memory bestBuy = level(platform, platform.inner.bestBuyPrice());

        if (LevelExt.exists(bestBuy)) {
            require(LevelExt.isBuy(bestBuy), "PlatformExt: best buy level is not a buy level");
            require(bestBuy.data.higherLevel == 0, "PlatformExt: best buy level's higherLevel is not 0");
        }

        return bestBuy;
    }

    function bestSellLevel(PriceBookTest.Platform memory platform) internal view returns (PriceBookTest.Level memory) {
        PriceBookTest.Level memory bestSell = level(platform, platform.inner.bestSellPrice());

        if (bestSell.exists()) {
            require(!bestSell.isBuy(), "PlatformExt: best sell level is a buy level");
            require(bestSell.data.lowerLevel == 0, "PlatformExt: best sell level's lowerLevel is not 0");
        }

        return bestSell;
    }

    function level(PriceBookTest.Platform memory platform, uint8 price)
        internal
        view
        returns (PriceBookTest.Level memory)
    {
        require(price < 100, "price must be < 100");

        (
            uint8 _higherLevel,
            uint8 _lowerLevel,
            PriceBook.OrderType _ty,
            uint256 _totalVolume,
            uint256 _headOrder,
            uint256 _tailOrder
        ) = platform.inner.priceLevels(price);

        return PriceBookTest.Level(
            price, PriceBook.PriceLevel(_higherLevel, _lowerLevel, _ty, _totalVolume, _headOrder, _tailOrder), platform
        );
    }

    function bestBuyOrder(PriceBookTest.Platform memory platform) internal view returns (PriceBookTest.Order memory) {
        PriceBookTest.Order memory _bestBuyOrder = order(platform, bestBuyLevel(platform).data.headOrder);

        if (platform.inner.bestBuyPrice() != 0) {
            require(_bestBuyOrder.exists(), "PlatformExt: best buy order does not exist");
            require(_bestBuyOrder.isHead(), "PlatformExt: best buy order is not head of best buy level's order list");
            require(!_bestBuyOrder.level.higher().exists(), "PlatformExt: best buy level has a higher level");
        }

        return _bestBuyOrder;
    }

    function bestSellOrder(PriceBookTest.Platform memory platform) internal view returns (PriceBookTest.Order memory) {
        PriceBookTest.Order memory _bestSellOrder = order(platform, bestSellLevel(platform).data.headOrder);

        if (platform.inner.bestSellPrice() != 0) {
            require(_bestSellOrder.exists(), "PlatformExt: best sell order does not exist");
            require(_bestSellOrder.isHead(), "PlatformExt: best sell order is not head of best sell level's order list");
            require(!_bestSellOrder.level.lower().exists(), "PlatformExt: best sell level has a lower level");
        }

        return _bestSellOrder;
    }

    function order(PriceBookTest.Platform memory platform, uint256 orderId)
        internal
        view
        returns (PriceBookTest.Order memory)
    {
        (address _maker, uint8 _price, uint256 _volume, uint256 _prevOrder, uint256 _nextOrder) =
            platform.inner.orders(orderId);

        PriceBookTest.Order memory _order = PriceBookTest.Order({
            id: orderId,
            level: level(platform, _price),
            data: PriceBook.Order(_maker, _price, _volume, _prevOrder, _nextOrder),
            platform: platform,
            unfilledVolume: 0
        });

        return _order;
    }
}
