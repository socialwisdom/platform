// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UserId, BookKey} from "../types/IdTypes.sol";
import {PointsBalance, SharesBalance} from "../types/Structs.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {
    InsufficientFreePoints,
    InsufficientFreeShares,
    InsufficientReservedPoints,
    InsufficientReservedShares
} from "../types/Errors.sol";

/// @notice Internal accounting module for Points and Shares balances.
/// Tracks free and reserved balances per user.
///
/// INVARIANTS (must always hold):
/// - free + reserved >= 0 (never negative)
/// - reserved balance represents locked obligations (open orders, pending fees, etc.)
/// - free balance is available for new trades or withdrawals
library Accounting {
    // ─────────────────────────────────────────────────────────────────────────
    // Points Balance Operations
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Get current Points balance (free + reserved).
    /// @param s Storage reference.
    /// @param userId User to query.
    /// @return free Available Points.
    /// @return reserved Locked Points.
    function getPointsBalance(PlatformStorage.Layout storage s, UserId userId)
        internal
        view
        returns (uint128 free, uint128 reserved)
    {
        PointsBalance storage balance = s.pointsBalances[userId];
        return (balance.free, balance.reserved);
    }

    /// @notice Get total Points (free + reserved).
    /// @param s Storage reference.
    /// @param userId User to query.
    /// @return Total Points balance.
    function getTotalPoints(PlatformStorage.Layout storage s, UserId userId) internal view returns (uint256) {
        PointsBalance storage balance = s.pointsBalances[userId];
        return uint256(balance.free) + uint256(balance.reserved);
    }

    /// @notice Add free Points to user (e.g., from deposit).
    /// @param s Storage reference.
    /// @param userId User to credit.
    /// @param amount Points to add.
    function addFreePoints(PlatformStorage.Layout storage s, UserId userId, uint128 amount) internal {
        PointsBalance storage balance = s.pointsBalances[userId];
        uint128 currentFree = balance.free;
        balance.free = currentFree + amount;
    }

    /// @notice Remove free Points from user (e.g., for withdrawal).
    /// Reverts if insufficient free balance.
    /// @param s Storage reference.
    /// @param userId User to debit.
    /// @param amount Points to remove.
    function removeFreePoints(PlatformStorage.Layout storage s, UserId userId, uint128 amount) internal {
        PointsBalance storage balance = s.pointsBalances[userId];
        if (balance.free < amount) {
            revert InsufficientFreePoints(balance.free, amount);
        }
        balance.free -= amount;
    }

    /// @notice Reserve Points (move from free to reserved).
    /// Used when placing an order to lock in funds.
    /// @param s Storage reference.
    /// @param userId User to reserve from.
    /// @param amount Points to reserve.
    function reservePoints(PlatformStorage.Layout storage s, UserId userId, uint128 amount) internal {
        PointsBalance storage balance = s.pointsBalances[userId];
        if (balance.free < amount) {
            revert InsufficientFreePoints(balance.free, amount);
        }
        balance.free -= amount;
        balance.reserved += amount;
    }

    /// @notice Release Points (move from reserved to free).
    /// Used when orders are cancelled or partially filled.
    /// @param s Storage reference.
    /// @param userId User to release to.
    /// @param amount Points to release.
    function releasePoints(PlatformStorage.Layout storage s, UserId userId, uint128 amount) internal {
        PointsBalance storage balance = s.pointsBalances[userId];
        if (balance.reserved < amount) {
            revert InsufficientReservedPoints(balance.reserved, amount);
        }
        balance.reserved -= amount;
        balance.free += amount;
    }

    /// @notice Consume reserved Points (remove from reserved without adding to free).
    /// Used for fee settlement and order execution.
    /// @param s Storage reference.
    /// @param userId User to consume from.
    /// @param amount Points to consume.
    function consumeReservedPoints(PlatformStorage.Layout storage s, UserId userId, uint128 amount) internal {
        PointsBalance storage balance = s.pointsBalances[userId];
        if (balance.reserved < amount) {
            revert InsufficientReservedPoints(balance.reserved, amount);
        }
        balance.reserved -= amount;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Shares Balance Operations
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Get current Shares balance for a user in a book.
    /// @param s Storage reference.
    /// @param userId User to query.
    /// @param bookKey Book identifier.
    /// @return free Available shares.
    /// @return reserved Locked shares.
    function getSharesBalance(PlatformStorage.Layout storage s, UserId userId, BookKey bookKey)
        internal
        view
        returns (uint128 free, uint128 reserved)
    {
        SharesBalance storage balance = s.sharesBalances[userId][bookKey];
        return (balance.free, balance.reserved);
    }

    /// @notice Get total Shares (free + reserved) for a user in a book.
    /// @param s Storage reference.
    /// @param userId User to query.
    /// @param bookKey Book identifier.
    /// @return Total shares balance.
    function getTotalShares(PlatformStorage.Layout storage s, UserId userId, BookKey bookKey)
        internal
        view
        returns (uint256)
    {
        SharesBalance storage balance = s.sharesBalances[userId][bookKey];
        return uint256(balance.free) + uint256(balance.reserved);
    }

    /// @notice Add free shares to user (e.g., from purchasing, settlement payout).
    /// @param s Storage reference.
    /// @param userId User to credit.
    /// @param bookKey Book identifier.
    /// @param amount Shares to add.
    function addFreeShares(PlatformStorage.Layout storage s, UserId userId, BookKey bookKey, uint128 amount) internal {
        SharesBalance storage balance = s.sharesBalances[userId][bookKey];
        balance.free += amount;
    }

    /// @notice Remove free shares from user (e.g., for settlement, burn, withdrawal).
    /// Reverts if insufficient free balance.
    /// @param s Storage reference.
    /// @param userId User to debit.
    /// @param bookKey Book identifier.
    /// @param amount Shares to remove.
    function removeFreeShares(PlatformStorage.Layout storage s, UserId userId, BookKey bookKey, uint128 amount)
        internal
    {
        SharesBalance storage balance = s.sharesBalances[userId][bookKey];
        if (balance.free < amount) {
            revert InsufficientFreeShares(balance.free, amount);
        }
        balance.free -= amount;
    }

    /// @notice Reserve shares (move from free to reserved).
    /// Used when placing a sell order to lock in shares.
    /// @param s Storage reference.
    /// @param userId User to reserve from.
    /// @param bookKey Book identifier.
    /// @param amount Shares to reserve.
    function reserveShares(PlatformStorage.Layout storage s, UserId userId, BookKey bookKey, uint128 amount) internal {
        SharesBalance storage balance = s.sharesBalances[userId][bookKey];
        if (balance.free < amount) {
            revert InsufficientFreeShares(balance.free, amount);
        }
        balance.free -= amount;
        balance.reserved += amount;
    }

    /// @notice Release shares (move from reserved to free).
    /// Used when orders are cancelled or partially filled.
    /// @param s Storage reference.
    /// @param userId User to release to.
    /// @param bookKey Book identifier.
    /// @param amount Shares to release.
    function releaseShares(PlatformStorage.Layout storage s, UserId userId, BookKey bookKey, uint128 amount) internal {
        SharesBalance storage balance = s.sharesBalances[userId][bookKey];
        if (balance.reserved < amount) {
            revert InsufficientReservedShares(balance.reserved, amount);
        }
        balance.reserved -= amount;
        balance.free += amount;
    }

    /// @notice Consume reserved shares (remove from reserved without adding to free).
    /// Used for order execution and settlement.
    /// @param s Storage reference.
    /// @param userId User to consume from.
    /// @param bookKey Book identifier.
    /// @param amount Shares to consume.
    function consumeReservedShares(PlatformStorage.Layout storage s, UserId userId, BookKey bookKey, uint128 amount)
        internal
    {
        SharesBalance storage balance = s.sharesBalances[userId][bookKey];
        if (balance.reserved < amount) {
            revert InsufficientReservedShares(balance.reserved, amount);
        }
        balance.reserved -= amount;
    }
}
