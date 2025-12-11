// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ConditionalTokensLib} from "./ConditionalTokens.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {Level, LevelsLib} from "./Levels.sol";
import {Order, OrdersLib} from "./Orders.sol";

struct OrderBookOutcomes {
    IConditionalTokens conditionalTokens;
    IERC20 collateral;
    address oracle;
    // TODO: impl uint8 winnerFee;
    bytes32 conditionId;
}

struct OrderBookParams {
    bool active;
    uint256 id;
    uint256 minVolume;
}

struct OrderBook {
    OrderBookParams params;
    OrderBookOutcomes outcomes;

    uint8 bestBuyPrice;
    uint8 bestSellPrice;

    uint256 nextOrderId;

    mapping(uint8 => Level) buyLevels;
    mapping(uint8 => Level) sellLevels;

    mapping(uint256 => Order) orders;
}

library OrderBookLib {
    using OrderBookLib for OrderBook;

    using ConditionalTokensLib for IConditionalTokens;

    using LevelsLib for mapping(uint8 => Level);
    using OrdersLib for mapping(uint256 => Order);

    /// @dev Initializes the order book with the given ID and minimum volume.
    /// @dev Intended for test markets without outcomes.
    function initialize(OrderBook storage orderBook, uint256 id, uint256 minVolume) internal {
        orderBook.initializeWithOutcomes(id, minVolume, IConditionalTokens(address(0)), IERC20(address(0)), address(0));
    }

    /// @dev Initializes the order book with it's parameters and outcomes configuration.
    function initializeWithOutcomes(
        OrderBook storage orderBook,
        /* @dev order book params */
        uint256 id,
        uint256 minVolume,
        /* @dev outcomes params */
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        address oracle
    ) internal {
        if (orderBook.params.active) revert("already initialized");

        orderBook.params.active = true;
        orderBook.params.id = id;
        orderBook.params.minVolume = minVolume;

        orderBook.outcomes.conditionalTokens = conditionalTokens;
        orderBook.outcomes.collateral = collateral;
        orderBook.outcomes.oracle = oracle;

        if (address(conditionalTokens) != address(0)) {
            orderBook.outcomes.conditionId = conditionalTokens.createBinaryCondition(
                oracle,
                bytes32(id)
            );
        }

        orderBook.nextOrderId = 1;
    }

    /// @dev Finishes the order book, preventing new orders from being placed.
    /// @dev Intended for test markets without outcomes.
    function finish(OrderBook storage orderBook) internal whileActive(orderBook) {
        orderBook.params.active = false;
    }

    /// @dev Finishes the order book, preventing new orders from being placed and resolves outcome.
    function setOutcomes(OrderBook storage orderBook, bool yesWon) internal {
        if (orderBook.params.active) revert("market still active");

        if (address(orderBook.outcomes.conditionalTokens) == address(0)) revert("market has no outcomes");

        if (msg.sender != orderBook.outcomes.oracle) revert IPlatform.Unauthorized();

        orderBook.outcomes.conditionalTokens.resolveCondition(
            orderBook.outcomes.conditionId,
            yesWon
        );
    }

    /// @return orderId. The ID of the created buy order. It may be filled immediately.
    function buy(OrderBook storage orderBook, address maker, uint8 price, uint256 volume) internal whileActive(orderBook) returns (uint256) {
        return orderBook._placeOrder(maker, price, volume, true);
    }

    /// @return orderId. The ID of the created sell order. It may be filled immediately.
    function sell(OrderBook storage orderBook, address maker, uint8 price, uint256 volume) internal whileActive(orderBook) returns (uint256) {
        return orderBook._placeOrder(maker, price, volume, false);
    }

    /// @return unfilledVolume. The unfilled volume of the cancelled order.
    function cancel(OrderBook storage orderBook, address caller, uint256 orderId) internal returns (uint256) {
        Order storage order = orderBook.orders[orderId];

        if (!order.active) revert IPlatform.InactiveOrder();

        if (order.maker != caller) revert IPlatform.Unauthorized();

        bool isBuy = order.isBuy;

        uint256 unfilledVolume = orderBook._removeOrder(orderId, isBuy);

        emit IPlatform.OrderCancelled(
            orderBook.params.id,
            orderId,
            order.price,
            isBuy,
            unfilledVolume
        );

        return unfilledVolume;
    }

    modifier whileActive(OrderBook storage orderBook) {
        if (!orderBook.params.active) revert IPlatform.InactiveMarket();
        _;
    }

    function _placeOrder(OrderBook storage orderBook, address maker, uint8 price, uint256 volume, bool isBuy) internal returns (uint256) {
        if (price == 0 || price > 99) revert IPlatform.IncorrectPrice();

        if (volume < orderBook.params.minVolume) revert IPlatform.InsufficientVolume();

        uint256 unfilledVolume = volume;

        while (unfilledVolume != 0) {
            uint256 orderToFillImmediately = orderBook._nextForFilling(price, !isBuy);

            if (orderToFillImmediately == 0) break;

            unfilledVolume = orderBook._fill(orderToFillImmediately, unfilledVolume);
        }

        uint256 orderId;

        if (unfilledVolume != 0) {
            orderId = orderBook._createOrder(price, maker, unfilledVolume, isBuy);
        } else {
            orderId = orderBook.nextOrderId++;
        }

        emit IPlatform.OrderPlaced(
            orderBook.params.id,
            orderId,
            price,
            isBuy,
            volume,
            unfilledVolume
        );

        return orderId;
    }

    /// @return unfilledVolume. The unfilled volume after attempting to fill.
    function _fill(OrderBook storage orderBook, uint256 orderId, uint256 volume) internal returns (uint256) {
        (uint256 remainingVolume, uint256 unfilledVolume) = orderBook.orders.fill(orderId, volume);

        emit IPlatform.OrderFilled(
            orderBook.params.id,
            orderId,
            orderBook.orders[orderId].price,
            orderBook.orders[orderId].isBuy,
            volume - unfilledVolume,
            remainingVolume
        );

        if (remainingVolume == 0) {
            orderBook._removeOrder(orderId, orderBook.orders[orderId].isBuy);
        }

        return unfilledVolume;
    }

    /// @return orderId. The next candidate order for filling with the matching price.
    function _nextForFilling(OrderBook storage orderBook, uint8 price, bool isBuy) internal view returns (uint256) {
        if (isBuy) {
            return (price <= orderBook.bestBuyPrice) ? orderBook.buyLevels[orderBook.bestBuyPrice].headOrder : 0;
        } else {
            return (price >= orderBook.bestSellPrice) ? orderBook.sellLevels[orderBook.bestSellPrice].headOrder : 0;
        }
    }

    function _createOrder(OrderBook storage orderBook, uint8 price, address maker, uint256 volume, bool isBuy) internal returns (uint256) {
        uint256 orderId = orderBook.nextOrderId++;

        bool best = isBuy ? (price > orderBook.bestBuyPrice) : (price < orderBook.bestSellPrice || orderBook.bestSellPrice == 0);

        if (best) {
            orderBook._createBestOrder(orderId, price, maker, volume, isBuy);
        } else {
            orderBook._createOrderAt(orderId, price, maker, volume, isBuy);
        }

        return orderId;
    }

    function _createOrderAt(OrderBook storage orderBook, uint256 orderId, uint8 price, address maker, uint256 volume, bool isBuy) internal {
        if (isBuy) {
            if (orderBook.buyLevels[price].active) {
                orderBook.orders.createBuyTail(orderId, price, maker, volume, orderBook.buyLevels);
            } else {
                orderBook.buyLevels.createBuy(price, orderBook.bestBuyPrice, orderId);
                orderBook.orders.createBuyHead(orderId, price, maker, volume);
            }
        } else {
            if (orderBook.sellLevels[price].active) {
                orderBook.orders.createSellTail(orderId, price, maker, volume, orderBook.sellLevels);
            } else {
                orderBook.sellLevels.createSell(price, orderBook.bestSellPrice, orderId);
                orderBook.orders.createSellHead(orderId, price, maker, volume);
            }
        }
    }

    function _createBestOrder(OrderBook storage orderBook, uint256 orderId, uint8 price, address maker, uint256 volume, bool isBuy) internal {
        if (isBuy) {
            orderBook.buyLevels.createBest(price, orderBook.bestBuyPrice, orderId);
            orderBook.orders.createBuyHead(orderId, price, maker, volume);
            orderBook.bestBuyPrice = price;
        } else {
            orderBook.sellLevels.createBest(price, orderBook.bestSellPrice, orderId);
            orderBook.orders.createSellHead(orderId, price, maker, volume);
            orderBook.bestSellPrice = price;
        }
    }

    /// @return unfilledVolume. The unfilled volume of the removed order.
    function _removeOrder(OrderBook storage orderBook, uint256 orderId, bool isBuy) internal returns (uint256) {
        (bool bestChanged, uint8 newBestPrice, uint256 unfilledVolume) = orderBook.orders.remove(orderId, isBuy ? orderBook.buyLevels : orderBook.sellLevels);

        if (bestChanged) {
            if (isBuy) {
                orderBook.bestBuyPrice = newBestPrice;
            } else {
                orderBook.bestSellPrice = newBestPrice;
            }
        }

        return unfilledVolume;
    }
}
