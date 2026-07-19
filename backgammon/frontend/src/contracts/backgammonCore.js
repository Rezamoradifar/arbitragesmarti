// Fill in after you deploy BackgammonCore.sol (see /contracts in the project root).
export const BACKGAMMON_CORE_ADDRESS = {
  // Deployed 2026-07-19 via deploy/deploy.js on BSC Testnet (chain 97).
  97: import.meta.env.VITE_CORE_ADDRESS_TESTNET || "0x707fA8673EA320F284F3B81448367e4c0509F64A",
  // Deployed 2026-07-19 via deploy/deploy.js on BSC Mainnet (chain 56).
  // NOT audited. wagerAmount is 0 (free play) until a professional audit
  // completes -- see backgammon/README.md.
  56: import.meta.env.VITE_CORE_ADDRESS_MAINNET || "0x707fA8673EA320F284F3B81448367e4c0509F64A",
};

// Block BackgammonCore was deployed at (conservative lower bound) -- keeps
// getLogs() scans for the open-tables list from having to walk the whole chain.
export const BACKGAMMON_CORE_DEPLOY_BLOCK = {
  97: 120003833n,
  56: 110860908n,
};

// Trimmed ABI: only what the frontend calls/reads/listens to.
// Regenerate the full ABI from your Hardhat/Foundry build artifacts once compiled.
export const BACKGAMMON_CORE_ABI = [
  {
    type: "function",
    name: "createGame",
    stateMutability: "payable",
    inputs: [
      { name: "wagerAmount", type: "uint256" },
      { name: "wagerToken", type: "address" },
    ],
    outputs: [{ name: "gameId", type: "uint256" }],
  },
  {
    type: "function",
    name: "joinGame",
    stateMutability: "payable",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "commitRoll",
    stateMutability: "nonpayable",
    inputs: [
      { name: "gameId", type: "uint256" },
      { name: "commitHash", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "revealRoll",
    stateMutability: "nonpayable",
    inputs: [
      { name: "gameId", type: "uint256" },
      { name: "secretValue", type: "uint8" },
      { name: "salt", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "submitMoves",
    stateMutability: "nonpayable",
    inputs: [
      { name: "gameId", type: "uint256" },
      {
        name: "moves",
        type: "tuple[]",
        components: [
          { name: "from", type: "int8" },
          { name: "to", type: "int8" },
        ],
      },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "resign",
    stateMutability: "nonpayable",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "claimTimeout",
    stateMutability: "nonpayable",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "getGame",
    stateMutability: "view",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [
      { name: "playerA", type: "address" },
      { name: "playerB", type: "address" },
      { name: "phase", type: "uint8" },
      { name: "turn", type: "uint8" },
      { name: "bar", type: "uint8[2]" },
      { name: "borneOff", type: "uint8[2]" },
      { name: "winner", type: "address" },
    ],
  },
  {
    type: "function",
    name: "getBoard",
    stateMutability: "view",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [{ name: "", type: "int8[24]" }],
  },
  {
    type: "function",
    name: "getDice",
    stateMutability: "view",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [
      { name: "remainingPips", type: "uint8[4]" },
      { name: "pipCount", type: "uint8" },
    ],
  },
  {
    type: "function",
    name: "getTiming",
    stateMutability: "view",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [
      { name: "phaseDeadline", type: "uint256" },
      { name: "turnTimeoutSeconds", type: "uint256" },
    ],
  },
  {
    type: "event",
    name: "GameCreated",
    inputs: [
      { name: "gameId", type: "uint256", indexed: true },
      { name: "creator", type: "address", indexed: true },
      { name: "wager", type: "uint256", indexed: false },
      { name: "token", type: "address", indexed: false },
    ],
  },
  {
    type: "event",
    name: "GameJoined",
    inputs: [
      { name: "gameId", type: "uint256", indexed: true },
      { name: "opponent", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "MovesPlayed",
    inputs: [
      { name: "gameId", type: "uint256", indexed: true },
      { name: "player", type: "uint8", indexed: false },
      {
        name: "moves",
        type: "tuple[]",
        indexed: false,
        components: [
          { name: "from", type: "int8" },
          { name: "to", type: "int8" },
        ],
      },
    ],
  },
  {
    type: "event",
    name: "GameFinished",
    inputs: [
      { name: "gameId", type: "uint256", indexed: true },
      { name: "winner", type: "address", indexed: false },
      { name: "winnerPayout", type: "uint256", indexed: false },
      { name: "platformFee", type: "uint256", indexed: false },
      { name: "referralFee", type: "uint256", indexed: false },
    ],
  },
];

export const GAME_PHASE = [
  "None",
  "WaitingForOpponent",
  "CommitRoll",
  "RevealRoll",
  "Move",
  "Finished",
];
