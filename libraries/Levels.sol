// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// Invariants:
/// - (headOrder != 0) == active
/// - (tailOrder != 0) == active
///
/// Helpers:
/// - isBest == (active && prevLevel == 0)
struct Level {
    bool active;
    uint8 prevLevel;
    uint8 nextLevel;
    uint256 headOrder;
    uint256 tailOrder;
}

library LevelsLib {
    function createBest(mapping (uint8 => Level) storage levels, uint8 price, uint8 nextPrice, uint256 orderId) internal {
        return createBetween(levels, price, 0, nextPrice, orderId);
    }

    function createBetween(mapping (uint8 => Level) storage levels, uint8 price, uint8 prevLevel, uint8 nextLevel, uint256 orderId) internal {
        Level storage level = levels[price];

        level.active = true;
        level.prevLevel = prevLevel;
        level.nextLevel = nextLevel;
        level.headOrder = orderId;
        level.tailOrder = orderId;

        if (prevLevel != 0) {
            /* dev */ require(levels[prevLevel].active, "levels.createBetween: inactive prev level");
            levels[prevLevel].nextLevel = price;
        }

        if (nextLevel != 0) {
            /* dev */ require(levels[nextLevel].active, "levels.createBetween: inactive next level");
            levels[nextLevel].prevLevel = price;
        }
    }

    function createBuy(mapping (uint8 => Level) storage levels, uint8 price, uint8 bestPrice, uint256 orderId) internal {
        while (bestPrice > price) {
            if (levels[bestPrice].nextLevel < price) {
                return createBetween(levels, price, bestPrice, levels[bestPrice].nextLevel, orderId);
            } else {
                bestPrice = levels[bestPrice].nextLevel;
            }
        }
    }

    function createSell(mapping (uint8 => Level) storage levels, uint8 price, uint8 bestPrice, uint256 orderId) internal {
        while (bestPrice < price || bestPrice == 0) {
            if (levels[bestPrice].nextLevel > price || levels[bestPrice].nextLevel == 0) {
                return createBetween(levels, price, bestPrice, levels[bestPrice].nextLevel, orderId);
            } else {
                bestPrice = levels[bestPrice].nextLevel;
            }
        }
    }

    /// @return (bestChanged, nextLevel).
    function remove(mapping (uint8 => Level) storage levels, uint8 price) internal returns (bool, uint8) {
        Level storage level = levels[price];
        /* dev */ require(level.active, "levels.remove: inactive level");

        level.active = false;
        level.headOrder = 0;
        level.tailOrder = 0;

        if (level.nextLevel != 0) {
            /* dev */ require(levels[level.nextLevel].active, "levels.remove: inactive next level");
            levels[level.nextLevel].prevLevel = level.prevLevel;
        }

        if (level.prevLevel != 0) {
            /* dev */ require(levels[level.prevLevel].active, "levels.remove: inactive prev level");
            levels[level.prevLevel].nextLevel = level.nextLevel;
        }

        return (level.prevLevel == 0, level.nextLevel);
    }
}
