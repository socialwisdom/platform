// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Tick, EmptyMask} from "../types/Types.sol";

library MaskLib {
    function hasAny(uint128 mask) internal pure returns (bool) {
        return mask != 0;
    }

    function set(uint128 mask, Tick tick) internal pure returns (uint128) {
        return mask | _bit(tick);
    }

    function clear(uint128 mask, Tick tick) internal pure returns (uint128) {
        return mask & ~_bit(tick);
    }

    function bestAsk(uint128 mask) internal pure returns (Tick) {
        if (mask == 0) revert EmptyMask();

        uint128 lsb = mask & (~mask + 1);
        uint8 idx = _ctz128(lsb);
        return Tick.wrap(idx + 1);
    }

    function bestBid(uint128 mask) internal pure returns (Tick) {
        if (mask == 0) revert EmptyMask();

        uint8 idx = _msb128(mask);
        return Tick.wrap(idx + 1);
    }

    function _bit(Tick tick) private pure returns (uint128) {
        return uint128(1) << (Tick.unwrap(tick) - 1);
    }

    /// @dev Count trailing zeros for non-zero 128-bit x. Returns [0..127].
    function _ctz128(uint128 x) private pure returns (uint8 n) {
        // We intentionally test the low k bits by truncating to uint{k}.
        // This cast is safe because we only care whether the low part is zero.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (uint64(x) == 0) {
            n += 64;
            x >>= 64;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        if (uint32(x) == 0) {
            n += 32;
            x >>= 32;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        if (uint16(x) == 0) {
            n += 16;
            x >>= 16;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        if (uint8(x) == 0) {
            n += 8;
            x >>= 8;
        }
        if (x & 0x0F == 0) {
            n += 4;
            x >>= 4;
        }
        if (x & 0x03 == 0) {
            n += 2;
            x >>= 2;
        }
        if (x & 0x01 == 0) {
            n += 1;
        }
        return n;
    }

    /// @dev Most significant bit index for non-zero 128-bit x. Returns [0..127].
    function _msb128(uint128 x) private pure returns (uint8 n) {
        // SECURITY: caller ensures x != 0.
        if (x >> 64 != 0) {
            x >>= 64;
            n += 64;
        }
        if (x >> 32 != 0) {
            x >>= 32;
            n += 32;
        }
        if (x >> 16 != 0) {
            x >>= 16;
            n += 16;
        }
        if (x >> 8 != 0) {
            x >>= 8;
            n += 8;
        }
        if (x >> 4 != 0) {
            x >>= 4;
            n += 4;
        }
        if (x >> 2 != 0) {
            x >>= 2;
            n += 2;
        }
        if (x >> 1 != 0) {
            n += 1;
        }
        return n;
    }
}
