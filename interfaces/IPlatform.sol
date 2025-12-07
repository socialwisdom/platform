// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPlatform} from "../interfaces/IPlatform.sol";
import {Level} from "../libraries/Levels.sol";
import {Order} from "../libraries/Orders.sol";
import {OrderBook, OrderBookLib, OrderBookParams} from "../libraries/OrderBook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IPlatform {
    /// @dev An attempt to access to an inactive market.
    error InactiveMarket();

    /// @dev The requested price is not in [1, 99] range.
    error IncorrectPrice();

    /// @dev The requested volume is too low for the market.
    error InsufficientVolume();

    /// @dev The order is inactive (already filled, canceled, or never existed).
    error InactiveOrder();

    /// @dev The caller is not authorized to perform the action: e.g. cancel an order they do not make.
    error Unauthorized();

    /// @dev Emitted when a new market is created.
    event MarketCreated(uint256 marketId);

    /// @dev Emitted when a market is closed.
    event MarketClosed(uint256 marketId);

    /// @dev Emitted when a new order is placed.
    event OrderPlaced(
        uint256 indexed marketId,
        uint256 orderId,
        uint8 indexed price,
        bool indexed isBuy,
        uint256 volume,
        uint256 unfilledVolume
    );

    /// @dev Emitted when an order is cancelled.
    event OrderCancelled(
        uint256 indexed marketId,
        uint256 orderId,
        uint8 indexed price,
        bool indexed isBuy,
        uint256 unfilledVolume
    );

    /// @dev Emitted when an order is filled. If remainingVolume is zero, the order is fully filled and removed.
    event OrderFilled(
        uint256 indexed marketId,
        uint256 indexed orderId,
        uint8 indexed price,
        bool isBuy,
        uint256 volumeFilled,
        uint256 remainingVolume
    );

    /// @return marketId. The ID of the created market.
    function createMarket() external returns (uint256);

    /// @dev Closes the market with the given ID.
    function closeMarket(uint256 marketId) external;

    /// @return orderId. The ID of the created buy order. Zero if was filled immediately.
    function buy(uint256 market, uint8 price, uint256 volume) external returns (uint256);

    /// @return orderId. The ID of the created sell order. Zero if was filled immediately.
    function sell(uint256 market, uint8 price, uint256 volume) external returns (uint256);

    /// @return unfilledVolume. The non zero volume that was not filled.
    function cancel(uint256 market, uint256 orderId) external returns (uint256);

    /// @return bestPrice. The best price for the given market and side.
    function bestPrice(uint256 market, bool isBuy) external view returns (uint8);

    /// @return level. The level for the given market, price, and side.
    function level(uint256 market, uint8 price, bool isBuy) external view returns (Level memory);

    /// @return order. The order for the given market and order ID.
    function order(uint256 market, uint256 orderId) external view returns (Order memory);

    /// @return params. The parameters for the given market.
    function params(uint256 market) external view returns (OrderBookParams memory);
}
