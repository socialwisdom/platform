// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Market lifecycle and configuration APIs.
interface IMarkets {
    // ==================== Events ====================

    /// @notice Emitted once after market storage is written.
    event MarketCreated(
        uint64 indexed marketId,
        uint64 indexed creatorId,
        uint64 indexed resolverId,
        uint64 expirationAt,
        bool allowEarlyResolve,
        uint16 creatorFeeBps,
        bytes32 questionHash,
        bytes32 outcomesHash,
        string question,
        string[] outcomeLabels,
        string resolutionRules
    );

    /// @notice Emitted when resolver selects (or updates) the pending outcome.
    event MarketResolved(uint64 indexed marketId, uint8 winningOutcomeId, uint64 resolvedAt);

    /// @notice Emitted once when resolver finalizes the outcome.
    event MarketFinalized(uint64 indexed marketId, uint64 finalizedAt);

    /// @notice Emitted after market creator role changes.
    event MarketCreatorUpdated(address indexed account, bool isCreator);

    // ==================== Write API ====================

    /// @notice Create a new market.
    /// @param resolver Resolver address for the market.
    /// @param outcomesCount Number of outcomes in the market.
    /// @param expirationAt Timestamp when trading expires (0 = no expiration).
    /// @param allowEarlyResolve Whether resolver can resolve before expiration.
    /// @param makerFeeBps Maker trading fee in bps.
    /// @param takerFeeBps Taker trading fee in bps.
    /// @param questionHash Hash of question metadata.
    /// @param outcomesHash Hash of outcomes metadata.
    /// @param question Human-readable question (event only).
    /// @param outcomeLabels Human-readable outcome labels (event only).
    /// @param resolutionRules Human-readable resolution rules (event only).
    /// @return marketId The newly created market id.
    function createMarket(
        address resolver,
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
    ) external returns (uint64 marketId);

    /// @notice Resolver selects or updates pending outcome.
    function resolveMarket(uint64 marketId, uint8 winningOutcomeId) external;

    /// @notice Resolver finalizes pending outcome.
    function finalizeMarket(uint64 marketId) external;

    /// @notice Set market creator role for an account (Owner only).
    function setMarketCreator(address account, bool isCreator) external;

    // ==================== Read API ====================

    /// @notice Get market configuration and resolution flags.
    function getMarket(uint64 marketId)
        external
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
        );

    /// @notice Get derived market state as uint8.
    /// Values: 0=Active, 1=Expired, 2=ResolvedPending, 3=ResolvedFinal.
    function getMarketState(uint64 marketId) external view returns (uint8);

    /// @notice Check whether an account can create markets.
    function isMarketCreator(address account) external view returns (bool);
}
