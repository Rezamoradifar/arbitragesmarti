export const RATING_REGISTRY_ADDRESS = {
  97: import.meta.env.VITE_RATING_ADDRESS_TESTNET || "0xF07fe39C8532e3b714cfDFFCee28bcC9603F7092",
  56: import.meta.env.VITE_RATING_ADDRESS_MAINNET || "0xF07fe39C8532e3b714cfDFFCee28bcC9603F7092",
};

// Block the contract was deployed at (conservative lower bound) -- keeps
// getLogs() scans for the leaderboard from having to walk the whole chain.
export const RATING_REGISTRY_DEPLOY_BLOCK = {
  97: 120003833n,
  56: 110860908n,
};

export const DEFAULT_RATING = 1000;

export const RATING_REGISTRY_ABI = [
  {
    type: "function",
    name: "rating",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint32" }],
  },
  {
    type: "function",
    name: "gamesPlayed",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint32" }],
  },
  {
    type: "event",
    name: "RatingUpdated",
    inputs: [
      { name: "player", type: "address", indexed: true },
      { name: "newRating", type: "uint32", indexed: false },
    ],
  },
];
