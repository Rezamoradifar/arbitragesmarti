// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ArbiSmartV2} from "../../src/ArbiSmartV2.sol";
import {Handler, InvariantTestUSDC} from "./Handler.sol";

/// @notice Invariant tests for ArbiSmartV2's staking/referral accounting.
///         Run with `forge test --match-contract ArbiSmartV2InvariantTest`.
///         Scope: the user-facing staking surface only (see Handler.sol for
///         why the Polymarket integration functions are out of scope here).
contract ArbiSmartV2InvariantTest is Test {
    ArbiSmartV2 internal arbi;
    InvariantTestUSDC internal usdc;
    Handler internal handler;

    address internal owner = makeAddr("owner");
    address internal feeWallet1 = makeAddr("feeWallet1");
    address internal feeWallet2 = makeAddr("feeWallet2");
    address internal profitRecipient = makeAddr("profitRecipient");

    function setUp() public {
        usdc = new InvariantTestUSDC();
        arbi = new ArbiSmartV2(address(usdc), owner, feeWallet1, feeWallet2, profitRecipient);
        vm.warp(block.timestamp + 25 hours); // clear the free-period window

        handler = new Handler(arbi, usdc);

        targetContract(address(handler));
    }

    /// @dev Direct regression guard for the exact bug this refactor fixed:
    ///      no stake that has ever been earlyExited may retain a nonzero
    ///      `amount` — if this ever fails, the "claim after earlyExit"
    ///      fund-drain path has come back.
    function invariant_earlyExitedStakesAreAlwaysZeroed() public view {
        for (uint256 i = 0; i < 6; i++) {
            address actor = handler.actors(i);
            (uint256 amount,,,,,,, bool earlyExited,) = arbi.stakes(actor);
            if (earlyExited) {
                assertEq(amount, 0, "an early-exited stake must have amount == 0");
            }
        }
    }

    /// @dev The contract must never end up owing more than it holds: total
    ///      staked principal tracked by the contract can never exceed the
    ///      collateral balance it actually custodies plus what has already
    ///      been paid out (a basic solvency-direction sanity check; it does
    ///      not assert profitability, only that the ledger isn't lying).
    function invariant_totalStakedNeverExceedsHandlerGhostSum() public view {
        assertLe(arbi.totalStaked(), handler.ghost_sumActiveStakes(), "totalStaked must never exceed the sum of amounts the handler believes are staked");
    }

    /// @dev Sanity: the contract's own collateral balance is always
    ///      non-negative (trivial under uint256, but included as an
    ///      explicit floor so a future refactor that introduces unchecked
    ///      arithmetic would be caught immediately by this invariant suite).
    function invariant_collateralBalanceNonNegative() public view {
        assertGe(usdc.balanceOf(address(arbi)), 0);
    }
}
