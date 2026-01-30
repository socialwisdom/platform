// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITradingView} from "../interfaces/ITradingView.sol";

import {PlatformTradingView} from "./PlatformTradingView.sol";

/// @notice Concrete delegatecall target for trading view functions.
contract PlatformTradingViewModule is ITradingView, PlatformTradingView {
    // ==================== ITradingView ====================

    function getCancelCandidates(uint64 marketId, uint8 outcomeId, uint8 side, uint32 targetOrderId, uint256 maxN)
        external
        view
        returns (uint32[] memory)
    {
        return _getCancelCandidates(marketId, outcomeId, side, targetOrderId, maxN);
    }

    function getOrderRemainingAndRequested(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        external
        view
        returns (uint128 remaining, uint128 requested)
    {
        return _getOrderRemainingAndRequested(marketId, outcomeId, side, orderId);
    }

    function getBookMask(uint64 marketId, uint8 outcomeId, uint8 side) external view returns (uint128 mask) {
        return _getBookMask(marketId, outcomeId, side);
    }

    function getLevel(uint64 marketId, uint8 outcomeId, uint8 side, uint8 tick)
        external
        view
        returns (uint32 headOrderId, uint32 tailOrderId, uint128 totalShares)
    {
        return _getLevel(marketId, outcomeId, side, tick);
    }

    function getBookLevels(uint64 marketId, uint8 outcomeId, uint8 side)
        external
        view
        returns (uint8[] memory ticks, uint128[] memory totalShares)
    {
        return _getBookLevels(marketId, outcomeId, side);
    }

    function getMarketBookLevels(uint64 marketId)
        external
        view
        returns (
            uint8 outcomesCount,
            uint8[][] memory bidTicks,
            uint128[][] memory bidTotalShares,
            uint8[][] memory askTicks,
            uint128[][] memory askTotalShares
        )
    {
        return _getMarketBookLevels(marketId);
    }

    function getOrder(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId)
        external
        view
        returns (uint64 ownerId, uint32 nextOrderId, uint8 tick, uint128 sharesRemaining, uint128 requestedShares)
    {
        return _getOrder(marketId, outcomeId, side, orderId);
    }
}
