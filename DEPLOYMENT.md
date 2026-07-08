# ArbiSmartV2 — Foundry Deployment Guide (Polygon Mainnet)

This project deploys `src/ArbiSmartV2.sol` to Polygon mainnet (chain id 137)
using Foundry, with automatic PolygonScan verification.

## What was verified in this environment vs. what you must verify yourself

Foundry's `forge`/`cast` binaries could not be installed in the sandboxed
environment this project was generated in (its network policy blocks
`github.com` and `objects.githubusercontent.com`, which is where
`foundryup` downloads the prebuilt binaries from). Everything below was
still verified as far as possible without them:

- `lib/openzeppelin-contracts` and `lib/forge-std` are **real git
  submodules**, cloned from their official repositories and pinned to
  tagged releases (`v5.6.1` and `v1.9.7` respectively) — not stubs.
- `src/ArbiSmartV2.sol` was independently compiled with the **exact solc
  version and settings declared in `foundry.toml`** (`solc 0.8.26`,
  `via_ir = true`, optimizer on, 200 runs) using the vendored OpenZeppelin
  v5.6.1 source, via solc's Node.js bindings directly (not through
  `forge`). Result: **0 errors, 0 warnings**, valid runtime bytecode
  (11,980 bytes, well under the 24,576-byte EIP-170 limit).

**Before deploying anything real, run `forge build` yourself first** and
confirm it also reports zero warnings — this environment's compile check is
strong evidence, not a substitute for Foundry's own build.

## 1. Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## 2. Install dependencies

The two required libraries are already vendored as git submodules in this
repo (`lib/openzeppelin-contracts` @ v5.6.1, `lib/forge-std` @ v1.9.7). If
you cloned this repo fresh, pull them in with:

```bash
git submodule update --init --recursive
```

## 3. Configure environment

```bash
cp .env.example .env
```

Fill in `.env`:

| Variable | Notes |
|---|---|
| `POLYGON_RPC_URL` | A private RPC endpoint is strongly recommended for production (Alchemy/Infura/QuickNode). |
| `PRIVATE_KEY` | Deployer key. Only needs to pay gas — does not need to be the contract owner. |
| `COLLATERAL_TOKEN` | Must be the exact ERC-20 address the target Polymarket condition(s) were prepared with. |
| `INITIAL_OWNER` | **Strongly recommended:** a Gnosis Safe multisig or `TimelockController` address, not a bare EOA — this receives full admin privileges. |
| `FEE_WALLET_1` / `FEE_WALLET_2` | Fee recipients, funded from staking-yield claims. |
| `PROFIT_RECIPIENT` | Distinct recipient of the performance fee on REAL, realized Polymarket arbitrage profit (`profitFeeBPS`, default 10%, owner-adjustable up to a hard 20% cap). |
| `POLYGONSCAN_API_KEY` | From https://polygonscan.com/myapikey |

Foundry reads `.env` automatically via `vm.envAddress`/`vm.envUint` in
`script/Deploy.s.sol` when you run `forge script`/`forge test` with
`source .env` exported, or by using `--env-file .env` if your Foundry
version supports it. Simplest: `source .env` before running any `forge`
command below.

## 4. Build

```bash
forge build
```

Expect: **0 errors, 0 warnings**. If you see "Stack too deep", confirm
`via_ir = true` is present in `foundry.toml` (it is, by default, in this
project) and that you didn't override it on the command line.

## 5. Deploy + automatic verification (one command)

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url polygon \
  --broadcast \
  --verify \
  -vvvv
```

- `--rpc-url polygon` resolves to `POLYGON_RPC_URL` via the `[rpc_endpoints]`
  table in `foundry.toml`.
- `--broadcast` actually sends the deployment transaction (omit it first
  for a dry run).
- `--verify` runs Foundry's built-in verifier against the `[etherscan]`
  table in `foundry.toml` (which points at PolygonScan's API, chain 137)
  immediately after the transaction confirms.

This is a **real, irreversible on-chain deployment once `--broadcast` is
included** — double-check every `.env` value, especially `INITIAL_OWNER`,
before running it.

## 6. Standalone verification (fallback)

PolygonScan sometimes hasn't indexed a brand-new contract yet, which can
make the automatic `--verify` step above fail even though the deployment
itself succeeded. If that happens, wait a minute and verify separately with
`forge verify-contract`, using the deployed address from step 5's output
and the same constructor arguments:

```bash
forge verify-contract \
  --chain 137 \
  --etherscan-api-key "$POLYGONSCAN_API_KEY" \
  --constructor-args $(cast abi-encode \
    "constructor(address,address,address,address,address)" \
    "$COLLATERAL_TOKEN" "$INITIAL_OWNER" "$FEE_WALLET_1" "$FEE_WALLET_2" "$PROFIT_RECIPIENT") \
  <DEPLOYED_CONTRACT_ADDRESS> \
  src/ArbiSmartV2.sol:ArbiSmartV2
```

Replace `<DEPLOYED_CONTRACT_ADDRESS>` with the address printed by the
deploy script. You can also find/re-run past deployments via the
`broadcast/Deploy.s.sol/137/run-latest.json` file Foundry writes after
every broadcast.

## 6.5. Testing

`test/ArbiSmartV2.t.sol` (unit tests) and `test/invariant/` (handler + invariants) are included. Run:

```bash
forge test -vvv
forge test --match-contract ArbiSmartV2InvariantTest -vvv
```

A full production validation pass (Slither, Mythril, and 20 real executed end-to-end scenarios against the official Polymarket Conditional Tokens source) was already completed — see the validation report for details and a go/no-go recommendation. No Critical or High severity issues were found.

## 7. Post-deployment checklist

- [ ] Confirm `owner()` on PolygonScan matches your intended multisig/timelock, not the deployer EOA.
- [ ] Confirm `collateralToken()` matches the exact token address used by the Polymarket market(s) you intend to trade.
- [ ] Confirm `profitRecipient()` and `profitFeeBPS()` (default 10%, capped at 20%) match what you intended — distinct from `feeWallet1`/`feeWallet2`.
- [ ] Confirm the contract shows as "Contract" with a green checkmark (verified) on PolygonScan, and that the displayed source matches `src/ArbiSmartV2.sol`.
- [ ] If `INITIAL_OWNER` was a plain EOA for testing, transfer ownership to your multisig/timelock via `transferOwnership` + `acceptOwnership` (Ownable2Step) before any real funds are deposited.
- [ ] Read the "WHAT CHANGED VS. THE ORIGINAL CONTRACT" NatSpec block at the top of `src/ArbiSmartV2.sol` — in particular, this contract cannot autonomously trade on Polymarket's order book (`CTFExchange.fillOrder`/`matchOrders` are `onlyOperator`-gated by Polymarket itself); only direct `splitPosition`/`mergePositions`/`redeemPositions` calls to the Conditional Tokens contract are implemented.
