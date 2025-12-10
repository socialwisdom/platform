// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {console2} from "forge-std/console2.sol";
import {Deploy} from "../libraries/Deploy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

contract USDC is ERC20 {
    uint256 public constant dec = 18;
    uint256 public constant tokens = 10 ** dec;

    uint256 public constant initSupply = 1_000_000 * tokens;

    constructor() ERC20("TestToken", "TT") {
        _mint(msg.sender, initSupply);
    }

    function decimals() public pure override returns (uint8) {
        return uint8(dec);
    }
}

contract ConditionalTokensTest is Test {
    IConditionalTokens public conditionalTokens;
    USDC public usdc;

    address public constant oracle = address(0x09ac1e);

    function setUp() public {
        vm.startPrank(address(0x42));

        console2.log("Oracle address:", oracle);

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
        bytes32 conditionId = conditionalTokens.getConditionId(oracle, questionId, outcomeSlotCount);

        vm.expectEmit();
        emit IConditionalTokens.ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);

        conditionalTokens.prepareCondition(oracle, questionId, outcomeSlotCount);

        vm.stopPrank();
        vm.prank(oracle);
        vm.expectRevert();
        conditionalTokens.prepareCondition(oracle, bytes32(uint256(2)), outcomeSlotCount);
        vm.startPrank(address(0x42));

        bytes32 parentCollectionId = bytes32(0);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // 0b01
        partition[1] = 2; // 0b10

        usdc.approve(address(conditionalTokens), 1_000 * usdc.tokens());

        conditionalTokens.splitPosition(usdc, parentCollectionId, conditionId, partition, 1_000 * usdc.tokens());

        assertEq(usdc.balanceOf(address(0x42)), usdc.initSupply() - 1_000 * usdc.tokens());

        uint256 yes = conditionalTokens.getPositionId(
            usdc, conditionalTokens.getCollectionId(parentCollectionId, conditionId, 1)
        );
        uint256 no = conditionalTokens.getPositionId(
            usdc, conditionalTokens.getCollectionId(parentCollectionId, conditionId, 2)
        );
        uint256 yesNo = conditionalTokens.getPositionId(
            usdc, conditionalTokens.getCollectionId(parentCollectionId, conditionId, 3)
        );

        assertEq(conditionalTokens.balanceOf(address(0x42), yes), 1_000 * usdc.tokens());
        assertEq(conditionalTokens.balanceOf(address(0x42), no), 1_000 * usdc.tokens());
        assertEq(conditionalTokens.balanceOf(address(0x42), yesNo), 0);

        conditionalTokens.safeTransferFrom(address(0x42), address(0x137), yes, 500 * usdc.tokens(), "");

        assertEq(conditionalTokens.balanceOf(address(0x42), yes), 500 * usdc.tokens());
        assertEq(conditionalTokens.balanceOf(address(0x137), yes), 500 * usdc.tokens());
        assertEq(conditionalTokens.balanceOf(address(0x42), no), 1_000 * usdc.tokens());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.stopPrank();
        vm.prank(oracle);

        vm.expectEmit();
        emit IConditionalTokens.ConditionResolution(conditionId, oracle, questionId, outcomeSlotCount, payouts);

        conditionalTokens.reportPayouts(questionId, payouts);

        vm.startPrank(address(0x42));

        uint256[] memory indexSets = new uint256[](1);

        indexSets[0] = 2; // No

        vm.expectEmit();
        emit IConditionalTokens.PayoutRedemption(address(0x42), usdc, parentCollectionId, conditionId, indexSets, 0);

        conditionalTokens.redeemPositions(usdc, parentCollectionId, conditionId, indexSets);

        assertEq(conditionalTokens.balanceOf(address(0x42), yes), 500 * usdc.tokens());
        assertEq(conditionalTokens.balanceOf(address(0x42), no), 0);
        assertEq(usdc.balanceOf(address(0x42)), usdc.initSupply() - 1_000 * usdc.tokens());

        indexSets[0] = 1; // Yes

        vm.expectEmit();
        emit IConditionalTokens.PayoutRedemption(
            address(0x42), usdc, parentCollectionId, conditionId, indexSets, 500 * usdc.tokens()
        );

        conditionalTokens.redeemPositions(usdc, parentCollectionId, conditionId, indexSets);

        assertEq(conditionalTokens.balanceOf(address(0x42), yes), 0);
        assertEq(conditionalTokens.balanceOf(address(0x42), no), 0);
        assertEq(usdc.balanceOf(address(0x42)), usdc.initSupply() - 500 * usdc.tokens());

        vm.stopPrank();
        vm.startPrank(address(0x137));

        assertEq(usdc.balanceOf(address(0x137)), 0);

        indexSets[0] = 1; // Yes
        conditionalTokens.redeemPositions(usdc, parentCollectionId, conditionId, indexSets);
        assertEq(usdc.balanceOf(address(0x137)), 500 * usdc.tokens());
    }
}
