// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {ConditionalTokensLib} from "../libraries/ConditionalTokens.sol";
import {console2} from "forge-std/console2.sol";
import {Deploy} from "../libraries/Deploy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Platform} from "../src/Platform.sol";
import {TestsLib, TestPlatform, TestMarket, TestLevel, TestOrder} from "../libraries/Tests.sol";

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
    using TestsLib for TestPlatform;
    using TestsLib for TestMarket;
    using TestsLib for TestLevel;
    using TestsLib for TestOrder;

    using ConditionalTokensLib for IConditionalTokens;

    IConditionalTokens public conditionalTokens;
    USDC public usdc;
    TestPlatform public platform;

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

        require(usdc.transfer(address(0x101), 100_000), "transfer to 0x101 failed");
        require(usdc.transfer(address(0x202), 100_000), "transfer to 0x202 failed");

        console2.log("Balance of 0x42:", usdc.balanceOf(address(0x42)));
        console2.log("Balance of 0x101:", usdc.balanceOf(address(0x101)));
        console2.log("Balance of 0x202:", usdc.balanceOf(address(0x202)));

        platform = TestPlatform({platform: new Platform(), vm: vm});

        console2.log("Platform address:", address(platform.platform));

        Ownable(address(conditionalTokens)).transferOwnership(address(platform.platform));
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

    function test_platform_poc() public {
        uint256 marketId = platform.platform.createMarketWithOutcomes(conditionalTokens, usdc, ORACLE);

        TestMarket memory market = TestMarket({id: marketId, platform: platform.platform, vm: platform.vm});

        bytes32 conditionId = platform.platform.outcomes(marketId).conditionId;

        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(0x42)), 0);
        assertEq(conditionalTokens.balanceNoOf(usdc, conditionId, address(0x42)), 0);

        conditionalTokens.buyBoth(usdc, conditionId, 1_000);

        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(0x42)), 1_000);
        assertEq(conditionalTokens.balanceNoOf(usdc, conditionId, address(0x42)), 1_000);

        conditionalTokens.setApprovalForAll(address(platform.platform), true);

        TestOrder memory sellOrder = market.sell(40, 100);

        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(0x42)), 900);
        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(platform.platform)), 100);
        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(0x101)), 0);

        vm.startPrank(address(0x101));
        assertEq(usdc.balanceOf(address(0x101)), 100_000);

        require(usdc.approve(address(platform.platform), 40 * 30 / 100), "approve failed");

        market.buy(40, 30);

        assertEq(usdc.balanceOf(address(0x101)), 100_000 - 40 * 30 / 100);
        assertEq(usdc.balanceOf(address(0x42)), usdc.SUPPLY() - 200_000 - 1_000 + 40 * 30 / 100);

        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(0x42)), 900);
        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(platform.platform)), 70);
        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(0x101)), 30);

        vm.startPrank(address(0x42));
        platform.platform.closeMarketWithOutcomes(marketId, true);

        sellOrder.cancel();

        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(0x42)), 970);
        assertEq(conditionalTokens.balanceYesOf(usdc, conditionId, address(platform.platform)), 0);

        conditionalTokens.redeemYes(usdc, conditionId);
        assertEq(usdc.balanceOf(address(0x42)), usdc.SUPPLY() - 200_000 - 1_000 + 40 * 30 / 100 + 970);

        vm.startPrank(address(0x101));
        conditionalTokens.redeemYes(usdc, conditionId);

        // 100_018 == 18 profit
        assertEq(usdc.balanceOf(address(0x101)), 100_000 - 40 * 30 / 100 + 30);
    }
}
