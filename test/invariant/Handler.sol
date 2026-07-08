// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ArbiSmartV2} from "../../src/ArbiSmartV2.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract InvariantTestUSDC is ERC20 {
    constructor() ERC20("Invariant Test USDC", "itUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Bounded, randomized-action handler for ArbiSmartV2 invariant
///         testing. Deliberately scoped to the user-facing staking/referral
///         surface (stake/topUp/claim/earlyExit/claimRef) — the Polymarket
///         integration functions require a real Conditional Tokens
///         deployment to be meaningful and are covered separately by the
///         real, executed Hardhat-based end-to-end test (see
///         DEPLOYMENT.md / the validation report).
contract Handler is Test {
    ArbiSmartV2 public arbi;
    InvariantTestUSDC public usdc;
    address[] public actors;

    uint256 public ghost_sumActiveStakes;

    constructor(ArbiSmartV2 _arbi, InvariantTestUSDC _usdc) {
        arbi = _arbi;
        usdc = _usdc;
        for (uint256 i = 0; i < 6; i++) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", i)))));
            actors.push(actor);
            usdc.mint(actor, 1_000_000_000000); // 1,000,000 tUSDC each
            vm.prank(actor);
            usdc.approve(address(arbi), type(uint256).max);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function stake(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        (,,,,,, bool active, bool earlyExited,) = arbi.stakes(actor);
        if (active || earlyExited) return; // one stake per actor per lifetime, by design

        amount = bound(amount, 10_000000, 25_000_000000);
        if (arbi.isFreePeriod()) return; // skip free-period edge case in the handler for simplicity

        vm.prank(actor);
        try arbi.stake(amount, address(0)) {
            ghost_sumActiveStakes += amount;
        } catch {}
    }

    function claim(uint256 actorSeed, uint256 warpSeed) external {
        address actor = _actor(actorSeed);
        vm.warp(block.timestamp + bound(warpSeed, 1 hours, 5 days));
        vm.prank(actor);
        try arbi.claim() {} catch {}
    }

    function earlyExit(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        (uint256 amount,,,,,, bool active,,) = arbi.stakes(actor);
        if (!active) return;
        vm.prank(actor);
        try arbi.earlyExit() {
            ghost_sumActiveStakes -= amount;
        } catch {}
    }

    function claimRef(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        vm.prank(actor);
        try arbi.claimRef() {} catch {}
    }
}
