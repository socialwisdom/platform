// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library ConditionalTokensLib {
    using ConditionalTokensLib for IConditionalTokens;

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

    function buyBoth(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        bytes32 conditionId,
        uint256 amount
    ) internal {
        uint[] memory partition = new uint[](2);

        partition[0] = YES;
        partition[1] = NO;

        require(collateral.approve(address(conditionalTokens), amount), "collateral approve failed");

        conditionalTokens.splitPosition(collateral, bytes32(0), conditionId, partition, amount);
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
    ) internal {
        conditionalTokens.resolveQuestion(conditionId, true);
    }

    function resolveAsNo(
        IConditionalTokens conditionalTokens,
        bytes32 conditionId
    ) internal {
        conditionalTokens.resolveQuestion(conditionId, false);
    }

        // TODO: add fee here
    function resolveQuestion(
        IConditionalTokens conditionalTokens,
        bytes32 questionId,
        bool yesWon
    ) internal {
        uint256[] memory payouts = new uint256[](2);

        if (yesWon) {
            payouts[0] = 1;
            payouts[1] = 0;
        } else {
            payouts[0] = 0;
            payouts[1] = 1;
        }

        conditionalTokens.reportPayouts(questionId, payouts);
    }

    function redeemYes(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        bytes32 conditionId
    ) internal {
        conditionalTokens.redeemWinnings(collateral, conditionId, true);
    }

    function redeemNo(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        bytes32 conditionId
    ) internal {
        conditionalTokens.redeemWinnings(collateral, conditionId, false);
    }

    function redeemWinnings(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        bytes32 conditionId,
        bool yesWon
    ) internal {
        uint[] memory indexSets = new uint[](1);

        indexSets[0] = yesWon ? YES : NO;

        conditionalTokens.redeemPositions(collateral, bytes32(0), conditionId, indexSets);
    }
}
