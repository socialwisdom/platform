// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BookKey} from "../types/IdTypes.sol";
import {Side} from "../types/Enums.sol";

library BookKeyLib {
    uint256 internal constant SIDE_BITS = 8;
    uint256 internal constant OUTCOME_BITS = 8;

    // Layout (low -> high):
    // [ side:8 | outcomeId:8 | marketId:64 ] => total 80 bits
    uint256 internal constant SIDE_MASK = (uint256(1) << SIDE_BITS) - 1; // 0xFF
    uint256 internal constant OUTCOME_MASK = (uint256(1) << OUTCOME_BITS) - 1; // 0xFF

    error InvalidSideValue(uint8 v);

    function pack(uint64 marketId, uint8 outcomeId, Side side) internal pure returns (BookKey) {
        // SECURITY: only allow canonical enum values 0/1
        uint8 sv = uint8(side);
        if (sv > 1) revert InvalidSideValue(sv);

        uint256 key =
            (uint256(marketId) << (OUTCOME_BITS + SIDE_BITS)) | (uint256(outcomeId) << SIDE_BITS) | uint256(sv);

        // casting to uint80 is safe because we pack into <= 80 bits:
        // marketId uses 64 bits, outcomeId 8 bits, side 8 bits.
        // forge-lint: disable-next-line(unsafe-typecast)
        return BookKey.wrap(uint80(key));
    }

    function unpack(BookKey bk) internal pure returns (uint64 marketId, uint8 outcomeId, Side side) {
        uint256 key = uint256(BookKey.unwrap(bk));

        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 sv = uint8(key & SIDE_MASK);
        if (sv > 1) revert InvalidSideValue(sv);
        side = Side(sv);

        // forge-lint: disable-next-line(unsafe-typecast)
        outcomeId = uint8((key >> SIDE_BITS) & OUTCOME_MASK);

        // forge-lint: disable-next-line(unsafe-typecast)
        marketId = uint64(key >> (OUTCOME_BITS + SIDE_BITS));
    }

    function sideOf(BookKey bk) internal pure returns (Side) {
        uint256 key = uint256(BookKey.unwrap(bk));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 sv = uint8(key & SIDE_MASK);
        if (sv > 1) revert InvalidSideValue(sv);
        return Side(sv);
    }

    function opposite(Side s) internal pure returns (Side) {
        return s == Side.Ask ? Side.Bid : Side.Ask;
    }
}
