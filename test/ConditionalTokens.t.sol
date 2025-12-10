// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {console2} from "forge-std/console2.sol";
import {Deploy} from "../libraries/Deploy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {Test} from "forge-std/Test.sol";

contract USDC is ERC20 {
    uint256 public constant TOKENS = 10 ** 18;
    uint256 public constant SUPPLY = 1_000_000 * TOKENS;

    constructor() ERC20("TestToken", "TT") {
        _mint(msg.sender, SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

contract ConditionalTokensTest is Test {
    IConditionalTokens public conditionalTokens;
    USDC public usdc;

    address public constant ORACLE = address(0x09ac1e);

    function setUp() public {
        vm.startPrank(address(0x42));

        console2.log("Oracle address:", ORACLE);

        conditionalTokens = Deploy.conditionalTokens();
        console2.log("CT impl address:", address(conditionalTokens));

        conditionalTokens = IConditionalTokens(address(new ConditionalTokens(address(conditionalTokens))));

        console2.log("CT address:", address(conditionalTokens));

        usdc = new USDC();

        console2.log("USDC address:", address(usdc));
        console2.log("Balance of 0x42:", usdc.balanceOf(address(0x42)));
    }

    function test_conditionalTokens_poc() public {
        bytes32 questionId = bytes32(uint256(1));
        uint256 outcomeSlotCount = 2;
        bytes32 conditionId = conditionalTokens.getConditionId(ORACLE, questionId, outcomeSlotCount);

        vm.expectEmit();
        emit IConditionalTokens.ConditionPreparation(conditionId, ORACLE, questionId, outcomeSlotCount);

        conditionalTokens.prepareCondition(ORACLE, questionId, outcomeSlotCount);

        vm.stopPrank();

        vm.prank(ORACLE);
        vm.expectRevert();
        conditionalTokens.prepareCondition(ORACLE, bytes32(uint256(2)), outcomeSlotCount);
        vm.startPrank(address(0x42));

        bytes32 parentCollectionId = bytes32(0);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // 0b01
        partition[1] = 2; // 0b10

        usdc.approve(address(conditionalTokens), 1_000 * usdc.TOKENS());

        conditionalTokens.splitPosition(usdc, parentCollectionId, conditionId, partition, 1_000 * usdc.TOKENS());

        assertEq(usdc.balanceOf(address(0x42)), usdc.SUPPLY() - 1_000 * usdc.TOKENS());
        uint256 yes = conditionalTokens.getPositionId(
            usdc, conditionalTokens.getCollectionId(parentCollectionId, conditionId, 1)
        );
        uint256 no = conditionalTokens.getPositionId(
            usdc, conditionalTokens.getCollectionId(parentCollectionId, conditionId, 2)
        );
        uint256 yesNo = conditionalTokens.getPositionId(
            usdc, conditionalTokens.getCollectionId(parentCollectionId, conditionId, 3)
        );

        assertEq(conditionalTokens.balanceOf(address(0x42), yes), 1_000 * usdc.TOKENS());
        assertEq(conditionalTokens.balanceOf(address(0x42), no), 1_000 * usdc.TOKENS());
        assertEq(conditionalTokens.balanceOf(address(0x42), yesNo), 0);

        conditionalTokens.safeTransferFrom(address(0x42), address(0x137), yes, 500 * usdc.TOKENS(), "");
        assertEq(conditionalTokens.balanceOf(address(0x42), yes), 500 * usdc.TOKENS());
        assertEq(conditionalTokens.balanceOf(address(0x137), yes), 500 * usdc.TOKENS());
        assertEq(conditionalTokens.balanceOf(address(0x42), no), 1_000 * usdc.TOKENS());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.stopPrank();
        vm.prank(ORACLE);

        vm.expectEmit();
        emit IConditionalTokens.ConditionResolution(conditionId, ORACLE, questionId, outcomeSlotCount, payouts);

        conditionalTokens.reportPayouts(questionId, payouts);

        vm.startPrank(address(0x42));

        uint256[] memory indexSets = new uint256[](1);

        indexSets[0] = 2; // No

        vm.expectEmit();
        emit IConditionalTokens.PayoutRedemption(address(0x42), usdc, parentCollectionId, conditionId, indexSets, 0);

        conditionalTokens.redeemPositions(usdc, parentCollectionId, conditionId, indexSets);

        assertEq(conditionalTokens.balanceOf(address(0x42), yes), 500 * usdc.TOKENS());
        assertEq(conditionalTokens.balanceOf(address(0x42), no), 0);
        assertEq(usdc.balanceOf(address(0x42)), usdc.SUPPLY() - 1_000 * usdc.TOKENS());

        indexSets[0] = 1; // Yes

        vm.expectEmit();
        emit IConditionalTokens.PayoutRedemption(
            address(0x42), usdc, parentCollectionId, conditionId, indexSets, 500 * usdc.TOKENS()
        );

        conditionalTokens.redeemPositions(usdc, parentCollectionId, conditionId, indexSets);

        assertEq(conditionalTokens.balanceOf(address(0x42), yes), 0);
        assertEq(conditionalTokens.balanceOf(address(0x42), no), 0);
        assertEq(usdc.balanceOf(address(0x42)), usdc.SUPPLY() - 500 * usdc.TOKENS());

        vm.stopPrank();
        vm.startPrank(address(0x137));

        assertEq(usdc.balanceOf(address(0x137)), 0);

        indexSets[0] = 1; // Yes
        conditionalTokens.redeemPositions(usdc, parentCollectionId, conditionId, indexSets);
        assertEq(usdc.balanceOf(address(0x137)), 500 * usdc.TOKENS());
    }
}
