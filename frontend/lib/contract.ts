import abi from "./abi.json";

export const CONTRACT_ADDRESS = (process.env.NEXT_PUBLIC_CONTRACT_ADDRESS ||
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

export const CONTRACT_ABI = abi;

export const ERC20_ABI = [
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "decimals",
    outputs: [{ name: "", type: "uint8" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "symbol",
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const COLLATERAL_ADDRESS = (process.env.NEXT_PUBLIC_COLLATERAL_ADDRESS ||
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

// Plan names matching dailyRates/minStakes index in the contract (0-3).
export const PLAN_NAMES = ["Starter", "Growth", "Advanced", "Elite"];

export function formatUnits6(value: bigint): string {
  const negative = value < 0n;
  const v = negative ? -value : value;
  const whole = v / 1_000000n;
  const frac = (v % 1_000000n).toString().padStart(6, "0").replace(/0+$/, "") || "0";
  return `${negative ? "-" : ""}${whole.toString()}.${frac}`;
}

export function parseUnits6(value: string): bigint {
  const [whole, frac = ""] = value.trim().split(".");
  const fracPadded = (frac + "000000").slice(0, 6);
  const wholeBig = BigInt(whole === "" ? "0" : whole);
  return wholeBig * 1_000000n + BigInt(fracPadded === "" ? "0" : fracPadded);
}
