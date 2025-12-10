// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GnosisCTFProxy} from "./GnosisProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ConditionalTokens is Ownable, GnosisCTFProxy {
    constructor(address _impl) Ownable(msg.sender) GnosisCTFProxy(_impl) {}

    // @dev: Patched with onlyOwner access control to restrict condition preparation.
    function prepareCondition(address, bytes32, uint256) external override onlyOwner {
        _delegate();
    }

    // @dev: Patched to include a winner fee.
    function reportPayouts(bytes32, uint256[] calldata) external override {
        // FIXME: implement fee logic here
        _delegate();
    }

    // @dev: Patched to forbid merging positions after payouts have been reported.
    function mergePositions(IERC20, bytes32, bytes32 conditionId, uint256[] calldata, uint256) external override {
        require(_payoutDenominator[conditionId] == 0, "Cannot merge positions after payouts are reported");
        _delegate();
    }
}
