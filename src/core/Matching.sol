// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {Level} from "../types/Structs.sol";
import {BookKey, Tick, OrderId} from "../types/IdTypes.sol";
import {Side} from "../types/Enums.sol";
import {Keys} from "../encoding/Keys.sol";
import {Masks} from "../encoding/Masks.sol";
import {LevelQueue} from "./LevelQueue.sol";

library Matching {
    /// @notice Info about a single fill for Trade event emission.
    struct FillInfo {
        OrderId makerId;
        OrderId takerId;
        uint128 sharesFilled;
        Tick tick;
        bool levelEmptied;
    }

    /// @notice Performs one matching step (one maker order fill) and returns fill info.
    /// Caller is responsible for managing the loop and emitting Trade events.
    /// Assumes all inputs are valid (checked by Platform).
    function matchOneStep(
        PlatformStorage storage s,
        BookKey makerBookKey,
        Side makerSide,
        OrderId takerOrderId,
        Tick limitTick,
        uint128 remainingToFill
    ) internal returns (FillInfo memory) {
        FillInfo memory info;
        if (remainingToFill == 0) return info;

        uint128 mask = makerSide == Side.Bid ? s.books[makerBookKey].bidsMask : s.books[makerBookKey].asksMask;
        if (mask == 0) return info;

        Tick tick = makerSide == Side.Bid ? Masks.bestBid(mask) : Masks.bestAsk(mask);
        if (!_checkPrice(makerSide, tick, limitTick)) return info;

        return _fillLevel(s, makerBookKey, makerSide, tick, takerOrderId, remainingToFill, mask);
    }

    function _checkPrice(Side makerSide, Tick tick, Tick limitTick) private pure returns (bool) {
        uint8 tickValue = Tick.unwrap(tick);
        uint8 limitValue = Tick.unwrap(limitTick);
        return makerSide == Side.Bid ? tickValue >= limitValue : tickValue <= limitValue;
    }

    function _fillLevel(
        PlatformStorage storage s,
        BookKey makerBookKey,
        Side makerSide,
        Tick tick,
        OrderId takerOrderId,
        uint128 remainingToFill,
        uint128 mask
    ) private returns (FillInfo memory info) {
        Level storage level = s.levels[Keys.levelKey(makerBookKey, tick)];
        uint32 headOrderIdRaw = level.headOrderId;
        if (headOrderIdRaw == 0) {
            _clearMask(s, makerBookKey, makerSide, tick, mask);
            return info;
        }

        OrderId headOrderId = OrderId.wrap(headOrderIdRaw);
        uint128 headRemaining = s.orders[Keys.orderKey(makerBookKey, headOrderId)].sharesRemaining;
        if (headRemaining == 0) {
            (, bool levelEmptied) = LevelQueue.popHeadIfFilled(s, makerBookKey, tick);
            if (levelEmptied) _clearMask(s, makerBookKey, makerSide, tick, mask);
            return info;
        }

        uint128 filled = headRemaining < remainingToFill ? headRemaining : remainingToFill;
        s.orders[Keys.orderKey(makerBookKey, headOrderId)].sharesRemaining = headRemaining - filled;
        level.totalShares -= filled;

        if (headRemaining == filled) {
            (, bool levelEmptied) = LevelQueue.popHeadIfFilled(s, makerBookKey, tick);
            if (levelEmptied) _clearMask(s, makerBookKey, makerSide, tick, mask);
            info.levelEmptied = true;
        }

        info.makerId = headOrderId;
        info.takerId = takerOrderId;
        info.sharesFilled = filled;
        info.tick = tick;
        return info;
    }

    function _clearMask(PlatformStorage storage s, BookKey makerBookKey, Side makerSide, Tick tick, uint128 mask)
        private
    {
        uint128 clearedMask = Masks.clear(mask, tick);
        if (makerSide == Side.Bid) s.books[makerBookKey].bidsMask = clearedMask;
        else s.books[makerBookKey].asksMask = clearedMask;
    }
}
