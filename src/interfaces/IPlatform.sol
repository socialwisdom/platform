// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice IPlatform defines the external API of the Social Wisdom protocol.
/// All events and function signatures for user-facing operations.
/// Events are primary for observation/indexing; views provide canonical state.
interface IPlatform {
    // ==================== User Registry Events ====================

    /// @notice Emitted once per address when a fresh userId is assigned (lazy registration allowed).
    event UserRegistered(address indexed user, uint64 userId);

    // ==================== Market Lifecycle Events ====================

    /// @notice Emitted once after market storage is written.
    event MarketCreated(
        uint64 indexed marketId,
        uint64 indexed creatorId,
        uint64 indexed resolverId,
        uint64 expirationAt,
        bool allowEarlyResolve,
        bytes32 questionHash,
        bytes32 outcomesHash,
        string question,
        string[] outcomeLabels,
        string resolutionRules
    );

    /// @notice Emitted when resolver selects (or updates) the pending outcome.
    event MarketResolved(uint64 indexed marketId, uint8 winningOutcomeId, uint64 resolvedAt);

    /// @notice Emitted once when resolver finalizes the outcome.
    event MarketFinalized(uint64 indexed marketId, uint64 finalizedAt);

    // ==================== Trading Events ====================

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

    // ==================== Balance and Custody Events ====================

    /// @notice Emitted after collateral transfer succeeds and Points are credited.
    event PointsDeposited(uint64 indexed userId, address indexed user, uint128 amount);

    /// @notice Emitted after Points debit and collateral transfer succeeds.
    event PointsWithdrawn(uint64 indexed userId, address indexed user, uint128 amount);

    /// @notice Emitted after ERC-1155 transfer into custody succeeds.
    event SharesDeposited(uint64 indexed userId, uint64 indexed marketId, uint8 indexed outcomeId, uint128 amount);

    /// @notice Emitted after balances debit and ERC-1155 transfer out succeeds.
    event SharesWithdrawn(uint64 indexed userId, uint64 indexed marketId, uint8 indexed outcomeId, uint128 amount);

    // ==================== Claim Events ====================

    /// @notice Emitted after successful claim settlement.
    event Claimed(
        uint64 indexed marketId,
        uint64 indexed userId,
        uint128 sharesRedeemed,
        uint128 grossPoints,
        uint128 winningFeePaid,
        uint128 netPoints
    );

    // ==================== Administrative Events ====================

    /// @notice Emitted after fee exemption state changes.
    event FeeExemptionUpdated(address indexed account, bool isExempt);

    // ==================== Balance Views ====================

    /// @notice Get the Points balance for a user.
    /// @param user The address of the user.
    /// @return free Available Points.
    /// @return reserved Locked Points.
    function getPointsBalance(address user) external view returns (uint128 free, uint128 reserved);

    /// @notice Get the Shares balance for a user in a specific market outcome.
    /// @param marketId The market ID.
    /// @param outcomeId The outcome ID.
    /// @param user The address of the user.
    /// @return free Available Shares.
    /// @return reserved Locked Shares.
    function getSharesBalance(uint64 marketId, uint8 outcomeId, address user)
        external
        view
        returns (uint128 free, uint128 reserved);

    // ==================== User Registry ====================

    /// @notice Get the userId for a given address, or 0 if not registered.
    function userIdOf(address user) external view returns (uint64);

    /// @notice Get the address for a given userId, or address(0) if not registered.
    function userOfId(uint64 id) external view returns (address);

    /// @notice Register the caller as a new user, or return their existing userId.
    /// @return id The userId assigned to msg.sender.
    function register() external returns (uint64 id);

    // ==================== Points Deposits & Withdrawals ====================

    /// @notice Deposit Points into the platform.
    /// @param amount Points to deposit.
    function deposit(uint128 amount) external;

    /// @notice Withdraw free Points from the platform.
    /// Only free (non-reserved) Points can be withdrawn.
    /// @param amount Points to withdraw.
    function withdraw(uint128 amount) external;

    // ==================== Shares Deposits & Withdrawals ====================

    /// @notice Deposit Shares into the platform.
    /// @param marketId The market these shares are for.
    /// @param outcomeId The outcome index for these shares.
    /// @param amount Shares to deposit.
    function depositShares(uint64 marketId, uint8 outcomeId, uint128 amount) external;

    /// @notice Withdraw free Shares from the platform.
    /// Only free (non-reserved) Shares can be withdrawn.
    /// @param marketId The market these shares are for.
    /// @param outcomeId The outcome index for these shares.
    /// @param amount Shares to withdraw.
    function withdrawShares(uint64 marketId, uint8 outcomeId, uint128 amount) external;

    // ==================== Trading APIs ====================

    /// @notice Place a limit order on the specified market outcome side.
    /// Always allocates a new orderId (even if fully filled immediately).
    /// @param marketId The market this order is for.
    /// @param outcomeId The outcome index for this order.
    /// @param side Whether this is a bid (buy outcome) or ask (sell outcome).
    /// @param limitTick The price level for this order [1..99].
    /// @param sharesRequested The number of shares requested.
    /// @return orderIdOr0 The orderId if the order rests, or 0 if fully filled immediately.
    /// @return filledShares Shares filled immediately by this limit order.
    /// @return pointsTraded Points exchanged in this order.
    function placeLimit(uint64 marketId, uint8 outcomeId, uint8 side, uint8 limitTick, uint128 sharesRequested)
        external
        returns (uint32 orderIdOr0, uint128 filledShares, uint256 pointsTraded);

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

    // ==================== Trading Views ====================

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
}
