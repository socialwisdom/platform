// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAccounting} from "../interfaces/IAccounting.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {Market} from "../types/Structs.sol";
import {UserId} from "../types/IdTypes.sol";
import {InvalidInput, MarketNotFound, UnregisteredUser} from "../types/Errors.sol";

import {Accounting} from "../core/Accounting.sol";
import {Fees} from "../core/Fees.sol";
import {Markets} from "../core/Markets.sol";

/// @notice Internal accounting, registry, and fee accrual logic.
abstract contract PlatformAccounting {
    // ==================== Internal Helpers ====================

    function _getOrRegister(address user) internal returns (UserId uid) {
        uid = UserId.wrap(_userIdOf(user));
        if (UserId.unwrap(uid) != 0) return uid;
        return UserId.wrap(_register(user));
    }

    function _requireRegistered(address user) internal view returns (UserId uid) {
        uid = UserId.wrap(_userIdOf(user));
        if (UserId.unwrap(uid) == 0) revert UnregisteredUser();
    }

    // ==================== IAccounting ====================

    // ==================== Write API ====================

    function _register(address user) internal returns (uint64 id) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        UserId next = s.nextUserId;
        if (UserId.unwrap(next) == 0) next = UserId.wrap(1);

        id = UserId.unwrap(next);

        s.userIdOf[user] = UserId.wrap(id);
        s.userOfId[UserId.wrap(id)] = user;
        s.nextUserId = UserId.wrap(id + 1);
        emit IAccounting.UserRegistered(user, id);
    }

    function _sweepMarketFees(uint64 marketId)
        internal
        returns (uint128 protocolFeesPoints, uint128 creatorFeesPoints)
    {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _accountingRequireMarketExists(marketId);

        Market storage m = s.markets[marketId];
        // Unclaimed trading fees for this market (not yet split with creator).
        uint128 totalFees = m.tradingFeesPoints;
        if (totalFees == 0) return (0, 0);

        m.tradingFeesPoints = 0;

        creatorFeesPoints = m.creatorFeeBps == 0 ? 0 : Fees.computeFee(totalFees, m.creatorFeeBps);
        protocolFeesPoints = totalFees - creatorFeesPoints;

        if (creatorFeesPoints > 0) {
            Accounting.addFreePoints(s, UserId.wrap(m.creatorId), creatorFeesPoints);
        }

        if (protocolFeesPoints > 0) {
            uint256 newProtocolFees = uint256(s.protocolFeesPoints) + uint256(protocolFeesPoints);
            if (newProtocolFees > type(uint128).max) revert InvalidInput();
            // forge-lint: disable-next-line(unsafe-typecast)
            s.protocolFeesPoints = uint128(newProtocolFees);
        }

        emit IAccounting.MarketFeesSwept(marketId, protocolFeesPoints, creatorFeesPoints);
        return (protocolFeesPoints, creatorFeesPoints);
    }

    // ==================== Read API ====================

    function _userIdOf(address user) internal view returns (uint64) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return UserId.unwrap(s.userIdOf[user]);
    }

    function _userOfId(uint64 id) internal view returns (address) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return s.userOfId[UserId.wrap(id)];
    }

    function _getMarketTradingFeesPoints(uint64 marketId) internal view returns (uint128) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        _accountingRequireMarketExists(marketId);
        // Unclaimed trading fees for this market (not yet split with creator).
        return s.markets[marketId].tradingFeesPoints;
    }

    function _getProtocolDustPoints() internal view returns (uint128) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return s.protocolDustPoints;
    }

    function _getProtocolFeesPoints() internal view returns (uint128) {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        return s.protocolFeesPoints;
    }

    function _accountingRequireMarketExists(uint64 marketId) internal view {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        if (!Markets.exists(s, marketId)) revert MarketNotFound(marketId);
    }
}
