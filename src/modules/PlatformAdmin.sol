// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAdmin} from "../interfaces/IAdmin.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {UserId} from "../types/IdTypes.sol";
import {InvalidInput} from "../types/Errors.sol";
import {PlatformRoles} from "../types/Roles.sol";

/// @notice Internal admin helpers and role views.
abstract contract PlatformAdmin is PlatformRoles {
    bytes32 private constant _DEFAULT_ADMIN_ROLE = 0x00;

    function _accessControlInit() internal virtual;

    function _grantRoleInternal(bytes32 role, address account) internal virtual;

    function _revokeRoleInternal(bytes32 role, address account) internal virtual;

    function _pausableInit() internal virtual;

    function _pauseInternal() internal virtual;

    function _unpauseInternal() internal virtual;

    function _pausedInternal() internal view virtual returns (bool);

    // ==================== IAdmin ====================

    // ==================== Write API ====================

    function _setFeeExempt(UserId uid, address account, bool isExempt) internal {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        s.feeExempt[uid] = isExempt;
        emit IAdmin.FeeExemptionUpdated(account, isExempt);
    }

    function _pauseProtocol() internal {
        _pauseInternal();
    }

    function _unpauseProtocol() internal {
        _unpauseInternal();
    }

    // ==================== Read API ====================

    function _isPausedView() internal view returns (bool) {
        return _pausedInternal();
    }

    function _initializeOwner(address owner) internal {
        _accessControlInit();
        _pausableInit();

        _grantRoleInternal(_DEFAULT_ADMIN_ROLE, owner);
        _grantRoleInternal(PAUSER_ROLE, owner);
        _grantRoleInternal(UPGRADER_ROLE, owner);
        _grantRoleInternal(MARKET_CREATOR_ROLE, owner);

        PlatformStorage.Layout storage s = PlatformStorage.layout();
        s.protocolVersion = 1;
    }

    function _reinitializeV2() internal {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        s.protocolVersion = 2;
    }

    function _authorizeUpgradeImpl(address newImplementation) internal pure {
        if (newImplementation == address(0)) revert InvalidInput();
    }
}
