# ChainGammon Contracts — BSC Edition

An on-chain backgammon platform's feature set, split honestly between
what can live on-chain and what must stay off-chain.

## Contracts (this folder)

| Contract | Purpose |
|---|---|
| `BackgammonCore.sol` | Board state, commit-reveal dice, move validation, hitting, bearing off, wager escrow + payout, timeouts/resignation |
| `BackgammonTournament.sol` | Entry fees, prize pool escrow, organizer-finalized standings, on-chain prize claims |
| `RatingRegistry.sol` | On-chain ELO-style rating, updated by `BackgammonCore` after each finished game |
| `ReferralRegistry.sol` | Multi-level referral commissions, paid out instantly in the same transaction a wagered game finishes |

## Revenue model (wagered games only — free play is never fee'd)

Every wagered game's pot (`wagerAmount * 2`) splits three ways when it finishes:

- **5% → platform treasury** (`protocolFeeBps`, `feeRecipient`)
- **10% → referral pool** (`referralFeeBps`), forwarded to `ReferralRegistry`
  and paid out **instantly, multi-level, in the same transaction** —
  no separate claim step for referrers.
- **85% → the winner**

Referral split mechanics: the 10% referral pool is divided 50/50 between
playerA's and playerB's own upline chains (each player's stake funds their
own referrer tree). Within one player's half, level 1 (direct referrer)
gets 50%, level 2 gets 30%, level 3 gets 20% — configurable via
`ReferralRegistry.setLevelBps`. Any unpaid share (player has no referrer,
or a shorter chain than 3 levels) is swept back to the platform treasury
in the same transaction, so funds never get stuck.

Both fee rates are owner-adjustable but hard-capped at a combined 30%
(`MAX_TOTAL_FEE_BPS`) so the contract itself can't be reconfigured into
something predatory.

Deployment order matters: deploy `ReferralRegistry` first, then
`BackgammonCore`, then call `referralRegistry.setAuthorizedCaller(coreAddress, true)`
and `core.setReferralRegistry(registryAddress)`.

**Platform owner / treasury wallet:** `0x63c5B98AEfd69658B652d5F35FFda3C6c06847E3`
— this is where `feeRecipient` points and where contract ownership
(fee settings, authorized-caller management) is transferred to. See
`deploy/deploy.js` for the full automated deployment + wiring script.

Dependencies: OpenZeppelin Contracts (`IERC20`, `ReentrancyGuard`, `Ownable`).

## What's realistically on-chain vs off-chain

**On-chain (these contracts):**
- Board / dice / moves / win detection
- Wager escrow and payout
- Tournament prize pool and claims
- Rating updates

**Off-chain (backend + frontend, not smart contracts):**
- **AI opponent** — running model inference inside the EVM is not
  economically or technically feasible. The AI plays as a normal wallet
  (a bot service holding a key) that calls `submitMoves` like any player.
- **Lessons / blog / how-to-play content** — plain content, no reason to
  put it on-chain.
- **Move analysis / "blunders" report** — needs a real backgammon
  analysis engine (e.g. an open-source rollout engine); runs server-side
  and reads game history from `BackgammonCore` events.
- **Lobby / matchmaking / chat / avatars / profile customization** —
  real-time and storage-heavy, standard Web2 backend (Postgres + websockets).
- **Tournament bracket pairing** — computed off-chain; only the prize
  pool and final standings need to be trustless.

## Suggested stack (matches your existing BSC frontend work)

- **Frontend:** React + ethers.js/viem + wagmi, wallet connect via
  MetaMask/WalletConnect — same pattern as your matrix dashboard project.
- **Backend:** Node service that (a) runs the AI bot wallet, (b) indexes
  `BackgammonCore`/`BackgammonTournament` events into Postgres for
  lobby/history/leaderboard reads, (c) serves lesson content.
- **Indexing:** The Graph subgraph or a simple event-listener service —
  reading full game history directly from chain for every UI request
  will be slow/expensive.

## Known simplifications / Phase 2 TODOs

- No doubling cube yet (`BackgammonCore` plays fixed-stake games only).
- Move legality checks distance/occupancy but does not yet enforce
  "must play the maximum number of legal dice" edge case some rule sets
  require — add before any real-money mainnet deployment.
- `RatingRegistry._expectedScoreScaled` is a bucketed approximation of
  the ELO logistic curve (Solidity has no floating point) — fine for
  in-app ranking, not for anything requiring exact ELO math.
- **Not audited.** Get a professional Solidity audit before enabling
  real-money wagering on mainnet — this is standard practice and worth
  budgeting for given the escrow/payout logic here.

## Next steps

1. ~~`npm install @openzeppelin/contracts` and compile with Hardhat/Foundry~~ —
   done: `npm install` + `npx hardhat compile` in this folder (Solidity
   0.8.24, OpenZeppelin v5). `npx hardhat test` runs the test suite in
   `test/`.
2. ~~Wire `BackgammonCore` to call `RatingRegistry.reportResult()` on
   `_finishGame`~~ — done: `BackgammonCore` now has a `ratingRegistry`
   address (set via `setRatingRegistry`, wired automatically in
   `deploy/deploy.js`) and calls `reportResult()` in `_finishGame`,
   best-effort (a misconfigured registry never blocks payout).
3. ~~Deploy to BSC testnet~~ — done: also deployed to BSC mainnet (see
   `deployments/bscTestnet.json` / `deployments/bscMainnet.json`).
4. ~~Verify on BscScan~~ — done: `npx hardhat verify --network <bscTestnet|bscMainnet> <address> [constructorArgs...]`
   (needs `BSCSCAN_API_KEY` in `.env`, a free key from
   https://bscscan.com/myapikey — the Etherscan V2 unified API key works
   across all supported chains). All four contracts verified on both
   networks; links in the `deployments/*.json` files.
5. Build the bot wallet service for AI opponents.
6. Get a professional audit before enabling real-money wagering on
   mainnet.
