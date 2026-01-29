// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IMarkets} from "../interfaces/IMarkets.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {Market} from "../types/Structs.sol";
import {UserId} from "../types/IdTypes.sol";
import {MarketState} from "../types/Enums.sol";
import {FeeBpsTooHigh, Unauthorized, MarketNotFound, InvalidOutcomeId, MarketNotActive} from "../types/Errors.sol";

import {Markets} from "../core/Markets.sol";
import {Fees} from "../core/Fees.sol";

/// @notice Internal market lifecycle logic.
abstract contract PlatformMarkets {
    uint16 internal constant MAX_CREATOR_FEE_BPS_INTERNAL = 2_500; // 25%

    // ==================== IMarkets ====================

    // ==================== Write API ====================

    function _createMarket(
        UserId creatorId,
        UserId resolverId,
        uint8 outcomesCount,
        uint64 expirationAt,
        bool allowEarlyResolve,
        uint16 makerFeeBps,
        uint16 takerFeeBps,
        uint16 creatorFeeBps,
        bytes32 questionHash,
        bytes32 outcomesHash,
        string calldata question,
        string[] calldata outcomeLabels,
        string calldata resolutionRules
    ) internal returns (uint64 marketId) {
        if (!_isMarketCreator(creatorId)) revert Unauthorized();

        Fees.validateFeeBps(makerFeeBps);
        Fees.validateFeeBps(takerFeeBps);
        if (creatorFeeBps > MAX_CREATOR_FEE_BPS_INTERNAL) {
            revert FeeBpsTooHigh(creatorFeeBps, MAX_CREATOR_FEE_BPS_INTERNAL);
        }
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        marketId = Markets.createMarket(
            s,
            creatorId,
            resolverId,
            outcomesCount,
            expirationAt,
            allowEarlyResolve,
            makerFeeBps,
            takerFeeBps,
            creatorFeeBps,
            questionHash,
            outcomesHash
        );

        emit IMarkets.MarketCreated(
            marketId,
            UserId.unwrap(creatorId),
            UserId.unwrap(resolverId),
            expirationAt,
            allowEarlyResolve,
            creatorFeeBps,
            questionHash,
            outcomesHash,
            question,
            outcomeLabels,
            resolutionRules
        );
    }

    function _resolveMarket(uint64 marketId, uint8 winningOutcomeId, UserId resolverId) internal {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _requireMarketExistsAndOutcome(marketId, winningOutcomeId);

        Market storage m = s.markets[marketId];
        if (m.resolverId != UserId.unwrap(resolverId)) revert Unauthorized();

        Markets.resolveMarket(s, marketId, winningOutcomeId);
        emit IMarkets.MarketResolved(marketId, winningOutcomeId, uint64(block.timestamp));
    }

    function _finalizeMarket(uint64 marketId, uint64 resolveFinalizeDelay, UserId resolverId) internal {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _requireMarketExists(marketId);

        Market storage m = s.markets[marketId];
        if (m.resolverId != UserId.unwrap(resolverId)) revert Unauthorized();

        Markets.finalizeMarket(s, marketId, resolveFinalizeDelay);
        emit IMarkets.MarketFinalized(marketId, uint64(block.timestamp));
    }

    function _setMarketCreator(address account, UserId uid, bool isCreator) internal {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        s.marketCreator[uid] = isCreator;
        emit IMarkets.MarketCreatorUpdated(account, isCreator);
    }

    // ==================== Read API ====================

    function _getMarket(uint64 marketId)
        internal
        view
        returns (
            uint64 creatorId,
            uint64 resolverId,
            uint8 outcomesCount,
            uint64 expirationAt,
            bool allowEarlyResolve,
            uint16 makerFeeBps,
            uint16 takerFeeBps,
            uint16 creatorFeeBps,
            bytes32 questionHash,
            bytes32 outcomesHash,
            bool resolved,
            bool finalized,
            uint8 winningOutcomeId
        )
    {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _requireMarketExists(marketId);

        Market storage m = s.markets[marketId];
        return (
            m.creatorId,
            m.resolverId,
            m.outcomesCount,
            m.expirationAt,
            m.allowEarlyResolve,
            m.makerFeeBps,
            m.takerFeeBps,
            m.creatorFeeBps,
            m.questionHash,
            m.outcomesHash,
            m.resolved,
            m.finalized,
            m.winningOutcomeId
        );
    }

    function _getMarketState(uint64 marketId) internal view returns (uint8) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _requireMarketExists(marketId);

        Market storage m = s.markets[marketId];
        return uint8(Markets.deriveState(m));
    }

    function _isMarketCreator(UserId userId) internal view returns (bool) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return s.marketCreator[userId];
    }

    // ==================== Internal Helpers ====================

    function _requireMarketExists(uint64 marketId) internal view {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        if (!Markets.exists(s, marketId)) revert MarketNotFound(marketId);
    }

    function _requireMarketExistsAndOutcome(uint64 marketId, uint8 outcomeId) internal view {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _requireMarketExists(marketId);
        Market storage m = s.markets[marketId];
        if (outcomeId >= m.outcomesCount) revert InvalidOutcomeId(outcomeId, m.outcomesCount);
    }

    function _requireActiveMarket(uint64 marketId, uint8 outcomeId) internal view {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _requireMarketExistsAndOutcome(marketId, outcomeId);
        Market storage m = s.markets[marketId];
        if (Markets.deriveState(m) != MarketState.Active) revert MarketNotActive(marketId);
    }
}
