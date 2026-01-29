// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Protocol-level administration APIs.
interface IAdmin {
    // ==================== Events ====================

    /// @notice Emitted after fee exemption state changes.
    event FeeExemptionUpdated(address indexed account, bool isExempt);

    // ==================== Write API ====================

    /// @notice Set fee exemption status for an account (Owner only).
    function setFeeExempt(address account, bool isExempt) external;

    /// @notice Pause all state-changing actions.
    function pause() external;

    /// @notice Unpause all state-changing actions.
    function unpause() external;

    // ==================== Read API ====================

    /// @notice Check whether an account is fee-exempt.
    function isFeeExempt(address account) external view returns (bool);

    /// @notice Returns true if the protocol is paused.
    function isPaused() external view returns (bool);
}
