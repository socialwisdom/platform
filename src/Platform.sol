// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlatform} from "./interfaces/IPlatform.sol";
import {IMarkets} from "./interfaces/IMarkets.sol";

import {PlatformStorage} from "./storage/PlatformStorage.sol";
import {UserId, BookKey, Tick} from "./types/IdTypes.sol";
import {Side} from "./types/Enums.sol";
import {InvalidInput, TooManyCancelCandidates} from "./types/Errors.sol";

import {Accounting} from "./core/Accounting.sol";
import {BookKeyLib} from "./encoding/BookKeyLib.sol";
import {TickLib} from "./encoding/TickLib.sol";

import {PlatformAccounting} from "./modules/PlatformAccounting.sol";
import {PlatformAdmin} from "./modules/PlatformAdmin.sol";
import {PlatformCustody} from "./modules/PlatformCustody.sol";
import {PlatformMarkets} from "./modules/PlatformMarkets.sol";
import {PlatformTrading} from "./modules/PlatformTrading.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract Platform is
    IPlatform,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ERC1155Holder,
    PlatformAccounting,
    PlatformAdmin,
    PlatformCustody,
    PlatformMarkets,
    PlatformTrading
{
    uint64 public constant RESOLVE_FINALIZE_DELAY = 1 hours;
    uint16 public constant MAX_CREATOR_FEE_BPS = 2_500; // 25%

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address tradingViewModule) external initializer {
        _initializeOwner(owner);
        _setTradingViewModule(tradingViewModule);
    }

    function reinitializeV2() external reinitializer(2) onlyRole(DEFAULT_ADMIN_ROLE) {
        _reinitializeV2();
    }

    // ==================== IAccounting ====================

    // ==================== Write API ====================

    function register() external whenNotPaused returns (uint64 id) {
        return UserId.unwrap(_getOrRegister(msg.sender));
    }

    function sweepMarketFees(uint64 marketId)
        external
        whenNotPaused
        returns (uint128 protocolFeesPoints, uint128 creatorFeesPoints)
    {
        return _sweepMarketFees(marketId);
    }
    // ==================== Read API ====================

    function userIdOf(address user) external view returns (uint64) {
        return _userIdOf(user);
    }

    function userOfId(uint64 id) external view returns (address) {
        return _userOfId(id);
    }

    function getPointsBalance(address user) external view returns (uint128 free, uint128 reserved) {
        UserId uid = UserId.wrap(_userIdOf(user));
        if (UserId.unwrap(uid) == 0) return (0, 0);
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return Accounting.getPointsBalance(s, uid);
    }

    function getSharesBalance(uint64 marketId, uint8 outcomeId, address user)
        external
        view
        returns (uint128 free, uint128 reserved)
    {
        UserId uid = UserId.wrap(_userIdOf(user));
        if (UserId.unwrap(uid) == 0) return (0, 0);
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return Accounting.getSharesBalance(s, uid, bookKey);
    }

    function getMarketTradingFeesPoints(uint64 marketId) external view returns (uint128) {
        return _getMarketTradingFeesPoints(marketId);
    }

    function getProtocolDustPoints() external view returns (uint128) {
        return _getProtocolDustPoints();
    }

    function getProtocolFeesPoints() external view returns (uint128) {
        return _getProtocolFeesPoints();
    }

    // ==================== IAdmin ====================

    // ==================== Write API ====================

    function setFeeExempt(address account, bool isExempt) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        UserId uid = _getOrRegister(account);
        _setFeeExempt(uid, account, isExempt);
    }

    function pause() external onlyRole(PAUSER_ROLE) whenNotPaused {
        _pauseProtocol();
    }

    function unpause() external onlyRole(PAUSER_ROLE) whenPaused {
        _unpauseProtocol();
    }

    function grantRole(bytes32 role, address account) public override(AccessControlUpgradeable) whenNotPaused {
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public override(AccessControlUpgradeable) whenNotPaused {
        super.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) public override(AccessControlUpgradeable) whenNotPaused {
        super.renounceRole(role, account);
    }

    // ==================== Read API ====================

    function isFeeExempt(address account) external view returns (bool) {
        UserId uid = UserId.wrap(_userIdOf(account));
        if (UserId.unwrap(uid) == 0) return false;
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return s.feeExempt[uid];
    }

    function isPaused() external view returns (bool) {
        return _isPausedView();
    }

    // ==================== ICustody ====================

    // ==================== Write API ====================

    function deposit(uint128 amount) external whenNotPaused {
        if (amount == 0) revert InvalidInput();
        UserId uid = _getOrRegister(msg.sender);
        _deposit(uid, amount);
    }

    function withdraw(uint128 amount) external whenNotPaused {
        if (amount == 0) revert InvalidInput();
        UserId uid = _requireRegistered(msg.sender);
        _withdraw(uid, amount);
    }

    function depositShares(uint64 marketId, uint8 outcomeId, uint128 amount) external whenNotPaused {
        if (amount == 0) revert InvalidInput();
        UserId uid = _getOrRegister(msg.sender);
        _depositShares(uid, marketId, outcomeId, amount);
    }

    function withdrawShares(uint64 marketId, uint8 outcomeId, uint128 amount) external whenNotPaused {
        if (amount == 0) revert InvalidInput();
        UserId uid = _requireRegistered(msg.sender);
        _withdrawShares(uid, marketId, outcomeId, amount);
    }

    // ==================== IMarkets ====================

    // ==================== Write API ====================

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
    ) external whenNotPaused onlyRole(MARKET_CREATOR_ROLE) returns (uint64 marketId) {
        UserId creatorId = _getOrRegister(msg.sender);
        UserId resolverId = _getOrRegister(resolver);
        return _createMarket(
            creatorId,
            resolverId,
            outcomesCount,
            expirationAt,
            allowEarlyResolve,
            makerFeeBps,
            takerFeeBps,
            creatorFeeBps,
            questionHash,
            outcomesHash,
            question,
            outcomeLabels,
            resolutionRules
        );
    }

    function resolveMarket(uint64 marketId, uint8 winningOutcomeId) external whenNotPaused {
        UserId resolverId = UserId.wrap(_userIdOf(msg.sender));
        _resolveMarket(marketId, winningOutcomeId, resolverId);
    }

    function finalizeMarket(uint64 marketId) external whenNotPaused {
        UserId resolverId = UserId.wrap(_userIdOf(msg.sender));
        _finalizeMarket(marketId, RESOLVE_FINALIZE_DELAY, resolverId);
    }

    function setMarketCreator(address account, bool isCreator) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        _getOrRegister(account);
        if (isCreator) {
            _grantRole(MARKET_CREATOR_ROLE, account);
        } else {
            _revokeRole(MARKET_CREATOR_ROLE, account);
        }
        emit IMarkets.MarketCreatorUpdated(account, isCreator);
    }

    // ==================== Read API ====================

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
        )
    {
        return _getMarket(marketId);
    }

    function getMarketState(uint64 marketId) external view returns (uint8) {
        return _getMarketState(marketId);
    }

    function isMarketCreator(address account) external view returns (bool) {
        UserId uid = UserId.wrap(_userIdOf(account));
        if (UserId.unwrap(uid) == 0) return false;
        return hasRole(MARKET_CREATOR_ROLE, account);
    }

    // ==================== ITrading ====================

    // ==================== Write API ====================

    function placeLimit(uint64 marketId, uint8 outcomeId, uint8 side, uint8 limitTick, uint128 sharesRequested)
        external
        whenNotPaused
        returns (uint32 orderId, uint128 filledShares, uint256 pointsTraded)
    {
        if (sharesRequested == 0) revert InvalidInput();
        if (side > 1) revert InvalidInput();
        TickLib.check(Tick.wrap(limitTick));

        UserId uid = _getOrRegister(msg.sender);
        return _placeLimit(uid, marketId, outcomeId, side, limitTick, sharesRequested);
    }

    function take(
        uint64 marketId,
        uint8 outcomeId,
        uint8 side,
        uint8 limitTick,
        uint128 sharesRequested,
        uint128 minFill
    ) external whenNotPaused returns (uint128 filledShares, uint256 pointsTraded) {
        if (sharesRequested == 0) revert InvalidInput();
        if (side > 1) revert InvalidInput();
        TickLib.check(Tick.wrap(limitTick));

        UserId uid = _getOrRegister(msg.sender);
        return _take(uid, marketId, outcomeId, side, limitTick, sharesRequested, minFill);
    }

    function cancel(uint64 marketId, uint8 outcomeId, uint8 side, uint32 orderId, uint32[] calldata prevCandidates)
        external
        whenNotPaused
        returns (uint128 cancelledShares)
    {
        if (prevCandidates.length > 16) revert TooManyCancelCandidates();
        if (side > 1) revert InvalidInput();

        UserId uid = _getOrRegister(msg.sender);
        return _cancel(uid, marketId, outcomeId, side, orderId, prevCandidates);
    }

    // ==================== Internal Helpers ====================

    function _setTradingViewModule(address module) internal {
        if (module == address(0)) revert InvalidInput();
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        s.tradingViewModule = module;
    }

    function _tradingViewModule() internal view returns (address) {
        return PlatformStorage.layout().tradingViewModule;
    }

    fallback() external {
        _delegateTradingViewFallback();
    }

    function _delegateTradingViewFallback() private {
        address impl = _tradingViewModule();
        if (impl == address(0)) revert InvalidInput();

        assembly {
            let ptr := mload(0x40)
            let dataLen := calldatasize()
            let dataPtr := add(ptr, 0x20)

            calldatacopy(dataPtr, 0, dataLen)

            let success := delegatecall(gas(), impl, dataPtr, dataLen, 0, 0)
            let size := returndatasize()

            mstore(ptr, size)
            returndatacopy(add(ptr, 0x20), 0, size)

            let newFree := add(ptr, and(add(add(size, 0x20), 0x1f), not(0x1f)))
            mstore(0x40, newFree)

            if iszero(success) {
                revert(add(ptr, 0x20), size)
            }

            return(add(ptr, 0x20), size)
        }
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(UPGRADER_ROLE) {
        _authorizeUpgradeImpl(newImplementation);
    }

    function _accessControlInit() internal override {
        __AccessControl_init();
    }

    function _grantRoleInternal(bytes32 role, address account) internal override {
        _grantRole(role, account);
    }

    function _revokeRoleInternal(bytes32 role, address account) internal override {
        _revokeRole(role, account);
    }

    function _pausableInit() internal override {
        __Pausable_init();
    }

    function _pauseInternal() internal override {
        _pause();
    }

    function _unpauseInternal() internal override {
        _unpause();
    }

    function _pausedInternal() internal view override returns (bool) {
        return paused();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, ERC1155Holder)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
