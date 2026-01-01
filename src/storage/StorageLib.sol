// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AppStorage} from "./Storage.sol";

/// @notice Canonical storage accessor.
/// Uses a single fixed slot for the entire app storage layout.
///
/// SECURITY / INVARIANT:
/// - This slot must never change for a deployed system.
/// - Storage layout in AppStorage is append-only.
library StorageLib {
    // Namespace this to your project. Changing this breaks storage compatibility.
    bytes32 internal constant SLOT = keccak256("socialwisdom.storage.v1");

    /// @notice Returns a pointer to the canonical AppStorage struct.
    function s() internal pure returns (AppStorage storage st) {
        bytes32 slot = SLOT;
        assembly {
            st.slot := slot
        }
    }
}
