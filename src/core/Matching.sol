// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {BookState, Level, Order} from "../types/Structs.sol";
import {BookKey, Tick, OrderId} from "../types/IdTypes.sol";
import {Side} from "../types/Enums.sol";
import {BookKeyLib} from "../encoding/BookKeyLib.sol";
import {Keys} from "../encoding/Keys.sol";
import {Masks} from "../encoding/Masks.sol";
import {LevelQueue} from "./LevelQueue.sol";

library Matching {
    /// @notice Matches up to sharesRequested against the opposite side book within limitTick.
    /// Returns (sharesFilled, pointsTraded = sum(fillShares * tick)).
    function matchUpTo(PlatformStorage storage s, BookKey takerBookKey, Tick limitTick, uint128 sharesRequested)
        internal
        returns (uint128 sharesFilled, uint256 pointsTraded)
    {
        if (sharesRequested == 0) return (0, 0);

        Side takerSide = BookKeyLib.sideOf(takerBookKey);
        Side makerSide = BookKeyLib.opposite(takerSide);

        (uint64 marketId, uint8 outcomeId,) = BookKeyLib.unpack(takerBookKey);
        BookKey makerBookKey = BookKeyLib.pack(marketId, outcomeId, makerSide);

        return _matchLoop(s, makerBookKey, makerSide, takerSide, limitTick, sharesRequested);
    }

    function _matchLoop(
        PlatformStorage storage s,
        BookKey makerBookKey,
        Side makerSide,
        Side takerSide,
        Tick limitTick,
        uint128 sharesRequested
    ) private returns (uint128 sharesFilled, uint256 pointsTraded) {
        BookState storage makerBook = s.books[makerBookKey];

        uint128 mask = makerSide == Side.Bid ? makerBook.bidsMask : makerBook.asksMask;

        uint128 remaining = sharesRequested;
        uint8 limit = Tick.unwrap(limitTick);

        while (remaining != 0 && mask != 0) {
            Tick bestTick = makerSide == Side.Bid ? Masks.bestBid(mask) : Masks.bestAsk(mask);
            uint8 bt = Tick.unwrap(bestTick);

            if (takerSide == Side.Bid) {
                if (bt > limit) break;
            } else {
                if (bt < limit) break;
            }

            // packed result: [ emptied (1 bit) | filled (128 bits) ]
            uint256 packed = _fillOneLevelPacked(s, makerBookKey, bestTick, remaining);
            // casting to uint128 is safe because _fillOneLevelPacked encodes filledInLevel only in the low 128 bits
            // and filledInLevel is accumulated as uint128 (never exceeds 2^128-1).
            // forge-lint: disable-next-line(unsafe-typecast)
            uint128 filled = uint128(packed);
            bool emptied = (packed >> 255) != 0; // top bit

            if (filled != 0) {
                unchecked {
                    remaining -= filled;
                    sharesFilled += filled;
                }
                pointsTraded += uint256(filled) * uint256(bt);
            }

            if (emptied) {
                mask = Masks.clear(mask, bestTick);
                if (makerSide == Side.Bid) makerBook.bidsMask = mask;
                else makerBook.asksMask = mask;
            }
        }

        return (sharesFilled, pointsTraded);
    }

    /// @dev Fills one price level FIFO.
    /// Returns packed uint256:
    /// - bit 255: levelEmptied
    /// - bits [0..127]: filledInLevel (uint128)
    function _fillOneLevelPacked(PlatformStorage storage s, BookKey makerBookKey, Tick tick, uint128 remainingToFill)
        private
        returns (uint256 packed)
    {
        Level storage lvl = s.levels[Keys.levelKey(makerBookKey, tick)];

        uint128 remaining = remainingToFill;
        uint128 filledInLevel = 0;

        while (remaining != 0) {
            uint32 headRaw = lvl.headOrderId;
            if (headRaw == 0) {
                // mask says non-empty but level empty -> treat as emptied
                return (uint256(1) << 255) | uint256(filledInLevel);
            }

            OrderId headId = OrderId.wrap(headRaw);
            Order storage ord = s.orders[Keys.orderKey(makerBookKey, headId)];

            uint128 makerRem = ord.sharesRemaining;

            if (makerRem == 0) {
                (, bool emptied0) = LevelQueue.popHeadIfFilled(s, makerBookKey, tick);
                if (emptied0) return (uint256(1) << 255) | uint256(filledInLevel);
                continue;
            }

            uint128 fill = makerRem < remaining ? makerRem : remaining;

            unchecked {
                ord.sharesRemaining = makerRem - fill;
                lvl.totalShares -= fill;

                remaining -= fill;
                filledInLevel += fill;
            }

            if (ord.sharesRemaining == 0) {
                (, bool emptied) = LevelQueue.popHeadIfFilled(s, makerBookKey, tick);
                if (emptied) return (uint256(1) << 255) | uint256(filledInLevel);
                // else continue
            } else {
                // head partially filled => stop at this tick
                return uint256(filledInLevel);
            }
        }

        return uint256(filledInLevel);
    }
}
