import { DiceIcon, TrophyIcon, ChartIcon } from "./icons";

const FEATURES = [
  {
    title: "Casual & wagered tables",
    body: "Play for free, or stake BNB on a table — the pot settles automatically on-chain the moment a game finishes.",
    Icon: DiceIcon,
  },
  {
    title: "Tournaments",
    body: "Enter a prize pool, compete, and claim your share directly from the contract once standings are finalized.",
    Icon: TrophyIcon,
  },
  {
    title: "On-chain ratings",
    body: "Every finished game updates a public ELO-style rating — no centralized database, no hidden leaderboard.",
    Icon: ChartIcon,
  },
];

const HOW_IT_WORKS = [
  { step: "1", title: "Connect a wallet", body: "MetaMask or Trust Wallet on BNB Smart Chain." },
  { step: "2", title: "Open or join a table", body: "Free play to start, or stake BNB once you're ready." },
  { step: "3", title: "Play it out", body: "Roll, move, and win — the contract handles payout instantly." },
];

export default function Landing({ isConnected, onPlay }) {
  return (
    <div style={{ display: "grid", gap: "2rem" }}>
      <div className="panel" style={{ padding: "3rem 2rem", textAlign: "center" }}>
        <div className="eyebrow">On-chain · BNB Smart Chain</div>
        <h1 style={{ fontSize: "2.4rem", margin: "0.5rem 0 0.8rem" }}>ChainGammon</h1>
        <p style={{ color: "var(--ivory-dim)", maxWidth: 520, margin: "0 auto 1.6rem", lineHeight: 1.6 }}>
          Backgammon settled entirely on-chain: board state, dice, wagers, and
          payouts. No house wallet holding your stake, no black-box RNG.
        </p>
        <button className="btn-primary" onClick={onPlay}>
          {isConnected ? "Enter the lobby" : "Connect wallet to play"}
        </button>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "1rem" }}>
        {FEATURES.map((f) => (
          <div key={f.title} className="panel panel-interactive" style={{ padding: "1.4rem" }}>
            <span className="feature-icon">
              <f.Icon width={19} height={19} />
            </span>
            <h3 style={{ fontSize: "1.05rem", marginBottom: "0.5rem" }}>{f.title}</h3>
            <p style={{ color: "var(--ivory-dim)", margin: 0, fontSize: "0.9rem", lineHeight: 1.55 }}>{f.body}</p>
          </div>
        ))}
      </div>

      <div className="panel" style={{ padding: "1.6rem 1.4rem" }}>
        <div className="eyebrow" style={{ marginBottom: "1rem" }}>How it works</div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "1.2rem" }}>
          {HOW_IT_WORKS.map((s) => (
            <div key={s.step}>
              <div className="mono" style={{ color: "var(--brass-bright)", fontSize: "1.4rem" }}>{s.step}</div>
              <h3 style={{ fontSize: "0.98rem", margin: "0.2rem 0 0.3rem" }}>{s.title}</h3>
              <p style={{ color: "var(--ivory-dim)", margin: 0, fontSize: "0.85rem" }}>{s.body}</p>
            </div>
          ))}
        </div>
      </div>

      <p style={{ textAlign: "center", color: "var(--ivory-dim)", fontSize: "0.78rem" }}>
        Contracts are unaudited — real-money wagering is disabled on mainnet
        until a professional audit is complete. Testnet wagering is open now.
      </p>
    </div>
  );
}
