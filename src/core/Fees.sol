// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Tick} from "../types/IdTypes.sol";
import {InvalidInput, FeeBpsTooHigh} from "../types/Errors.sol";

/// @notice Fee and price math helpers (pure).
library Fees {
    uint16 internal constant MAX_FEE_BPS = 1_000; // 10%
    uint16 internal constant FEE_BPS_DENOM = 10_000;

    uint256 internal constant DECIMALS = 1e6;
    uint256 internal constant TICK_DENOM = 100; // centi-Points per share

    /// @notice Validate fee bps against MAX_FEE_BPS.
    function validateFeeBps(uint16 feeBps) internal pure {
        if (feeBps > MAX_FEE_BPS) revert FeeBpsTooHigh(feeBps, MAX_FEE_BPS);
    }

    /// @notice Compute sellerGross (floor), buyerPaid (ceil), and dust for a fill.
    /// num = shares * tick * 1e6, den = 100 * 1e6
    function computeNotional(uint128 shares, Tick tick)
        internal
        pure
        returns (uint128 sellerGross, uint128 buyerPaid, uint128 dust)
    {
        uint256 num = uint256(shares) * uint256(uint8(Tick.unwrap(tick))) * DECIMALS;
        uint256 den = TICK_DENOM * DECIMALS;
        uint256 floorVal = num / den;
        uint256 ceilVal = (num + den - 1) / den;
        if (floorVal > type(uint128).max || ceilVal > type(uint128).max) revert InvalidInput();
        // casting to 'uint128' is safe because floor/ceil are bounded by the checks above
        // forge-lint: disable-next-line(unsafe-typecast)
        sellerGross = uint128(floorVal);
        // casting to 'uint128' is safe because floor/ceil are bounded by the checks above
        // forge-lint: disable-next-line(unsafe-typecast)
        buyerPaid = uint128(ceilVal);
        // casting to 'uint128' is safe because floor/ceil are bounded by the checks above
        // forge-lint: disable-next-line(unsafe-typecast)
        dust = uint128(ceilVal - floorVal);
    }

    /// @notice Compute sellerGross (floor) for a given shares/tick.
    function computeSellerGross(uint128 shares, Tick tick) internal pure returns (uint128 sellerGross) {
        uint256 num = uint256(shares) * uint256(uint8(Tick.unwrap(tick))) * DECIMALS;
        uint256 den = TICK_DENOM * DECIMALS;
        uint256 floorVal = num / den;
        if (floorVal > type(uint128).max) revert InvalidInput();
        // casting to 'uint128' is safe because floorVal is checked above
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(floorVal);
    }

    /// @notice Compute buyerPaid (ceil) for a given shares/tick.
    function computeBuyerPaid(uint128 shares, Tick tick) internal pure returns (uint128 buyerPaid) {
        uint256 num = uint256(shares) * uint256(uint8(Tick.unwrap(tick))) * DECIMALS;
        uint256 den = TICK_DENOM * DECIMALS;
        uint256 ceilVal = (num + den - 1) / den;
        if (ceilVal > type(uint128).max) revert InvalidInput();
        // casting to 'uint128' is safe because ceilVal is checked above
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(ceilVal);
    }

    /// @notice Compute fee = ceil(sellerGross * feeBps / 10_000).
    function computeFee(uint128 sellerGross, uint16 feeBps) internal pure returns (uint128 fee) {
        if (feeBps == 0 || sellerGross == 0) return 0;
        uint256 num = uint256(sellerGross) * uint256(feeBps);
        uint256 feeVal = (num + FEE_BPS_DENOM - 1) / FEE_BPS_DENOM;
        if (feeVal > type(uint128).max) revert InvalidInput();
        // casting to 'uint128' is safe because feeVal is checked above
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(feeVal);
    }

    /// @notice Compute max fee for shares at limit tick using sellerGross base.
    function computeMaxFee(uint128 shares, Tick limitTick, uint16 feeBps) internal pure returns (uint128) {
        uint128 sellerGross = computeSellerGross(shares, limitTick);
        return computeFee(sellerGross, feeBps);
    }
}
