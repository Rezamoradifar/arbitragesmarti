// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ArbiSmartV2} from "../src/ArbiSmartV2.sol";

/**
 * @title Deploy
 * @notice Deploys {ArbiSmartV2} to Polygon mainnet (chain id 137).
 *
 * Usage (see README.md for the full walkthrough):
 *
 *   forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url polygon \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * All parameters are read from environment variables (see .env.example) so
 * that no addresses or keys are hardcoded in source. `--verify` triggers
 * Foundry's built-in PolygonScan verification immediately after the
 * broadcast succeeds, using the [etherscan] config in foundry.toml. If
 * verification during the broadcast fails (e.g. PolygonScan has not yet
 * indexed the transaction), re-run verification standalone with
 * `forge verify-contract` — see README.md for the exact command,
 * including how to pass the ABI-encoded constructor arguments.
 */
contract Deploy is Script {
    function run() external returns (ArbiSmartV2 deployed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address feeWallet1 = vm.envAddress("FEE_WALLET_1");
        address feeWallet2 = vm.envAddress("FEE_WALLET_2");
        address profitRecipient = vm.envAddress("PROFIT_RECIPIENT");

        console2.log("Deploying ArbiSmartV2 with parameters:");
        console2.log("  collateralToken: ", collateralToken);
        console2.log("  initialOwner:    ", initialOwner);
        console2.log("  feeWallet1:      ", feeWallet1);
        console2.log("  feeWallet2:      ", feeWallet2);
        console2.log("  profitRecipient: ", profitRecipient);

        require(collateralToken != address(0), "COLLATERAL_TOKEN not set");
        require(initialOwner != address(0), "INITIAL_OWNER not set");
        require(feeWallet1 != address(0), "FEE_WALLET_1 not set");
        require(feeWallet2 != address(0), "FEE_WALLET_2 not set");
        require(profitRecipient != address(0), "PROFIT_RECIPIENT not set");

        vm.startBroadcast(deployerPrivateKey);

        deployed = new ArbiSmartV2(collateralToken, initialOwner, feeWallet1, feeWallet2, profitRecipient);

        vm.stopBroadcast();

        console2.log("ArbiSmartV2 deployed at:", address(deployed));
        console2.log("Verify owner():", deployed.owner());
        console2.log("Verify collateralToken():", address(deployed.collateralToken()));
        console2.log("Verify profitRecipient():", deployed.profitRecipient());
    }
}
