// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Base primitives and enums used across the codebase.
// Intentionally contains no logic.

type UserId is uint64; // UserId(0) = unregistered, valid ids start at 1
type BookKey is uint80; // packed: marketId(64) | outcomeId(8) | side(8)
type Tick is uint8; // discrete price level, valid range [1..99]
type OrderId is uint32; // monotonically increases per book

enum Side {
    Ask,
    Bid
}

// Generic / shared errors
error ZeroAddress();
error Unauthorized();
error InvalidInput();
error EmptyMask();

// OrderBook / matching errors (shared across callers)
error MinFillNotMet(uint128 filled, uint128 minFill);
error NotOrderOwner(OrderId orderId);
error OrderNotFound(OrderId orderId);
error PrevCandidateNotFound(OrderId orderId);
error TooManyCancelCandidates();

// Typed validation errors
error InvalidUserId(UserId userId);
error InvalidBookKey(BookKey bookKey);
error InvalidTick(Tick tick);
error InvalidOrderId(OrderId orderId);
error InvalidSide(Side side);

// Feature / state errors (used by gating)
error FeatureDisabled(uint256 featureFlag);
