// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UserId, BookKey} from "../types/IdTypes.sol";
import {BookState, Level, Order} from "../types/Structs.sol";

/// @notice Canonical storage layout (orderbook-only phase).
/// Append-only: when adding new subsystems later, ONLY append new fields/sections.
///
/// CORE INTENT:
/// - This storage is intentionally minimal to benchmark the on-chain LOB gas cost.
/// - No Points/Shares/Markets here yet.
///
/// GLOBAL INVARIANTS (high-level):
/// - books[bookKey].nextOrderId is monotonically increasing per book (start at 1; 0 reserved as "null").
/// - books[bookKey].bidsMask/asksMask: bit i set <=> tick(i+1) level is non-empty (tick=1 -> bit0).
/// - levels[levelKey].totalShares == sum(orders.sharesRemaining) for all orders in that level.
/// - FIFO per tick via next-only linked list (orders[orderKey].nextOrderId).
///
/// KEY DERIVATIONS (defined in src/encoding/Keys.sol later):
/// - levelKey = (uint256(bookKey) << 8) | uint8(tick)
/// - orderKey = (uint256(bookKey) << 32) | uint32(orderId)
struct PlatformStorage {
    // — Per-book aggregate state —
    mapping(BookKey => BookState) books;

    // --- Per-(book,tick) level state ---
    mapping(uint256 => Level) levels;

    // --- Per-(book,orderId) order nodes ---
    mapping(uint256 => Order) orders;

    // --- User registry (orderbook phase) ---
    mapping(address => UserId) userIdOf; // UserId(0) = unregistered
    mapping(UserId => address) userOfId;
    UserId nextUserId; // starts at 1
    // (Append new storage below this line in future iterations.)
}
