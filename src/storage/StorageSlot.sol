// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PlatformStorage} from "./PlatformStorage.sol";

/// @notice Canonical storage slot accessor.
/// Uses a single fixed slot for the entire app storage layout.
///
/// SECURITY / INVARIANT:
/// - This slot must never change for a deployed system.
/// - Storage layout in PlatformStorage is append-only.
library StorageSlot {
    // Namespace this to your project. Changing this breaks storage compatibility.
    bytes32 internal constant SLOT = keccak256("socialwisdom.storage.v1");

    /// @notice Returns a pointer to the canonical PlatformStorage struct.
    function layout() internal pure returns (PlatformStorage storage st) {
        bytes32 slot = SLOT;
        assembly {
            st.slot := slot
        }
    }
}
