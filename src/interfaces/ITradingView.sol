// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Read-only order book trading views.
interface ITradingView {
    // ==================== Read API ====================

    /// @notice Get candidate previous orders for traversing to a target order.
    /// Used to optimize cancellation by providing traversal hints.
    /// @param marketId The market.
    /// @param outcomeId The outcome index.
    /// @param side The order side.
    /// @param targetOrderId The order we are trying to reach.
    /// @param maxN Maximum number of candidates to return (will be capped at 16).
    /// @return Ordered array of candidate previous order IDs.
    function getCancelCandidates(uint64 marketId, uint8 outcomeId, uint8 side, uint32 targetOrderId, uint256 maxN)
        external
        view
        returns (uint32[] memory);

    /// @notice Get the remaining and requested shares for a specific order.
    /// WARNING: Intended for testing/indexing only; intended for removal/guarding in production.
    /// @param marketId The market.
    /// @param outcomeId The outcome index.
    /// @param side The order side.
    /// @param orderId The order ID.
    /// @return remaining Shares remaining to be filled.
    /// @return requested Total shares originally requested.
    function getOrderRemainingAndRequested(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        external
        view
        returns (uint128 remaining, uint128 requested);

    /// @notice Get the active tick mask for a given book.
    /// Used for best-price selection and off-chain book reconstruction.
    /// @param marketId The market.
    /// @param outcomeId The outcome index.
    /// @param side The book side.
    /// @return mask A 128-bit mask where bit(tick-1)=1 iff the level is non-empty.
    function getBookMask(uint64 marketId, uint8 outcomeId, uint8 side) external view returns (uint128 mask);

    /// @notice Get level metadata for a (book, tick).
    /// @param marketId The market.
    /// @param outcomeId The outcome index.
    /// @param side The book side.
    /// @param tick The price level.
    /// @return headOrderId First order at this level (0 if empty).
    /// @return tailOrderId Last order at this level (0 if empty).
    /// @return totalShares Sum of sharesRemaining across all orders at this level.
    function getLevel(uint64 marketId, uint8 outcomeId, uint8 side, uint8 tick)
        external
        view
        returns (uint32 headOrderId, uint32 tailOrderId, uint128 totalShares);

    /// @notice Get the full book as ordered ticks and total shares at each level.
    /// @dev For asks: ticks are ascending (best ask first). For bids: ticks are descending (best bid first).
    /// @param marketId The market.
    /// @param outcomeId The outcome index.
    /// @param side The book side.
    /// @return ticks Ordered list of non-empty ticks.
    /// @return totalShares Total shares at each corresponding tick.
    function getBookLevels(uint64 marketId, uint8 outcomeId, uint8 side)
        external
        view
        returns (uint8[] memory ticks, uint128[] memory totalShares);

    /// @notice Get full books for all outcomes in a market.
    /// @dev For asks: ticks are ascending (best ask first). For bids: ticks are descending (best bid first).
    /// @param marketId The market.
    /// @return outcomesCount Number of outcomes in the market.
    /// @return bidTicks Per-outcome bid ticks (ordered).
    /// @return bidTotalShares Per-outcome bid total shares aligned with bidTicks.
    /// @return askTicks Per-outcome ask ticks (ordered).
    /// @return askTotalShares Per-outcome ask total shares aligned with askTicks.
    function getMarketBookLevels(uint64 marketId)
        external
        view
        returns (
            uint8 outcomesCount,
            uint8[][] memory bidTicks,
            uint128[][] memory bidTotalShares,
            uint8[][] memory askTicks,
            uint128[][] memory askTotalShares
        );

    /// @notice Get a full order node for traversal and indexing.
    /// @param marketId The market.
    /// @param outcomeId The outcome index.
    /// @param side The book side.
    /// @param orderId The orderId.
    /// @return ownerId Internal userId of the order owner.
    /// @return nextOrderId Next orderId in FIFO list (0 if tail).
    /// @return tick Stored tick of this order.
    /// @return sharesRemaining Remaining shares to fill.
    /// @return requestedShares Original requested shares.
    function getOrder(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        external
        view
        returns (uint64 ownerId, uint32 nextOrderId, uint8 tick, uint128 sharesRemaining, uint128 requestedShares);
}
