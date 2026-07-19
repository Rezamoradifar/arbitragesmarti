# Backgammon dApp (BSC) — Full Project

On-chain Backgammon Galaxy-style platform for BNB Smart Chain.

## Structure

- `contracts/` — Solidity smart contracts (game engine, tournament, rating,
  referral) + Hardhat deploy script. See `contracts/README.md`.
- `frontend/` — React + wagmi/viem web app (wallet connect, lobby, board,
  dice/move flow, timer, sound/vibration, responsive/fullscreen). See
  `frontend/README.md`.

## Quick start

```bash
# 1. Contracts
cd contracts
npm install
npx hardhat compile
npx hardhat test
cp .env.example .env   # fill in DEPLOYER_PRIVATE_KEY (testnet key, never a funded mainnet key here)
npx hardhat run deploy/deploy.js --network bscTestnet

# 2. Frontend
cd ../frontend
npm install
cp .env.example .env   # paste the deployed BackgammonCore address in
npm run dev
```

## Status / what's real vs. mocked

- Contracts: Solidity source compiles clean under Hardhat (Solidity
  0.8.24, OpenZeppelin v5), and a Hardhat/Chai test suite
  (`contracts/test/`) covers game creation, wager escrow, resign/timeout
  payout splits (5% platform / 10% referral / 85% winner), multi-level
  referral commissions, rating updates, and tournament entry/finalize/claim
  — all 9 tests pass. `BackgammonCore` now calls
  `RatingRegistry.reportResult()` on every finished game (this wiring was
  a listed TODO and has been completed). **Still not deployed to any
  network or professionally audited** — get an audit before enabling
  real-money wagering on mainnet.
- Frontend: React + Vite app builds cleanly (`npm run build`) and the
  wallet-not-connected landing screen renders correctly (verified in a
  headless browser). The wallet-connected flow (lobby, board, live game)
  has not been exercised end-to-end against a deployed contract yet —
  do that after a testnet deployment.
- Off-chain by design (not in this project): AI opponent, lessons/blog
  content, deep move analysis, lobby indexing/chat. See
  `contracts/README.md` for the full on-chain vs. off-chain breakdown.

## Before real-money mainnet wagering

This is a real-money escrow/wagering platform. Before taking real funds on
mainnet:

1. Get a professional Solidity audit (escrow + payout logic in
   `BackgammonCore`/`ReferralRegistry`/`BackgammonTournament`).
2. Confirm gambling/wagering licensing for every jurisdiction you'll
   operate in.
3. Close the known Phase 2 gaps in `contracts/README.md` (no doubling
   cube yet; move legality doesn't yet enforce "must play the maximum
   number of legal dice").
4. Deploy to BSC testnet first, run a full game end-to-end from the
   frontend, then deploy to mainnet from a wallet you control (this repo
   never stores or transmits a private key — `DEPLOYER_PRIVATE_KEY` stays
   local in your own untracked `.env`).

## Platform owner / treasury

`0x63c5B98AEfd69658B652d5F35FFda3C6c06847E3` — receives the 5% platform
fee and holds admin ownership of all four contracts after deployment.
