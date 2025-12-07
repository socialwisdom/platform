// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPlatform} from "../interfaces/IPlatform.sol";
import {Level} from "../libraries/Levels.sol";
import {Order} from "../libraries/Orders.sol";
import {OrderBook, OrderBookLib, OrderBookParams} from "../libraries/OrderBook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Platform is IPlatform, Ownable {
    using OrderBookLib for OrderBook;

    /// @dev Created markets mapped by their ID.
    mapping(uint256 => OrderBook) public markets;

    /// @dev The next market ID to be assigned.
    uint256 public nextMarketId = 1;

    /// @dev The default minimum volume for a market.
    uint256 public constant DEFAULT_MIN_VOLUME = 10;

    /// @dev Initializes the platform contract setting the deployer as the owner.
    constructor() Ownable(msg.sender) {}

    /// @return marketId. The ID of the created market.
    function createMarket() external onlyOwner returns (uint256) {
        uint256 marketId = nextMarketId++;

        markets[marketId].initialize(marketId, DEFAULT_MIN_VOLUME);

        return marketId;
    }

    /// @dev Closes the market with the given ID.
    function closeMarket(uint256 marketId) external onlyOwner {
        return markets[marketId].finish();
    }

    /// @return orderId. The ID of the created buy order. Zero if was filled immediately.
    function buy(uint256 market, uint8 price, uint256 volume) external returns (uint256) {
        return markets[market].buy(msg.sender, price, volume);
    }

    /// @return orderId. The ID of the created sell order. Zero if was filled immediately.
    function sell(uint256 market, uint8 price, uint256 volume) external returns (uint256) {
        return markets[market].sell(msg.sender, price, volume);
    }

    /// @return unfilledVolume. The non zero volume that was not filled.
    function cancel(uint256 market, uint256 orderId) external returns (uint256) {
        return markets[market].cancel(msg.sender, orderId);
    }

    /// @return bestPrice. The best price for the given market and side.
    function bestPrice(uint256 market, bool isBuy) external view returns (uint8) {
        OrderBook storage orderBook = markets[market];

        return (isBuy) ? orderBook.bestBuyPrice : orderBook.bestSellPrice;
    }

    /// @return level. The level for the given market, price, and side.
    function level(uint256 market, uint8 price, bool isBuy) external view returns (Level memory) {
        OrderBook storage orderBook = markets[market];

        return (isBuy) ? orderBook.buyLevels[price] : orderBook.sellLevels[price];
    }

    /// @return order. The order for the given market and order ID.
    function order(uint256 market, uint256 orderId) external view returns (Order memory) {
        return markets[market].orders[orderId];
    }

    /// @return params. The parameters for the given market.
    function params(uint256 market) external view returns (OrderBookParams memory) {
        return markets[market].params;
    }
}
