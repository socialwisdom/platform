// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BookKey, Tick, OrderId} from "../types/Types.sol";

/// @notice Deterministic key derivation helpers for order book mappings.
/// No validation, no branching, no logic — pure packing.
///
/// KEY LAYOUTS (must remain stable):
/// - levelKey  = (uint256(bookKey) << 8)  | uint8(tick)
/// - orderKey  = (uint256(bookKey) << 32) | uint32(orderId)
///
/// SECURITY / INVARIANTS:
/// - bookKey, tick, and orderId are assumed to be validated at the boundary.
/// - These helpers are hot-path and must stay branchless.
library Keys {
    /// @notice Returns the storage key for a price level (book, tick).
    /// tick is stored in the low 8 bits.
    function levelKey(BookKey bookKey, Tick tick) internal pure returns (uint256) {
        return (uint256(BookKey.unwrap(bookKey)) << 8) | uint256(Tick.unwrap(tick));
    }

    /// @notice Returns the storage key for an order (book, orderId).
    /// orderId is stored in the low 32 bits.
    function orderKey(BookKey bookKey, OrderId orderId) internal pure returns (uint256) {
        return (uint256(BookKey.unwrap(bookKey)) << 32) | uint256(OrderId.unwrap(orderId));
    }
}
