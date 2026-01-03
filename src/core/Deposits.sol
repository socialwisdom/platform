// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BookKey, UserId} from "../types/IdTypes.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {Accounting} from "./Accounting.sol";

/// @notice Deposits and withdrawals module.
/// Manages custody of user funds (Points) and internal balance accounting.
/// Events are emitted by Platform (not here).
library Deposits {
    // ─────────────────────────────────────────────────────────────────────────
    // Points Deposit
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deposit Points into the platform.
    /// Called by Platform API. Converts external tokens to internal Points balance.
    ///
    /// INVARIANTS:
    /// - Must be called with proper authorization (signature or caller check).
    /// - User must be registered or auto-registered.
    /// - Actual token transfer handled by caller (Platform).
    /// - Adds amount to user's free Points balance.
    ///
    /// NOTE: Events are emitted by Platform, not here.
    /// TODO: integrate with actual collateral token (currently mocked)
    /// - transfer token from user to platform
    /// - mint equivalent Points internally
    /// - Platform emits PointsDeposited event
    ///
    /// @param s Storage reference.
    /// @param userId User ID (must be registered or caller will register).
    /// @param amount Points to deposit.
    function doDeposit(PlatformStorage storage s, UserId userId, uint128 amount) internal {
        // TODO: add actual IERC20 transfer

        // Credit user's free Points balance
        Accounting.addFreePoints(s, userId, amount);

        // NOTE: Platform.deposit() will emit PointsDeposited event
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Points Withdrawal
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Withdraw free Points from the platform.
    /// User can only withdraw free (non-reserved) Points.
    ///
    /// INVARIANTS:
    /// - User must have sufficient free Points.
    /// - Only free Points can be withdrawn (reserved are locked in orders).
    /// - Actual token transfer handled by caller (Platform).
    /// - Removes amount from user's free Points balance.
    ///
    /// NOTE: Events are emitted by Platform, not here.
    /// TODO: integrate with actual collateral token (currently mocked)
    /// - burn Points internally
    /// - transfer equivalent token to user
    /// - Platform emits PointsWithdrawn event
    ///
    /// @param s Storage reference.
    /// @param userId User ID.
    /// @param amount Points to withdraw.
    function doWithdraw(PlatformStorage storage s, UserId userId, uint128 amount) internal {
        // Check sufficient free balance
        Accounting.removeFreePoints(s, userId, amount);

        // TODO: add actual IERC20 transfer

        // NOTE: Platform.withdraw() will emit PointsWithdrawn event
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Shares Deposit
    // ─────────────────────────────────────────────────────────────────────────

    // TODO: doc me
    function doSharesDeposit(PlatformStorage storage s, UserId userId, BookKey bookKey, uint128 amount) internal {
        // TODO: add actual IERC1155 transfer

        // Credit user's free Shares balance
        Accounting.addFreeShares(s, userId, bookKey, amount);

        // NOTE: Platform.depositShares() will emit SharesDeposited event
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Shares Withdrawal
    // ─────────────────────────────────────────────────────────────────────────

    // TODO: doc me
    function doSharesWithdraw(PlatformStorage storage s, UserId userId, BookKey bookKey, uint128 amount) internal {
        // TODO: add actual IERC1155 transfer

        // Credit user's free Shares balance
        Accounting.addFreeShares(s, userId, bookKey, amount);

        // NOTE: Platform.withdrawShares() will emit SharesWithdrawn event
    }
}
