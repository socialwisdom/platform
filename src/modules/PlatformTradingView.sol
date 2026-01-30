// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {Order, Level} from "../types/Structs.sol";
import {UserId, BookKey, Tick, OrderId} from "../types/IdTypes.sol";
import {Side} from "../types/Enums.sol";

import {BookKeyLib} from "../encoding/BookKeyLib.sol";
import {Keys} from "../encoding/Keys.sol";
import {Masks} from "../encoding/Masks.sol";

import {OrderBook} from "../core/OrderBook.sol";

/// @notice Internal read-only order book views.
abstract contract PlatformTradingView {
    // ==================== ITradingView ====================

    // ==================== Read API ====================

    function _getCancelCandidates(uint64 marketId, uint8 outcomeId, uint8 side, uint32 targetOrderId, uint256 maxN)
        internal
        view
        returns (uint32[] memory)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));

        uint256 n = maxN > 16 ? 16 : maxN;
        if (n == 0) return new uint32[](0);

        PlatformStorage.Layout storage s = PlatformStorage.layout();
        OrderId[] memory candidates = OrderBook.collectPrevCandidates(s, bookKey, OrderId.wrap(targetOrderId), n);

        // Cast result back to uint32[]
        uint32[] memory result = new uint32[](candidates.length);
        for (uint256 i = 0; i < candidates.length; i++) {
            result[i] = OrderId.unwrap(candidates[i]);
        }
        return result;
    }

    function _getOrderRemainingAndRequested(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        internal
        view
        returns (uint128 remaining, uint128 requested)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Order storage o = s.orders[Keys.orderKey(bookKey, OrderId.wrap(orderId))];
        return (o.sharesRemaining, o.requestedShares);
    }

    function _getBookMask(uint64 marketId, uint8 outcomeId, uint8 side) internal view returns (uint128 mask) {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();

        return Side(side) == Side.Bid ? s.books[bookKey].bidsMask : s.books[bookKey].asksMask;
    }

    function _getLevel(uint64 marketId, uint8 outcomeId, uint8 side, uint8 tick)
        internal
        view
        returns (uint32 headOrderId, uint32 tailOrderId, uint128 totalShares)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();

        Level storage lvl = s.levels[Keys.levelKey(bookKey, Tick.wrap(tick))];
        return (lvl.headOrderId, lvl.tailOrderId, lvl.totalShares);
    }

    function _getBookLevels(uint64 marketId, uint8 outcomeId, uint8 side)
        internal
        view
        returns (uint8[] memory ticks, uint128[] memory totalShares)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();

        uint128 mask = Side(side) == Side.Bid ? s.books[bookKey].bidsMask : s.books[bookKey].asksMask;
        if (mask == 0) return (new uint8[](0), new uint128[](0));

        uint128 m = mask;
        uint256 count = 0;
        while (m != 0) {
            m &= (m - 1);
            count++;
        }

        ticks = new uint8[](count);
        totalShares = new uint128[](count);

        m = mask;
        for (uint256 i = 0; i < count; i++) {
            Tick tick = Side(side) == Side.Bid ? Masks.bestBid(m) : Masks.bestAsk(m);
            ticks[i] = Tick.unwrap(tick);

            Level storage lvl = s.levels[Keys.levelKey(bookKey, tick)];
            totalShares[i] = lvl.totalShares;

            m = Masks.clear(m, tick);
        }
    }

    function _getMarketBookLevels(uint64 marketId)
        internal
        view
        returns (
            uint8 outcomesCount,
            uint8[][] memory bidTicks,
            uint128[][] memory bidTotalShares,
            uint8[][] memory askTicks,
            uint128[][] memory askTotalShares
        )
    {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        outcomesCount = s.markets[marketId].outcomesCount;

        if (outcomesCount == 0) {
            return (0, new uint8[][](0), new uint128[][](0), new uint8[][](0), new uint128[][](0));
        }

        bidTicks = new uint8[][](outcomesCount);
        bidTotalShares = new uint128[][](outcomesCount);
        askTicks = new uint8[][](outcomesCount);
        askTotalShares = new uint128[][](outcomesCount);

        for (uint8 outcomeId = 0; outcomeId < outcomesCount; outcomeId++) {
            (uint8[] memory _bt, uint128[] memory _bs) = _getBookLevels(marketId, outcomeId, uint8(Side.Bid));
            (uint8[] memory _at, uint128[] memory _as) = _getBookLevels(marketId, outcomeId, uint8(Side.Ask));

            bidTicks[outcomeId] = _bt;
            bidTotalShares[outcomeId] = _bs;
            askTicks[outcomeId] = _at;
            askTotalShares[outcomeId] = _as;
        }
    }

    function _getOrder(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        internal
        view
        returns (uint64 ownerId, uint32 nextOrderId, uint8 tick, uint128 sharesRemaining, uint128 requestedShares)
    {
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side(side));
        PlatformStorage.Layout storage s = PlatformStorage.layout();

        Order storage o = s.orders[Keys.orderKey(bookKey, OrderId.wrap(orderId))];
        return (
            UserId.unwrap(o.ownerId),
            OrderId.unwrap(o.nextOrderId),
            Tick.unwrap(o.tick),
            o.sharesRemaining,
            o.requestedShares
        );
    }
}
