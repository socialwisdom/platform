// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Shared enums used across the codebase.

enum Side {
    Ask,
    Bid
}

enum MarketState {
    Active,
    Expired,
    ResolvedPending,
    ResolvedFinal
}
