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
    uint256 yesPositionId;
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
            require(address(collateral) != address(0), "collateral is zero address, while conditional tokens is set");

            orderBook.outcomes.conditionId = conditionalTokens.createBinaryCondition(
                address(this),
                bytes32(id)
            );

            orderBook.outcomes.yesPositionId = conditionalTokens.getPositionId(
                collateral,
                conditionalTokens.getCollectionId(
                    bytes32(0),
                    orderBook.outcomes.conditionId,
                    ConditionalTokensLib.YES
                )
            );
        } else {
            require(address(collateral) == address(0), "collateral is not zero address, while conditional tokens is not set");
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

    /// @return orderId. The ID of the created buy order for YES outcome. It may be filled immediately.
    function buy(OrderBook storage orderBook, address maker, uint8 price, uint256 volume) internal whileActive(orderBook) returns (uint256) {
        // TODO: refund unused collateral.
        orderBook._receiveCollateral(maker, volume * price);

        return orderBook._placeOrder(maker, price, volume, true);
    }

    /// @return orderId. The ID of the created sell order for YES outcome. It may be filled immediately.
    function sell(OrderBook storage orderBook, address maker, uint8 price, uint256 volume) internal whileActive(orderBook) returns (uint256) {
        orderBook._receiveYes(maker, volume);

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

        if (isBuy) {
            // Refund collateral
            orderBook._sendCollateral(order.maker, unfilledVolume * order.price);
        } else {
            // Refund YES outcome tokens
            orderBook._sendYes(order.maker, unfilledVolume);
        }

        return unfilledVolume;
    }

    modifier whileActive(OrderBook storage orderBook) {
        if (!orderBook.params.active) revert IPlatform.InactiveMarket();
        _;
    }

    function _receiveYes(OrderBook storage orderBook, address from, uint256 amount) internal {
        if (address(orderBook.outcomes.conditionalTokens) == address(0)) return;

        orderBook.outcomes.conditionalTokens.safeTransferFrom(
            from,
            address(this),
            orderBook.outcomes.yesPositionId,
            amount,
            ""
        );
    }

    function _sendYes(OrderBook storage orderBook, address to, uint256 amount) internal {
        if (address(orderBook.outcomes.conditionalTokens) == address(0)) return;

        orderBook.outcomes.conditionalTokens.safeTransferFrom(
            address(this),
            to,
            orderBook.outcomes.yesPositionId,
            amount,
            ""
        );
    }

    function _receiveCollateral(OrderBook storage orderBook, address from, uint256 amount) internal {
        if (address(orderBook.outcomes.collateral) == address(0)) return;

        require(orderBook.outcomes.collateral.transferFrom(from, address(this), amount), "collateral receive failed");
    }

    function _sendCollateral(OrderBook storage orderBook, address to, uint256 amount) internal {
        if (address(orderBook.outcomes.collateral) == address(0)) return;

        require(orderBook.outcomes.collateral.transfer(to, amount), "collateral send failed");
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

        uint256 volumeFilled = volume - unfilledVolume;

        if (isBuy) {
            // Send YES outcome tokens to buyer
            orderBook._sendYes(maker, volumeFilled);
        } else {
            // Send collateral to seller
            orderBook._sendCollateral(maker, volumeFilled * price);
        }

        return orderId;
    }

    /// @return unfilledVolume. The unfilled volume after attempting to fill.
    function _fill(OrderBook storage orderBook, uint256 orderId, uint256 volume) internal returns (uint256) {
        (uint256 remainingVolume, uint256 unfilledVolume) = orderBook.orders.fill(orderId, volume);

        uint256 volumeFilled = volume - unfilledVolume;
        bool isBuy = orderBook.orders[orderId].isBuy;
        uint8 price = orderBook.orders[orderId].price;

        emit IPlatform.OrderFilled(
            orderBook.params.id,
            orderId,
            price,
            isBuy,
            volumeFilled,
            remainingVolume
        );

        if (isBuy) {
            // Send YES outcome tokens to buyer
            orderBook._sendYes(orderBook.orders[orderId].maker, volumeFilled);
        } else {
            // Send collateral to seller
            orderBook._sendCollateral(orderBook.orders[orderId].maker, volumeFilled * price);
        }

        if (remainingVolume == 0) {
            orderBook._removeOrder(orderId, isBuy);
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
