// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAdmin} from "../interfaces/IAdmin.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {UserId} from "../types/IdTypes.sol";
import {InvalidInput} from "../types/Errors.sol";

/// @notice Internal admin helpers and role views.
abstract contract PlatformAdmin {
    function _ownableInit(address owner) internal virtual;

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

    function _initializeOwner(address owner, UserId ownerId) internal {
        _ownableInit(owner);
        _pausableInit();

        PlatformStorage.Layout storage s = PlatformStorage.layout();
        s.marketCreator[ownerId] = true;
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
