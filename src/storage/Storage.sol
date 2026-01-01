// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UserId, Tick, OrderId, BookKey} from "../types/Types.sol";

/// @notice Canonical storage layout (orderbook-only phase).
/// Append-only: when adding new subsystems later, ONLY append new fields/sections.
///
/// CORE INTENT:
/// - This storage is intentionally minimal to benchmark the on-chain LOB gas cost.
/// - No Points/Shares/Markets here yet.
///
/// GLOBAL INVARIANTS (high-level):
/// - books[bookKey].nextOrderId is monotonically increasing per book (start at 1; 0 reserved as “null”).
/// - books[bookKey].bidsMask/asksMask: bit i set <=> tick(i+1) level is non-empty (tick=1 -> bit0).
/// - levels[levelKey].totalShares == sum(orders.sharesRemaining) for all orders in that level.
/// - FIFO per tick via next-only linked list (orders[orderKey].nextOrderId).
///
/// KEY DERIVATIONS (defined in src/lib/Keys.sol later):
/// - levelKey = (uint256(bookKey) << 8) | uint8(tick)
/// - orderKey = (uint256(bookKey) << 32) | uint32(orderId)
struct AppStorage {
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

/// @notice Per-book aggregate state.
/// STORAGE PACKING (Solidity, by field order):
/// - SLOT 0:
///   - uint32  nextOrderId   (4 bytes)
///   - uint128 asksMask      (16 bytes)
///   - padding               (12 bytes)
/// - SLOT 1:
///   - uint128 bidsMask      (16 bytes)
///   - padding               (16 bytes)
///
/// Gas notes:
/// - nextOrderId increments on each new resting order (placeLimit remainder).
/// - masks are read constantly in matching (best bid/ask). Keeping bidsMask in SLOT 0
///   makes “create + update bids” often touch a single slot.
struct BookState {
    uint32 nextOrderId;
    uint128 asksMask;
    uint128 bidsMask;
}

/// @notice FIFO queue state for a given (book, tick).
/// STORAGE PACKING:
/// - SLOT 0:
///   - uint32  headOrderId   (4 bytes)
///   - uint32  tailOrderId   (4 bytes)
///   - uint128 totalShares   (16 bytes)
///   - padding               (8 bytes)
///
/// Hot-path:
/// - totalShares updated on every fill.
/// - head/tail updated when appending or removing a filled head.
struct Level {
    uint32 headOrderId; // 0 means empty
    uint32 tailOrderId; // 0 means empty
    uint128 totalShares; // sum of sharesRemaining across orders at this tick
}

/// @notice Order node stored per (book, orderId).
/// Linked list is next-only (FIFO). Cancel-in-middle is O(n) unless extended later.
///
/// GAS / HOT-PATH GOAL:
/// In matching loops we frequently need:
/// - sharesRemaining (updated every fill)
/// - nextOrderId     (to advance FIFO)
/// - ownerId         (often needed for accounting/events)
/// - tick            (mostly for clarity/events; rarely used in core logic)
///
/// STORAGE PACKING:
/// - SLOT 0 (HOT):
///   - uint128 sharesRemaining (16 bytes)
///   - uint64  ownerId         (8 bytes)  [UserId is uint64]
///   - uint32  nextOrderId      (4 bytes)  [OrderId is uint32]
///   - uint8   tick             (1 byte)
///   - padding                  (3 bytes)
///
/// Total = 16 + 8 + 4 + 1 = 29 bytes (fits in 1 slot).
///
/// - SLOT 1 (COLD):
///   - uint128 requestedShares  (16 bytes)
///   - padding                 (16 bytes)
///
/// requestedShares is immutable and intended for view/debug/indexing only.
/// Keeping it cold avoids touching it during fills (SSTORE to SLOT 0 only).
struct Order {
    // SLOT 0 (HOT)
    uint128 sharesRemaining;
    UserId ownerId;
    OrderId nextOrderId;
    Tick tick;

    // SLOT 1 (COLD)
    uint128 requestedShares;
}
