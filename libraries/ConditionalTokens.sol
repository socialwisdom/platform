// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library ConditionalTokensLibrary {
    using ConditionalTokensLibrary for IConditionalTokens;

    uint constant internal YES = 1; // 0b01;
    uint constant internal NO = 2;  // 0b10;

    // TODO: consider deadline timestamp
    function createBinaryCondition(
        IConditionalTokens conditionalTokens,
        uint256 marketId
    ) internal returns (bytes32) {
        return conditionalTokens.createBinaryCondition(address(this), bytes32(marketId));
    }

    function createBinaryCondition(
        IConditionalTokens conditionalTokens,
        address oracle,
        bytes32 questionId
    ) internal returns (bytes32) {
        conditionalTokens.prepareCondition(oracle, questionId, 2);

        return conditionalTokens.getConditionId(oracle, questionId, 2);
    }

    function balanceYes(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        bytes32 conditionId
    ) internal view returns (uint256) {
        return conditionalTokens.balanceYesOf(collateral, conditionId, msg.sender);
    }

    function balanceYesOf(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        bytes32 conditionId,
        address owner
    ) internal view returns (uint256) {
        return conditionalTokens.balanceOf(owner, conditionalTokens.getPositionId(
            collateral, conditionalTokens.getCollectionId(bytes32(0), conditionId, YES)
        ));
    }

    function balanceNo(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        bytes32 conditionId
    ) internal view returns (uint256) {
        return conditionalTokens.balanceNoOf(collateral, conditionId, msg.sender);
    }

    function balanceNoOf(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        bytes32 conditionId,
        address owner
    ) internal view returns (uint256) {
        return conditionalTokens.balanceOf(owner, conditionalTokens.getPositionId(
            collateral, conditionalTokens.getCollectionId(bytes32(0), conditionId, NO)
        ));
    }

    function resolveAsYes(
        IConditionalTokens conditionalTokens,
        bytes32 conditionId
        // TODO: add fee here
    ) internal {
        conditionalTokens.resolveCondition(conditionId, true);
    }

    function resolveAsNo(
        IConditionalTokens conditionalTokens,
        bytes32 conditionId
        // TODO: add fee here
    ) internal {
        conditionalTokens.resolveCondition(conditionId, false);
    }

    function resolveCondition(
        IConditionalTokens conditionalTokens,
        bytes32 conditionId,
        bool yesWon
        // TODO: add fee here
    ) internal {
        uint256[] memory payouts = new uint256[](2);

        if (yesWon) {
            payouts[0] = 1;
            payouts[1] = 0;
        } else {
            payouts[0] = 0;
            payouts[1] = 1;
        }

        conditionalTokens.reportPayouts(conditionId, payouts);
    }
}
