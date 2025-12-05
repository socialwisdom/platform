// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Level, LevelsLib} from "./Levels.sol";

/// Invariants:
/// - if (!active) { prevOrder == 0 && nextOrder == 0 && volume == 0 }
///
/// Helpers:
/// - isHead == (active && prevOrder == 0)
/// - isTail == (active && nextOrder == 0)
struct Order {
    bool active;
    uint8 price;
    bool isBuy;
    address maker;
    uint256 volume;
    uint256 prevOrder;
    uint256 nextOrder;
}

library OrdersLib {
    using LevelsLib for mapping (uint8 => Level);

    function createBuyHead(mapping (uint256 => Order) storage orders, uint256 id, uint8 price, address maker, uint256 volume) internal {
        return createHead(orders, id, price, maker, volume, true);
    }

    function createSellHead(mapping (uint256 => Order) storage orders, uint256 id, uint8 price, address maker, uint256 volume) internal {
        return createHead(orders, id, price, maker, volume, false);
    }

    function createHead(mapping (uint256 => Order) storage orders, uint256 id, uint8 price, address maker, uint256 volume, bool isBuy) internal {
        Order storage order = orders[id];
        /* dev */ require(!order.active);

        order.active = true;
        order.price = price;
        order.maker = maker;
        order.volume = volume;

        if (isBuy) {
            order.isBuy = true;
        }
    }

    function createBuyTail(mapping (uint256 => Order) storage orders, uint256 id, uint8 price, address maker, uint256 volume, mapping (uint8 => Level) storage levels) internal {
        return createTail(orders, id, price, maker, volume, true, levels);
    }

    function createSellTail(mapping (uint256 => Order) storage orders, uint256 id, uint8 price, address maker, uint256 volume, mapping (uint8 => Level) storage levels) internal {
        return createTail(orders, id, price, maker, volume, false, levels);
    }

    function createTail(mapping (uint256 => Order) storage orders, uint256 id, uint8 price, address maker, uint256 volume, bool isBuy, mapping (uint8 => Level) storage levels) internal {
        Level storage level = levels[price];
        /* dev */ require(level.active);

        Order storage order = orders[id];
        /* dev */ require(!order.active);

        order.active = true;
        order.price = price;
        order.maker = maker;
        order.volume = volume;
        order.prevOrder = level.tailOrder;
        if (isBuy) {
            order.isBuy = true;
        }

        orders[level.tailOrder].nextOrder = id;
        /* dev */ require(orders[level.tailOrder].active);
        /* dev */ require(orders[level.tailOrder].isBuy == isBuy);

        level.tailOrder = id;
    }

    /// @return unfilled volume. If 0, order is completely filled and should be removed.
    function fill(mapping (uint256 => Order) storage orders, uint256 id, uint256 volume) internal returns (uint256) {
        Order storage order = orders[id];
        /* dev */ require(order.active);
        /* dev */ require(volume > 0);

        if (order.volume > volume) {
            order.volume -= volume;
            return 0;
        }

        uint256 unfilledVolume = volume - order.volume;
        order.volume = 0;

        return unfilledVolume;
    }

    /// @return (bestChanged, newBestPrice, unfilledVolume). If bestChanged is true, newBestPrice is the new best price level after removal should be set.
    function remove(mapping (uint256 => Order) storage orders, uint256 id, mapping (uint8 => Level) storage levels) internal returns (bool, uint8, uint256) {
        Order storage order = orders[id];
        /* dev */ require(order.active);
        /* dev */ require(levels[order.price].active);

        uint256 prevId = order.prevOrder;
        uint256 nextId = order.nextOrder;
        uint256 unfilledVolume = order.volume;

        order.active = false;
        order.prevOrder = 0;
        order.nextOrder = 0;
        order.volume = 0;

        if (prevId == 0 && nextId == 0) {
            // Only order at this price level.
            (bool bestChanged, uint8 newBestPrice) = levels.remove(order.price);
            return (bestChanged, newBestPrice, unfilledVolume);
        } else if (prevId != 0 && nextId != 0) {
            // Some middle order at the level.
            /* dev */ require(orders[prevId].active);
            orders[prevId].nextOrder = nextId;
            /* dev */ require(orders[nextId].active);
            orders[nextId].prevOrder = prevId;
        } else if (prevId == 0) {
            // Head order at the level.
            levels[order.price].headOrder = nextId;
            /* dev */ require(orders[nextId].active);
            orders[nextId].prevOrder = 0;
        } else {
            // Tail order at the level.
            levels[order.price].tailOrder = prevId;
            /* dev */ require(orders[prevId].active);
            orders[prevId].nextOrder = 0;
        }

        return (false, 0, unfilledVolume);
    }
}
