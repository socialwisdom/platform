// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Tick} from "../types/IdTypes.sol";
import {InvalidTick} from "../types/Errors.sol";

/// @notice Tick helpers. Tick is a discrete price level in [1..99].
/// Bit mapping is fixed as: tick=1 -> bitIndex=0, tick=99 -> bitIndex=98.
///
/// SECURITY / VALIDATION POLICY:
/// - Boundary (Platform.sol) MUST validate user-supplied ticks using check().
/// - After validation, core/lib code treats Tick as a trusted internal invariant.
/// - Hot-path helpers (bitIndex/bit) DO NOT validate to minimize gas.
/// - Never call bitIndex/bit on untrusted external inputs without a prior check().
library TickLib {
    uint8 internal constant MIN_TICK = 1;
    uint8 internal constant MAX_TICK = 99;

    /// @notice Reverts if tick is out of bounds [1..99].
    /// SECURITY:
    /// - Call this at the boundary for any tick coming from calldata/user input.
    function check(Tick tick) internal pure {
        uint8 t = Tick.unwrap(tick);
        if (t < MIN_TICK || t > MAX_TICK) revert InvalidTick(tick);
    }

    /// @notice Converts tick to bit index in mask. tick=1 -> 0.
    /// HOT PATH:
    /// - No validation is performed. Requires tick to be pre-validated.
    function bitIndex(Tick tick) internal pure returns (uint8) {
        return Tick.unwrap(tick) - 1;
    }

    /// @notice Returns the bit (uint128) corresponding to this tick in masks. tick=1 -> 1<<0.
    /// HOT PATH:
    /// - No validation is performed. Requires tick to be pre-validated.
    function bit(Tick tick) internal pure returns (uint128) {
        return uint128(1) << bitIndex(tick);
    }
}
