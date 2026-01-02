// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice User-facing ID types.
/// Intentionally contains no logic.

type UserId is uint64; // UserId(0) = unregistered, valid ids start at 1
type BookKey is uint80; // packed: marketId(64) | outcomeId(8) | side(8)
type Tick is uint8; // discrete price level, valid range [1..99]
type OrderId is uint32; // monotonically increases per book
