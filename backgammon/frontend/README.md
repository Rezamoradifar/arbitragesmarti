# ChainGammon — Frontend

React + wagmi/viem client for the BackgammonCore/BackgammonTournament
contracts.

## Setup

```bash
npm install
cp .env.example .env
# fill in VITE_CORE_ADDRESS_TESTNET after deploying BackgammonCore.sol
npm run dev
```

## What's here

- `src/wagmi.js` — chain config (BSC + BSC Testnet), injected wallet connector
  (MetaMask/Trust Wallet); add a WalletConnect project ID for mobile-wallet
  QR support. Uses explicit publicnode RPC URLs (override with
  `VITE_TESTNET_RPC_URL`/`VITE_MAINNET_RPC_URL`) — viem's built-in chain
  defaults (`data-seed-*.bnbchain.org`, `thirdweb.com`) silently reset
  connections from a chunk of real-world networks (cloud/VPN/proxy IPs),
  which breaks reads with no clear error.
- `src/contracts/backgammonCore.js` / `ratingRegistry.js` / `backgammonTournament.js`
  — contract addresses + trimmed ABIs. Swap in the full ABI from your
  Hardhat build once compiled.
- `src/contracts/getLogsSafe.js` — free public RPCs only keep a shallow
  `eth_getLogs` history window (no paid archive tier); this retries with a
  short recent-only range instead of hanging or erroring when the full
  range is rejected, and flags the UI so it's honest about showing partial
  history.
- `src/components/NavBar.jsx` + `src/components/Landing.jsx` — top-level
  navigation and marketing/home view (hero, feature cards, how-it-works).
- `src/components/WalletConnect.jsx` — connect/disconnect, balance, wrong-chain prompt.
- `src/components/Lobby.jsx` — create a free or wagered table, join by game ID.
- `src/components/Board.jsx` — SVG board reading live state via `getBoard`/`getGame`.
- `src/components/GameStatus.jsx` — phase/turn/table cards; decides whether to show `DiceRoll` or `MovePanel`; also renders `Timer`.
- `src/components/DiceRoll.jsx` — commit-reveal dice flow; secret is cached in `localStorage` between commit and reveal so a page refresh doesn't lose it.
- `src/components/MovePanel.jsx` — shows remaining dice pips, lets the active player queue from/to moves and submit them in one transaction.
- `src/components/Timer.jsx` — live countdown reading `getTiming` (mirrors the contract's 5-minute `TURN_TIMEOUT`), progress bar, sound/vibration cue when time is low, and a "claim win" button once the opponent's clock hits zero.
- `src/components/Tournaments.jsx` — lists tournaments (from `TournamentCreated`/`TournamentFinalized` event logs, since the contract's tournament struct is private), create/register/claim.
- `src/components/Leaderboard.jsx` — on-chain ELO-style rankings from `RatingRegistry`, built from `RatingUpdated` event logs.
- `src/components/HowToPlay.jsx` — static rules reference.
- `src/components/FullscreenToggle.jsx` — Fullscreen API toggle (note: iOS Safari doesn't support the Fullscreen API on non-video elements — this fails silently there and the page just stays in normal responsive mode).
- `src/components/SettingsToggle.jsx` + `src/hooks/useFeedback.js` — sound (Web Audio synthesized tones, no audio files needed) and haptic vibration toggles, wired to turn-start / dice-reveal / move-submitted / timer-low / timeout / game-won events.
- `src/styles/global.css` — responsive rules for phone portrait/landscape, tablet, and a `:fullscreen` layout variant. The board itself (`Board.jsx`) is SVG with `viewBox` + `width:100%`, so it scales fluidly at any size without separate breakpoints.

## Known gaps to fill before this is a real product

- `Lobby.handleCreate` currently returns the transaction hash as a stand-in
  game ID — wire up `useWaitForTransactionReceipt` + parse the `GameCreated`
  event log to get the real `gameId`.
- No event indexer — lobby currently only supports "join by known ID"; a
  real lobby listing needs a backend indexing `GameCreated`/`GameJoined`
  events (see contracts README for the suggested indexing approach).
  Tournaments/Leaderboard hit the same limitation client-side: free public
  RPCs reject `eth_getLogs` beyond a shallow recent-block window without a
  paid archive tier, so `getLogsSafe.js` falls back to "recent activity
  only" instead of hanging — a real deployment should replace this with a
  proper indexer (subgraph or event-listener service) for full history.
- Point-to-board visual mapping in `Board.jsx` should be double-checked
  against `BackgammonCore._initBoard()`'s numbering before you rely on it
  for actual gameplay.
- `MovePanel` takes raw point numbers (0-23, 24 for bar/off) — a real
  product would let the player click points directly on the SVG board
  instead of typing numbers; wiring click-to-select is the next UX pass.
- No UI yet for `resign`, or for the referral link (`?ref=0x...` →
  `ReferralRegistry.setReferrer`).
- Sound autoplay: browsers block audio until the user has interacted with
  the page at least once — the first tone may be silently skipped if
  triggered before any click/tap, which is expected browser behavior, not
  a bug.
