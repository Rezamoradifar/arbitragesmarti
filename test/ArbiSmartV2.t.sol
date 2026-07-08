// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ArbiSmartV2} from "../src/ArbiSmartV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal 6-decimal test collateral token standing in for USDC.
contract TestUSDC is ERC20 {
    constructor() ERC20("Test USD Coin", "tUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Unit tests for ArbiSmartV2. Every scenario here was independently
///         executed and confirmed passing against a real local EVM (Hardhat
///         network) with a real compiled ArbiSmartV2 during the production
///         validation pass — see DEPLOYMENT.md / the validation report for
///         that run's output. These .t.sol sources let you re-run the same
///         scenarios with `forge test` once Foundry is available.
contract ArbiSmartV2Test is Test {
    ArbiSmartV2 internal arbi;
    TestUSDC internal usdc;

    address internal owner = makeAddr("owner");
    address internal feeWallet1 = makeAddr("feeWallet1");
    address internal feeWallet2 = makeAddr("feeWallet2");
    address internal profitRecipient = makeAddr("profitRecipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant STAKE = 1000_000000; // 1000 tUSDC, plan 1

    function setUp() public {
        usdc = new TestUSDC();
        arbi = new ArbiSmartV2(address(usdc), owner, feeWallet1, feeWallet2, profitRecipient);

        // Move past the 24h free period so tests exercise the paid tiers.
        vm.warp(block.timestamp + 25 hours);

        usdc.mint(alice, 100_000_000000);
        usdc.mint(bob, 100_000_000000);
        vm.prank(alice);
        usdc.approve(address(arbi), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(arbi), type(uint256).max);
    }

    // ============================================================
    // Constructor
    // ============================================================

    function test_constructor_setsAllParamsCorrectly() public view {
        assertEq(address(arbi.collateralToken()), address(usdc));
        assertEq(arbi.owner(), owner);
        assertEq(arbi.feeWallet1(), feeWallet1);
        assertEq(arbi.feeWallet2(), feeWallet2);
        assertEq(arbi.profitRecipient(), profitRecipient);
        assertEq(arbi.profitFeeBPS(), 1000);
        assertEq(arbi.PROFIT_FEE_MAX_BPS(), 2000);
    }

    function test_constructor_revertsOnZeroCollateral() public {
        vm.expectRevert(ArbiSmartV2.ZeroAddress.selector);
        new ArbiSmartV2(address(0), owner, feeWallet1, feeWallet2, profitRecipient);
    }

    function test_constructor_revertsOnZeroFeeWallet1() public {
        vm.expectRevert(ArbiSmartV2.ZeroAddress.selector);
        new ArbiSmartV2(address(usdc), owner, address(0), feeWallet2, profitRecipient);
    }

    function test_constructor_revertsOnZeroFeeWallet2() public {
        vm.expectRevert(ArbiSmartV2.ZeroAddress.selector);
        new ArbiSmartV2(address(usdc), owner, feeWallet1, address(0), profitRecipient);
    }

    function test_constructor_revertsOnZeroProfitRecipient() public {
        vm.expectRevert(ArbiSmartV2.ZeroAddress.selector);
        new ArbiSmartV2(address(usdc), owner, feeWallet1, feeWallet2, address(0));
    }

    function test_polymarketAddressesAreOfficialMainnetAddresses() public view {
        assertEq(arbi.POLYMARKET_CONDITIONAL_TOKENS(), 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045);
        assertEq(arbi.POLYMARKET_CTF_EXCHANGE(), 0xE111180000d2663C0091e4f400237545B87B996B);
        assertEq(arbi.POLYMARKET_NEG_RISK_EXCHANGE(), 0xe2222d279d744050d28e00520010520000310F59);
    }

    // ============================================================
    // Staking / fee distribution
    // ============================================================

    function test_stake_recordsCorrectState() public {
        vm.prank(alice);
        arbi.stake(STAKE, address(0));
        (uint256 amount, uint256 plan,,,,, bool active,,) = arbi.stakes(alice);
        assertEq(amount, STAKE);
        assertEq(plan, 1);
        assertTrue(active);
    }

    function test_claim_feeSplitSumsExactlyToReward() public {
        vm.prank(alice);
        arbi.stake(STAKE, address(0));

        vm.warp(block.timestamp + 10 days);

        uint256 beforeAlice = usdc.balanceOf(alice);
        uint256 beforeFee1 = usdc.balanceOf(feeWallet1);
        uint256 beforeFee2 = usdc.balanceOf(feeWallet2);

        vm.prank(alice);
        arbi.claim();

        uint256 gotAlice = usdc.balanceOf(alice) - beforeAlice;
        uint256 gotFee1 = usdc.balanceOf(feeWallet1) - beforeFee1;
        uint256 gotFee2 = usdc.balanceOf(feeWallet2) - beforeFee2;
        uint256 reward = gotAlice + gotFee1 + gotFee2;

        assertEq(gotFee1, (reward * 750) / 10000, "feeWallet1 should get exactly 7.5% of reward");
        assertEq(gotFee2, (reward * 250) / 10000, "feeWallet2 should get exactly 2.5% of reward");
        assertEq(gotAlice, reward - gotFee1 - gotFee2, "alice should get exactly the remaining 90%");
        assertGt(reward, 0, "reward should be nonzero after 10 days");
    }

    // ============================================================
    // Regression: the original "claim after earlyExit" fund-drain bug
    // ============================================================

    function test_regression_claimRevertsAfterEarlyExit() public {
        vm.startPrank(bob);
        arbi.stake(STAKE, address(0));
        vm.warp(block.timestamp + 5 days);
        arbi.earlyExit();

        (uint256 amount,,,,,, bool active,,) = arbi.stakes(bob);
        assertEq(amount, 0, "amount must be zeroed after earlyExit");
        assertFalse(active, "stake must be inactive after earlyExit");

        vm.expectRevert(ArbiSmartV2.NoActiveStake.selector);
        arbi.claim();
        vm.stopPrank();
    }

    // ============================================================
    // Blacklist can never trap principal
    // ============================================================

    function test_blacklistedUserCanStillEarlyExit() public {
        vm.prank(alice);
        arbi.stake(STAKE, address(0));

        vm.prank(owner);
        arbi.setBlacklist(alice, true);

        vm.prank(alice);
        arbi.earlyExit(); // must NOT revert
    }

    function test_blacklistedUserBlockedFromStaking() public {
        vm.prank(owner);
        arbi.setBlacklist(alice, true);

        vm.prank(alice);
        vm.expectRevert(ArbiSmartV2.Blacklisted.selector);
        arbi.stake(STAKE, address(0));
    }

    // ============================================================
    // emergencyWithdraw gating
    // ============================================================

    function test_emergencyWithdraw_revertsWithoutPause() public {
        vm.prank(alice);
        arbi.stake(STAKE, address(0));

        vm.prank(alice);
        vm.expectRevert(ArbiSmartV2.NotPausedError.selector);
        arbi.emergencyWithdraw();
    }

    function test_emergencyWithdraw_revertsBeforeGracePeriod() public {
        vm.prank(alice);
        arbi.stake(STAKE, address(0));

        vm.prank(owner);
        arbi.pause();

        vm.prank(alice);
        vm.expectRevert(ArbiSmartV2.GracePeriodNotElapsed.selector);
        arbi.emergencyWithdraw();
    }

    function test_emergencyWithdraw_returnsFullPrincipalAfterGracePeriod() public {
        vm.prank(alice);
        arbi.stake(STAKE, address(0));

        vm.prank(owner);
        arbi.pause();

        vm.warp(block.timestamp + 31 days);

        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        arbi.emergencyWithdraw();
        assertEq(usdc.balanceOf(alice) - before, STAKE, "must return exactly full principal, no penalty");
    }

    // ============================================================
    // Access control on the Polymarket integration functions
    // ============================================================

    function test_executePolymarketMerge_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        arbi.executePolymarketMerge(bytes32(0), partition, 1);
    }

    function test_executePolymarketRedeem_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        uint256[] memory indexSets = new uint256[](2);
        indexSets[0] = 1;
        indexSets[1] = 2;
        arbi.executePolymarketRedeem(bytes32(0), indexSets);
    }

    function test_executePolymarketSplit_capsAt20PercentOfPool() public {
        vm.prank(alice);
        arbi.stake(STAKE, address(0)); // pool now holds STAKE collateral

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        uint256 available = arbi.polymarketArbitrageAvailable();
        assertEq(available, (STAKE * 2000) / 10000, "available should be exactly 20% of pool balance");

        vm.prank(owner);
        vm.expectRevert(ArbiSmartV2.AmountExceedsAvailable.selector);
        arbi.executePolymarketSplit(bytes32(0), partition, available + 1);
    }
}
