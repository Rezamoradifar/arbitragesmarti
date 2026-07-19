import { useState } from "react";
import { useAccount } from "wagmi";
import WalletConnect from "./components/WalletConnect";
import Lobby from "./components/Lobby";
import Board from "./components/Board";
import GameStatus from "./components/GameStatus";
import SettingsToggle from "./components/SettingsToggle";
import FullscreenToggle from "./components/FullscreenToggle";

export default function App() {
  const { isConnected } = useAccount();
  const [activeGameId, setActiveGameId] = useState(null);

  return (
    <div className="app-container">
      <header className="app-header">
        <div>
          <div className="eyebrow">On-chain · BNB Smart Chain</div>
          <h1 style={{ fontSize: "1.9rem", marginTop: "0.3rem" }}>Galaxy Points</h1>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "0.8rem" }}>
          <SettingsToggle />
          <FullscreenToggle />
          <WalletConnect />
        </div>
      </header>

      {!isConnected && (
        <div className="panel" style={{ padding: "3rem", textAlign: "center" }}>
          <h2 style={{ fontSize: "1.3rem", marginBottom: "0.6rem" }}>Connect a wallet to play</h2>
          <p style={{ color: "var(--ivory-dim)", maxWidth: 440, margin: "0 auto" }}>
            Every roll, move, and stake is settled on-chain. Connect MetaMask or
            Trust Wallet on BNB Smart Chain to open a table.
          </p>
        </div>
      )}

      {isConnected && !activeGameId && <Lobby onEnterGame={setActiveGameId} />}

      {isConnected && activeGameId && (
        <div className="game-view">
          <button className="btn-ghost" style={{ marginBottom: "1rem" }} onClick={() => setActiveGameId(null)}>
            ← Back to lobby
          </button>
          <Board gameId={activeGameId} />
          <GameStatus gameId={activeGameId} />
        </div>
      )}
    </div>
  );
}
