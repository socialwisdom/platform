// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AppStorage, Level, Order} from "../storage/Storage.sol";
import {BookKey, Tick, OrderId} from "../types/Types.sol";
import {Keys} from "../lib/Keys.sol";

/// @notice FIFO queue operations for a single price level (bookKey, tick).
/// Next-only linked list: Order.nextOrderId forms the chain.
///
/// HOT-PATH / NO VALIDATION:
/// - Assumes (bookKey, tick, orderId) are valid and consistent.
/// - Boundary (Platform.sol) must validate user inputs (tick range, etc.).
/// - Core matching must maintain invariants: totalShares, head/tail correctness.
///
/// Invariants maintained:
/// - If level is empty: headOrderId == 0 && tailOrderId == 0 && totalShares == 0
/// - If non-empty: headOrderId != 0 && tailOrderId != 0
/// - tail.nextOrderId == 0
library LevelQueue {
    /// @notice Appends an order to the end of the FIFO queue for (bookKey, tick).
    /// Updates: level.headOrderId/level.tailOrderId, level.totalShares, and the previous tail’s nextOrderId.
    ///
    /// REQUIRES:
    /// - orders[orderKey(bookKey, orderId)] already exists and has:
    ///   - tick == tick
    ///   - nextOrderId == 0
    /// - sharesDelta is the order’s initial sharesRemaining to add to level.totalShares.
    function append(AppStorage storage s, BookKey bookKey, Tick tick, OrderId orderId, uint128 sharesDelta) internal {
        uint256 lk = Keys.levelKey(bookKey, tick);
        Level storage lvl = s.levels[lk];

        if (lvl.headOrderId == 0) {
            // Empty level.
            lvl.headOrderId = OrderId.unwrap(orderId);
            lvl.tailOrderId = OrderId.unwrap(orderId);
        } else {
            // Link previous tail -> new order.
            uint256 tailOk = Keys.orderKey(bookKey, OrderId.wrap(lvl.tailOrderId));
            Order storage tailOrder = s.orders[tailOk];
            tailOrder.nextOrderId = orderId;

            lvl.tailOrderId = OrderId.unwrap(orderId);
        }

        // Update aggregate.
        lvl.totalShares += sharesDelta;
    }

    /// @notice Decreases level totalShares by filledShares (hot-path on every fill).
    /// REQUIRES: filledShares <= lvl.totalShares.
    function decTotalShares(AppStorage storage s, BookKey bookKey, Tick tick, uint128 filledShares) internal {
        uint256 lk = Keys.levelKey(bookKey, tick);
        Level storage lvl = s.levels[lk];
        lvl.totalShares -= filledShares;
    }

    /// @notice Pops head order if it is fully filled (sharesRemaining == 0).
    /// Updates head/tail accordingly. Returns (poppedOrderId, levelBecameEmpty).
    ///
    /// REQUIRES:
    /// - Caller has already set the head order's sharesRemaining to 0.
    /// - Level is non-empty.
    function popHeadIfFilled(AppStorage storage s, BookKey bookKey, Tick tick)
        internal
        returns (OrderId poppedOrderId, bool levelEmpty)
    {
        uint256 lk = Keys.levelKey(bookKey, tick);
        Level storage lvl = s.levels[lk];

        uint32 head = lvl.headOrderId;
        // Caller should not call this on empty levels.
        // We avoid checks for hot-path; incorrect usage is a bug.
        poppedOrderId = OrderId.wrap(head);

        uint256 headOk = Keys.orderKey(bookKey, poppedOrderId);
        Order storage headOrder = s.orders[headOk];

        OrderId next = headOrder.nextOrderId;

        // Unlink head (optional cleanup): set its next to 0.
        // Not strictly required for correctness, but keeps state cleaner.
        headOrder.nextOrderId = OrderId.wrap(0);

        if (OrderId.unwrap(next) == 0) {
            // Queue becomes empty.
            lvl.headOrderId = 0;
            lvl.tailOrderId = 0;
            levelEmpty = true;
        } else {
            lvl.headOrderId = OrderId.unwrap(next);
            levelEmpty = false;
        }
    }

    /// @notice Reads current head order id for (bookKey,tick). Returns 0 if empty.
    function headOrderId(AppStorage storage s, BookKey bookKey, Tick tick) internal view returns (OrderId) {
        uint256 lk = Keys.levelKey(bookKey, tick);
        return OrderId.wrap(s.levels[lk].headOrderId);
    }

    /// @notice Reads current totalShares for (bookKey,tick).
    function totalShares(AppStorage storage s, BookKey bookKey, Tick tick) internal view returns (uint128) {
        uint256 lk = Keys.levelKey(bookKey, tick);
        return s.levels[lk].totalShares;
    }
}
