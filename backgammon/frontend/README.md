# Galaxy Points — Frontend

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
  QR support.
- `src/contracts/backgammonCore.js` — contract addresses + trimmed ABI.
  Swap in the full ABI from your Hardhat/Foundry build once compiled.
- `src/components/WalletConnect.jsx` — connect/disconnect, balance, wrong-chain prompt.
- `src/components/Lobby.jsx` — create a free or wagered table, join by game ID.
- `src/components/Board.jsx` — SVG board reading live state via `getBoard`/`getGame`.
- `src/components/GameStatus.jsx` — phase/turn/table cards; decides whether to show `DiceRoll` or `MovePanel`; also renders `Timer`.
- `src/components/DiceRoll.jsx` — commit-reveal dice flow; secret is cached in `localStorage` between commit and reveal so a page refresh doesn't lose it.
- `src/components/MovePanel.jsx` — shows remaining dice pips, lets the active player queue from/to moves and submit them in one transaction.
- `src/components/Timer.jsx` — live countdown reading `getTiming` (mirrors the contract's 5-minute `TURN_TIMEOUT`), progress bar, sound/vibration cue when time is low, and a "claim win" button once the opponent's clock hits zero.
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
