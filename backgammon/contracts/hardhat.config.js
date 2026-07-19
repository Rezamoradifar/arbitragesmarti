require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const accounts = PRIVATE_KEY ? [PRIVATE_KEY] : [];

module.exports = {
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    hardhat: {},
    bscTestnet: {
      url: process.env.BSC_TESTNET_RPC_URL || "https://bsc-testnet-rpc.publicnode.com",
      chainId: 97,
      accounts,
    },
    bscMainnet: {
      url: process.env.BSC_MAINNET_RPC_URL || "https://bsc-dataseed.binance.org",
      chainId: 56,
      accounts,
    },
  },
  etherscan: {
    // Etherscan API V2: a single key works across all supported chains
    // (BscScan merged into the unified Etherscan multichain API).
    apiKey: process.env.BSCSCAN_API_KEY || "",
  },
  sourcify: {
    // Disabled: this plugin version only speaks Sourcify's old v1 API,
    // which is in a deprecation "brownout" until 2027. BscScan/Etherscan
    // verification below works fine on its own.
    enabled: false,
  },
};
