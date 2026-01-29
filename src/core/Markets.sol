// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {Market} from "../types/Structs.sol";
import {MarketState} from "../types/Enums.sol";
import {UserId} from "../types/IdTypes.sol";
import {
    InvalidInput,
    InvalidOutcomeId,
    MarketAlreadyFinalized,
    MarketFinalizeTooEarly,
    MarketNotResolved,
    MarketResolveTooEarly
} from "../types/Errors.sol";

library Markets {
    function createMarket(
        PlatformStorage.Layout storage s,
        UserId creatorId,
        UserId resolverId,
        uint8 outcomesCount,
        uint64 expirationAt,
        bool allowEarlyResolve,
        uint16 makerFeeBps,
        uint16 takerFeeBps,
        uint16 creatorFeeBps,
        bytes32 questionHash,
        bytes32 outcomesHash
    ) internal returns (uint64 marketId) {
        if (outcomesCount == 0) revert InvalidInput();

        uint64 next = s.nextMarketId;
        if (next == 0) next = 1;

        marketId = next;
        s.nextMarketId = next + 1;

        Market storage m = s.markets[marketId];
        m.creatorId = uint64(UserId.unwrap(creatorId));
        m.resolverId = uint64(UserId.unwrap(resolverId));
        m.outcomesCount = outcomesCount;
        m.expirationAt = expirationAt;
        m.allowEarlyResolve = allowEarlyResolve;
        m.makerFeeBps = makerFeeBps;
        m.takerFeeBps = takerFeeBps;
        m.creatorFeeBps = creatorFeeBps;
        m.questionHash = questionHash;
        m.outcomesHash = outcomesHash;
        // resolved/finalized/winningOutcomeId default to zero values
    }

    function resolveMarket(PlatformStorage.Layout storage s, uint64 marketId, uint8 winningOutcomeId) internal {
        Market storage m = s.markets[marketId];

        if (m.finalized) revert MarketAlreadyFinalized(marketId);
        if (winningOutcomeId >= m.outcomesCount) revert InvalidOutcomeId(winningOutcomeId, m.outcomesCount);

        if (!m.allowEarlyResolve && m.expirationAt != 0 && block.timestamp < m.expirationAt) {
            revert MarketResolveTooEarly(marketId, m.expirationAt);
        }

        m.winningOutcomeId = winningOutcomeId;
        m.resolved = true;
        m.resolvedAt = uint64(block.timestamp);
    }

    function finalizeMarket(PlatformStorage.Layout storage s, uint64 marketId, uint64 finalizeDelay) internal {
        Market storage m = s.markets[marketId];

        if (!m.resolved) revert MarketNotResolved(marketId);
        if (m.finalized) revert MarketAlreadyFinalized(marketId);

        uint64 earliest = m.resolvedAt + finalizeDelay;
        if (block.timestamp < earliest) revert MarketFinalizeTooEarly(marketId, earliest);

        m.finalized = true;
    }

    function deriveState(Market storage m) internal view returns (MarketState) {
        if (m.finalized) return MarketState.ResolvedFinal;
        if (m.resolved) return MarketState.ResolvedPending;
        if (m.expirationAt != 0 && block.timestamp >= m.expirationAt) return MarketState.Expired;
        return MarketState.Active;
    }

    function exists(PlatformStorage.Layout storage s, uint64 marketId) internal view returns (bool) {
        return marketId != 0 && marketId < s.nextMarketId;
    }
}
