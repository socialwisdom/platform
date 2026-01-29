// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Internal ledger views, fee accrual, and settlement-related APIs.
interface IAccounting {
    // ==================== Events ====================

    /// @notice Emitted once per address when a fresh userId is assigned (lazy registration allowed).
    event UserRegistered(address indexed user, uint64 userId);

    /// @notice Emitted after successful claim settlement.
    event Claimed(
        uint64 indexed marketId,
        uint64 indexed userId,
        uint128 sharesRedeemed,
        uint128 grossPoints,
        uint128 winningFeePaid,
        uint128 netPoints
    );

    /// @notice Emitted after sweeping per-market trading fees.
    event MarketFeesSwept(uint64 indexed marketId, uint128 protocolFeesPoints, uint128 creatorFeesPoints);

    // ==================== Write API ====================

    /// @notice Register caller and assign a new userId if needed.
    /// @return id The assigned userId.
    function register() external returns (uint64 id);

    /// @notice Sweep per-market trading fees into protocol/global and creator balances.
    /// @return protocolFeesPoints Amount credited to protocol.
    /// @return creatorFeesPoints Amount credited to market creator.
    function sweepMarketFees(uint64 marketId) external returns (uint128 protocolFeesPoints, uint128 creatorFeesPoints);

    // ==================== Read API ====================

    /// @notice Resolve a userId for an address (0 if unregistered).
    function userIdOf(address user) external view returns (uint64);

    /// @notice Resolve an address for a userId (zero address if unregistered).
    function userOfId(uint64 id) external view returns (address);

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

    /// @notice Get accumulated trading fees for a market (Points), unclaimed and not yet split with creator.
    function getMarketTradingFeesPoints(uint64 marketId) external view returns (uint128);

    /// @notice Get accumulated protocol dust (Points).
    function getProtocolDustPoints() external view returns (uint128);

    /// @notice Get accumulated protocol fees (Points).
    function getProtocolFeesPoints() external view returns (uint128);
}
