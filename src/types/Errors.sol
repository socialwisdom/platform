// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UserId, BookKey, Tick, OrderId} from "./IdTypes.sol";
import {Side} from "./Enums.sol";

/// @notice Custom errors for the entire protocol.

// Generic / shared errors
error ZeroAddress();
error Unauthorized();
error InvalidInput();
error EmptyMask();

// User registry errors
error UnregisteredUser();

// Balance / accounting errors
error InsufficientFreePoints(uint128 available, uint128 required);
error InsufficientFreeShares(uint128 available, uint128 required);
error InsufficientReservedPoints(uint128 available, uint128 required);
error InsufficientReservedShares(uint128 available, uint128 required);

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
