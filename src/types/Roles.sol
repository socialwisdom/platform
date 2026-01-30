// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Protocol role identifiers used by AccessControl.
abstract contract PlatformRoles {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");
}
