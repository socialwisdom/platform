// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Level, LevelsLib} from "../libraries/Levels.sol";
import {Order, OrdersLib} from "../libraries/Orders.sol";

contract OrderBook {
    using LevelsLib for mapping(uint8 => Level);
    using OrdersLib for mapping(uint256 => Order);

    error InactiveOrder();

    error InsufficientVolume();

    error InvalidPrice();

    error Unauthorized();

    event OrderCreated(uint256 orderId, uint8 indexed price, bool indexed isBuy, uint256 volume);

    event OrderCancelled(uint256 orderId, uint8 indexed price, bool indexed isBuy, uint256 unfilledVolume);

    event OrderFilled(
        uint256 indexed orderId, uint8 indexed price, bool indexed isBuy, uint256 volumeFilled, uint256 remainingVolume
    );

    uint256 public constant MIN_VOLUME = 10;

    mapping(uint8 => Level) public buyLevels;
    mapping(uint8 => Level) public sellLevels;
    uint8 public bestBuyPrice;
    uint8 public bestSellPrice;

    mapping(uint256 => Order) public orders;
    uint256 public nextOrderId = 1;

    /// @return orderId. The ID of the created buy order. Zero if was filled immediately.
    function buy(uint8 price, uint256 volume) external returns (uint256) {
        if (price == 0 || price > 99) revert InvalidPrice();

        if (volume < MIN_VOLUME) revert InsufficientVolume();

        uint256 orderId = nextOrderId++;

        // Immediately match with existing sell orders.
        // TODO: optimize by entire level matching
        while (price >= bestSellPrice && bestSellPrice != 0) {
            uint256 orderToFill = sellLevels[bestSellPrice].headOrder;

            (uint256 remainingVolume, uint256 unfilledVolume) = orders.fill(orderToFill, volume);

            emit OrderFilled(orderToFill, bestSellPrice, false, volume - unfilledVolume, remainingVolume);

            if (remainingVolume == 0) _removeOrder(orderToFill, false);

            if (unfilledVolume == 0) {
                return 0;
            } else {
                volume = unfilledVolume;
            }
        }

        if (price > bestBuyPrice) {
            buyLevels.createBest(price, bestBuyPrice, orderId);
            bestBuyPrice = price;

            orders.createBuyHead(orderId, price, msg.sender, volume);
        } else if (buyLevels[price].active) {
            orders.createBuyTail(orderId, price, msg.sender, volume, buyLevels);
        } else {
            buyLevels.createBuy(price, bestBuyPrice, orderId);

            orders.createBuyTail(orderId, price, msg.sender, volume, buyLevels);
        }

        emit OrderCreated(orderId, price, true, volume);

        return orderId;
    }

    /// @return orderId. The ID of the created sell order. Zero if was filled immediately.
    function sell(uint8 price, uint256 volume) external returns (uint256) {
        if (price == 0 || price > 99) revert InvalidPrice();

        if (volume < MIN_VOLUME) revert InsufficientVolume();

        // Immediately match with existing buy orders.
        // TODO: optimize by entire level matching
        while (price <= bestBuyPrice) {
            uint256 orderToFill = buyLevels[bestBuyPrice].headOrder;

            (uint256 remainingVolume, uint256 unfilledVolume) = orders.fill(orderToFill, volume);

            emit OrderFilled(orderToFill, bestBuyPrice, true, volume - unfilledVolume, remainingVolume);

            if (remainingVolume == 0) _removeOrder(orderToFill, true);

            if (unfilledVolume == 0) {
                return 0;
            } else {
                volume = unfilledVolume;
            }
        }

        uint256 orderId = nextOrderId++;

        if (price < bestSellPrice || bestSellPrice == 0) {
            sellLevels.createBest(price, bestSellPrice, orderId);
            bestSellPrice = price;

            orders.createSellHead(orderId, price, msg.sender, volume);
        } else if (sellLevels[price].active) {
            orders.createSellTail(orderId, price, msg.sender, volume, sellLevels);
        } else {
            sellLevels.createSell(price, bestSellPrice, orderId);

            orders.createSellTail(orderId, price, msg.sender, volume, sellLevels);
        }

        emit OrderCreated(orderId, price, false, volume);

        return orderId;
    }

    /// @return unfilledVolume. The non zero volume that was not filled.
    function cancel(uint256 orderId) external returns (uint256) {
        if (!orders[orderId].active) revert InactiveOrder();

        if (orders[orderId].maker != msg.sender) revert Unauthorized();

        uint8 price = orders[orderId].price;
        bool isBuy = orders[orderId].isBuy;

        uint256 unfilledVolume = _removeOrder(orderId, isBuy);

        emit OrderCancelled(orderId, price, isBuy, unfilledVolume);

        return unfilledVolume;
    }

    function _removeOrder(uint256 orderId, bool isBuy) internal returns (uint256) {
        if (isBuy) {
            (bool bestChanged, uint8 newBestPrice, uint256 _unfilledVolume) = orders.remove(orderId, buyLevels);

            if (bestChanged) bestBuyPrice = newBestPrice;

            return _unfilledVolume;
        } else {
            (bool bestChanged, uint8 newBestPrice, uint256 _unfilledVolume) = orders.remove(orderId, sellLevels);

            if (bestChanged) bestSellPrice = newBestPrice;

            return _unfilledVolume;
        }
    }
}
