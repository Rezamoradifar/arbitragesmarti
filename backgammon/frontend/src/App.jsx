import { useState } from "react";
import { useAccount } from "wagmi";
import WalletConnect from "./components/WalletConnect";
import NavBar from "./components/NavBar";
import Landing from "./components/Landing";
import Lobby from "./components/Lobby";
import Board from "./components/Board";
import GameStatus from "./components/GameStatus";
import Tournaments from "./components/Tournaments";
import Leaderboard from "./components/Leaderboard";
import HowToPlay from "./components/HowToPlay";
import SettingsToggle from "./components/SettingsToggle";
import FullscreenToggle from "./components/FullscreenToggle";
import { DiceIcon } from "./components/icons";

export default function App() {
  const { isConnected } = useAccount();
  const [tab, setTab] = useState("home");
  const [activeGameId, setActiveGameId] = useState(null);

  function goToPlay() {
    setTab("play");
  }

  return (
    <div className="app-container">
      <header className="app-header">
        <div style={{ display: "flex", alignItems: "center", gap: "0.7rem" }}>
          <span className="brand-mark">
            <DiceIcon width={19} height={19} />
          </span>
          <div>
            <div className="eyebrow">On-chain · BNB Smart Chain</div>
            <h1 style={{ fontSize: "1.6rem", marginTop: "0.2rem" }}>ChainGammon</h1>
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "0.8rem" }}>
          <SettingsToggle />
          <FullscreenToggle />
          <WalletConnect />
        </div>
      </header>

      <div style={{ marginBottom: "1.6rem" }}>
        <NavBar active={tab} onChange={setTab} />
      </div>

      {tab === "home" && <Landing isConnected={isConnected} onPlay={goToPlay} />}

      {tab === "play" && !isConnected && (
        <div className="panel" style={{ padding: "3rem", textAlign: "center" }}>
          <h2 style={{ fontSize: "1.3rem", marginBottom: "0.6rem" }}>Connect a wallet to play</h2>
          <p style={{ color: "var(--ivory-dim)", maxWidth: 440, margin: "0 auto" }}>
            Every roll, move, and stake is settled on-chain. Connect MetaMask or
            Trust Wallet on BNB Smart Chain to open a table.
          </p>
        </div>
      )}

      {tab === "play" && isConnected && activeGameId === null && <Lobby onEnterGame={setActiveGameId} />}

      {tab === "play" && isConnected && activeGameId !== null && (
        <div className="game-view">
          <button className="btn-ghost" style={{ marginBottom: "1rem" }} onClick={() => setActiveGameId(null)}>
            ← Back to lobby
          </button>
          <Board gameId={activeGameId} />
          <GameStatus gameId={activeGameId} />
        </div>
      )}

      {tab === "tournaments" && <Tournaments />}
      {tab === "leaderboard" && <Leaderboard />}
      {tab === "how-to-play" && <HowToPlay />}
    </div>
  );
}
