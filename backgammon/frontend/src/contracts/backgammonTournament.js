export const TOURNAMENT_ADDRESS = {
  97: import.meta.env.VITE_TOURNAMENT_ADDRESS_TESTNET || "0x5C30ec862741f6977E22cFa7Fd368Cd95CF63a40",
  56: import.meta.env.VITE_TOURNAMENT_ADDRESS_MAINNET || "0x5C30ec862741f6977E22cFa7Fd368Cd95CF63a40",
};

// Block the contract was deployed at (conservative lower bound) -- keeps
// getLogs() scans for the tournament list from having to walk the whole chain.
export const TOURNAMENT_DEPLOY_BLOCK = {
  97: 120003833n,
  56: 110860908n,
};

export const TOURNAMENT_ABI = [
  {
    type: "function",
    name: "nextTournamentId",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "createTournament",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "entryFee", type: "uint256" },
      { name: "maxPlayers", type: "uint256" },
      { name: "payoutBpsByRank", type: "uint16[]" },
    ],
    outputs: [{ name: "id", type: "uint256" }],
  },
  {
    type: "function",
    name: "register",
    stateMutability: "payable",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "claimPrize",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "getPlayers",
    stateMutability: "view",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [{ name: "", type: "address[]" }],
  },
  {
    type: "function",
    name: "getRanking",
    stateMutability: "view",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [{ name: "", type: "address[]" }],
  },
  {
    type: "event",
    name: "TournamentCreated",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "organizer", type: "address", indexed: false },
      { name: "entryFee", type: "uint256", indexed: false },
      { name: "maxPlayers", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "TournamentFinalized",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "ranking", type: "address[]", indexed: false },
    ],
  },
];
