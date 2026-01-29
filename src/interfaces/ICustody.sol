// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Asset custody APIs for deposits and withdrawals.
interface ICustody {
    // ==================== Events ====================

    /// @notice Emitted after collateral transfer succeeds and Points are credited.
    event PointsDeposited(uint64 indexed userId, address indexed user, uint128 amount);

    /// @notice Emitted after Points debit and collateral transfer succeeds.
    event PointsWithdrawn(uint64 indexed userId, address indexed user, uint128 amount);

    /// @notice Emitted after ERC-1155 transfer into custody succeeds.
    event SharesDeposited(uint64 indexed userId, uint64 indexed marketId, uint8 indexed outcomeId, uint128 amount);

    /// @notice Emitted after balances debit and ERC-1155 transfer out succeeds.
    event SharesWithdrawn(uint64 indexed userId, uint64 indexed marketId, uint8 indexed outcomeId, uint128 amount);

    // ==================== Write API ====================

    /// @notice Deposit Points into the platform.
    /// @param amount Points to deposit.
    function deposit(uint128 amount) external;

    /// @notice Withdraw free Points from the platform.
    /// Only free (non-reserved) Points can be withdrawn.
    /// @param amount Points to withdraw.
    function withdraw(uint128 amount) external;

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
}
