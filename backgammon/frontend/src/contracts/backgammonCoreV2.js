// BackgammonCoreV2: same game engine as V1 (backgammonCore.js) plus a
// doubling cube and an owner-only emergency pause. Separate deployed
// contract, not an upgrade -- see backgammon/contracts/src/BackgammonCoreV2.sol.
export const BACKGAMMON_CORE_ADDRESS = {
  // Deployed 2026-07-20 via deploy/deployV2.js on BSC Testnet (chain 97).
  97: import.meta.env.VITE_CORE_V2_ADDRESS_TESTNET || "0xB877F39A0B5380636039413230C51703C7AC0DF9",
  // Deployed 2026-07-20 via deploy/deployV2.js on BSC Mainnet (chain 56).
  // NOT audited. wagerAmount is 0 (free play) until a professional audit
  // completes -- see backgammon/README.md.
  56: import.meta.env.VITE_CORE_V2_ADDRESS_MAINNET || "0xB877F39A0B5380636039413230C51703C7AC0DF9",
};

// Block BackgammonCoreV2 was deployed at (conservative lower bound) --
// keeps getLogs() scans for the open-tables list from having to walk the
// whole chain.
export const BACKGAMMON_CORE_DEPLOY_BLOCK = {
  97: 120225212n,
  56: 111082209n,
};

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
    name: "offerDouble",
    stateMutability: "payable",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "acceptDouble",
    stateMutability: "payable",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "declineDouble",
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
    type: "function",
    name: "getCube",
    stateMutability: "view",
    inputs: [{ name: "gameId", type: "uint256" }],
    outputs: [
      { name: "cubeValue", type: "uint8" },
      { name: "cubeOwner", type: "address" },
      { name: "doubleOfferedBy", type: "address" },
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
    name: "DoubleOffered",
    inputs: [
      { name: "gameId", type: "uint256", indexed: true },
      { name: "by", type: "address", indexed: true },
      { name: "newCubeValue", type: "uint8", indexed: false },
    ],
  },
  {
    type: "event",
    name: "DoubleAccepted",
    inputs: [
      { name: "gameId", type: "uint256", indexed: true },
      { name: "by", type: "address", indexed: true },
      { name: "newCubeValue", type: "uint8", indexed: false },
    ],
  },
  {
    type: "event",
    name: "DoubleDeclined",
    inputs: [
      { name: "gameId", type: "uint256", indexed: true },
      { name: "by", type: "address", indexed: true },
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

// Must match BackgammonCoreV2.sol's Phase enum order exactly.
export const GAME_PHASE = [
  "None",
  "WaitingForOpponent",
  "CommitRoll",
  "RevealRoll",
  "Move",
  "DoubleOffered",
  "Finished",
];
