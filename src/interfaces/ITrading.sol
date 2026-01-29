// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Order book trading APIs and related views.
interface ITrading {
    // ==================== Events ====================

    /// @notice Emitted on every placeLimit after allocating orderId, before any Trade events.
    event OrderPlaced(
        uint64 indexed marketId,
        uint8 indexed outcomeId,
        uint64 indexed ownerId,
        uint8 side,
        uint32 orderId,
        uint8 tick,
        uint128 sharesRequested
    );

    /// @notice Emitted after successful cancellation and release of reservations.
    event OrderCancelled(
        uint64 indexed marketId,
        uint8 indexed outcomeId,
        uint64 indexed ownerId,
        uint8 side,
        uint32 orderId,
        uint8 tick,
        uint128 sharesCancelled
    );

    /// @notice Emitted once per maker fill step after balances update.
    /// takerOrderId = 0 for pure take. Non-zero for placeLimit-initiated trades.
    event Trade(
        uint64 indexed marketId,
        uint64 indexed makerId,
        uint64 indexed takerId,
        uint8 outcomeId,
        uint8 side,
        uint32 makerOrderId,
        uint32 takerOrderId,
        uint8 tick,
        uint128 sharesFilled,
        uint128 pointsExchanged,
        uint128 makerFeePaid,
        uint128 takerFeePaid
    );

    /// @notice Emitted once per take, after all Trade events of that call.
    event Take(
        uint64 indexed marketId,
        uint8 indexed outcomeId,
        uint64 indexed takerId,
        uint8 side,
        uint8 maxTick,
        uint128 sharesRequested,
        uint128 sharesFilled
    );

    // ==================== Write API ====================

    /// @notice Place a limit order on the specified market outcome side.
    /// Always allocates a new orderId (even if fully filled immediately).
    /// @param marketId The market this order is for.
    /// @param outcomeId The outcome index for this order.
    /// @param side Whether this is a bid (buy outcome) or ask (sell outcome).
    /// @param limitTick The price level for this order [1..99].
    /// @param sharesRequested The number of shares requested.
    /// @return orderId The allocated orderId (even if fully filled immediately).
    /// @return filledShares Shares filled immediately by this limit order.
    /// @return pointsTraded Points exchanged in this order.
    function placeLimit(uint64 marketId, uint8 outcomeId, uint8 side, uint8 limitTick, uint128 sharesRequested)
        external
        returns (uint32 orderId, uint128 filledShares, uint256 pointsTraded);

    /// @notice Execute a market order against existing liquidity; never rests and does not allocate orderId.
    /// @param marketId The market this trade is for.
    /// @param outcomeId The outcome index for this trade.
    /// @param side The direction: Bid to buy shares, Ask to sell shares.
    /// @param limitTick The maximum (Bid) or minimum (Ask) price to accept [1..99].
    /// @param sharesRequested The number of shares to trade.
    /// @param minFill Minimum shares that must be filled, or revert.
    /// @return filledShares Shares actually filled.
    /// @return pointsTraded Points exchanged.
    function take(
        uint64 marketId,
        uint8 outcomeId,
        uint8 side,
        uint8 limitTick,
        uint128 sharesRequested,
        uint128 minFill
    ) external returns (uint128 filledShares, uint256 pointsTraded);

    /// @notice Cancel an existing limit order (allowed in all market states).
    /// @param marketId The market the order is in.
    /// @param outcomeId The outcome index.
    /// @param side The order side.
    /// @param orderId The order to cancel.
    /// @param prevCandidates Previous order IDs to help locate the target (chain traversal optimization, max 16).
    /// @return cancelledShares Shares that were cancelled.
    function cancel(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId, uint32[] calldata prevCandidates)
        external
        returns (uint128 cancelledShares);

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
