// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../src/Platform.sol";
import {IPlatform} from "../src/interfaces/IPlatform.sol";
import {MarketState, Side} from "../src/types/Enums.sol";
import {
    MarketNotActive,
    MarketNotResolved,
    MarketResolveTooEarly,
    MarketAlreadyFinalized,
    MarketFinalizeTooEarly,
    Unauthorized
} from "../src/types/Errors.sol";

contract MarketsTest is Test {
    Platform internal platform;

    address internal owner = address(this);
    address internal resolver = address(0xBEEF);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        platform = new Platform();
    }

    function _createMarket(address marketResolver, uint64 expirationAt, bool allowEarlyResolve)
        internal
        returns (uint64 marketId)
    {
        string[] memory labels = new string[](2);
        labels[0] = "Yes";
        labels[1] = "No";

        marketId = platform.createMarket(
            marketResolver, 2, expirationAt, allowEarlyResolve, bytes32(0), bytes32(0), bytes32(0), "Q", labels, "Rules"
        );
    }

    function test_CreateMarket_IncrementsAndEmits() public {
        string[] memory labels = new string[](2);
        labels[0] = "Yes";
        labels[1] = "No";

        vm.expectEmit(true, true, true, true);
        emit IPlatform.MarketCreated(1, 1, 2, 0, true, bytes32(0), bytes32(0), "Q", labels, "Rules");

        uint64 first =
            platform.createMarket(resolver, 2, 0, true, bytes32(0), bytes32(0), bytes32(0), "Q", labels, "Rules");

        uint64 second = _createMarket(resolver, 0, true);

        assertEq(first, 1);
        assertEq(second, 2);
    }

    function test_MarketState_Derivation() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 100), true);

        assertEq(platform.getMarketState(marketId), uint8(MarketState.Active));

        vm.warp(block.timestamp + 200);
        assertEq(platform.getMarketState(marketId), uint8(MarketState.Expired));

        vm.prank(resolver);
        platform.resolveMarket(marketId, 1);
        assertEq(platform.getMarketState(marketId), uint8(MarketState.ResolvedPending));

        vm.warp(block.timestamp + platform.RESOLVE_FINALIZE_DELAY());
        vm.prank(resolver);
        platform.finalizeMarket(marketId);
        assertEq(platform.getMarketState(marketId), uint8(MarketState.ResolvedFinal));
    }

    function test_MarketState_ResolutionOverridesExpiration() public {
        vm.warp(100);
        uint64 marketId = _createMarket(resolver, 99, true);

        assertEq(platform.getMarketState(marketId), uint8(MarketState.Expired));

        vm.prank(resolver);
        platform.resolveMarket(marketId, 0);

        assertEq(platform.getMarketState(marketId), uint8(MarketState.ResolvedPending));
    }

    function test_Gating_PlaceLimitTakeOnlyActive_CancelAlways() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 1), true);

        // Setup user
        vm.startPrank(alice);
        platform.register();
        platform.deposit(1_000_000);
        platform.depositShares(marketId, 0, 1_000_000);
        vm.stopPrank();

        // Place while active
        vm.prank(alice);
        (uint32 orderId,,) = platform.placeLimit(marketId, 0, uint8(Side.Ask), 50, 100);

        // Expire market
        vm.warp(block.timestamp + 10);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarketNotActive.selector, marketId));
        platform.placeLimit(marketId, 0, uint8(Side.Ask), 50, 100);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarketNotActive.selector, marketId));
        platform.take(marketId, 0, uint8(Side.Ask), 50, 100, 1);

        vm.prank(alice);
        platform.cancel(marketId, 0, uint8(Side.Ask), orderId, new uint32[](0));
    }

    function test_ResolverOnly_Access() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 100), true);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        platform.resolveMarket(marketId, 1);

        vm.prank(resolver);
        platform.resolveMarket(marketId, 1);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        platform.finalizeMarket(marketId);
    }

    function test_FinalizeRequiresPending() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 100), true);

        vm.prank(resolver);
        vm.expectRevert(abi.encodeWithSelector(MarketNotResolved.selector, marketId));
        platform.finalizeMarket(marketId);
    }

    function test_ResolveRespectsAllowEarlyResolve() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 100), false);

        vm.prank(resolver);
        vm.expectRevert(abi.encodeWithSelector(MarketResolveTooEarly.selector, marketId, uint64(block.timestamp + 100)));
        platform.resolveMarket(marketId, 0);

        vm.warp(block.timestamp + 200);
        vm.prank(resolver);
        platform.resolveMarket(marketId, 0);
    }

    function test_FinalizeCannotRepeat() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 100), true);

        vm.prank(resolver);
        platform.resolveMarket(marketId, 0);
        vm.warp(block.timestamp + platform.RESOLVE_FINALIZE_DELAY());
        vm.prank(resolver);
        platform.finalizeMarket(marketId);

        vm.prank(resolver);
        vm.expectRevert(abi.encodeWithSelector(MarketAlreadyFinalized.selector, marketId));
        platform.finalizeMarket(marketId);
    }

    function test_FinalizeRequiresDelay() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 100), true);

        vm.prank(resolver);
        platform.resolveMarket(marketId, 0);

        uint64 earliest = uint64(block.timestamp) + platform.RESOLVE_FINALIZE_DELAY();
        vm.prank(resolver);
        vm.expectRevert(abi.encodeWithSelector(MarketFinalizeTooEarly.selector, marketId, earliest));
        platform.finalizeMarket(marketId);

        vm.warp(earliest);
        vm.prank(resolver);
        platform.finalizeMarket(marketId);
    }

    function test_ResolveCanUpdateBeforeFinal() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 100), true);

        vm.prank(resolver);
        platform.resolveMarket(marketId, 0);

        vm.prank(resolver);
        platform.resolveMarket(marketId, 1);

        (,,,,,,,, bool resolved, bool finalized, uint8 winningOutcomeId) = platform.getMarket(marketId);
        assertTrue(resolved);
        assertFalse(finalized);
        assertEq(winningOutcomeId, 1);
    }

    function test_ResolveAfterFinalizedReverts() public {
        uint64 marketId = _createMarket(resolver, uint64(block.timestamp + 100), true);

        vm.prank(resolver);
        platform.resolveMarket(marketId, 0);
        vm.warp(block.timestamp + platform.RESOLVE_FINALIZE_DELAY());
        vm.prank(resolver);
        platform.finalizeMarket(marketId);

        vm.prank(resolver);
        vm.expectRevert(abi.encodeWithSelector(MarketAlreadyFinalized.selector, marketId));
        platform.resolveMarket(marketId, 1);
    }
}
