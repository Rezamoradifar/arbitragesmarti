const STEPS = [
  {
    title: "The board",
    body: "Each side has 15 checkers. You move around 24 points toward your home board, then bear them all off. The direction is fixed at table creation: Player A moves point 0 → 23, Player B moves point 23 → 0.",
  },
  {
    title: "Rolling",
    body: "Instead of trusting a server or an oracle, both players commit a hashed secret before every roll and then reveal it. The dice are derived from both reveals together, so neither player can bias the outcome alone.",
  },
  {
    title: "Moving",
    body: "Each die lets you move one checker that many points. Rolling doubles gives you four moves instead of two. Landing on a point held by exactly one enemy checker sends it to the bar; landing on a point held by two or more is blocked.",
  },
  {
    title: "The bar and bearing off",
    body: "A checker sent to the bar must re-enter your opponent's home board before any other move. Once all 15 of your checkers are in your home board, you can start bearing them off — first to bear off all 15 wins.",
  },
  {
    title: "Wagering",
    body: "Tables can be free play or wagered in BNB. A wagered table locks both players' stakes in the contract when the second player joins; the pot is split automatically the moment the game finishes — no separate withdrawal step.",
  },
  {
    title: "Timeouts",
    body: "Every phase (commit, reveal, move) has a 5-minute clock. If your opponent goes silent, you can claim the win once their clock reaches zero — the contract enforces this on-chain, no support ticket required.",
  },
];

export default function HowToPlay() {
  return (
    <div className="panel" style={{ padding: "1.5rem" }}>
      <div className="eyebrow">Rules</div>
      <h2 style={{ margin: "0.4rem 0 1.2rem" }}>How to play</h2>
      <div style={{ display: "grid", gap: "1.1rem" }}>
        {STEPS.map((s, i) => (
          <div key={s.title} style={{ display: "flex", gap: "1rem" }}>
            <div className="mono" style={{ color: "var(--brass-bright)", fontSize: "1.1rem", minWidth: "1.6rem" }}>
              {String(i + 1).padStart(2, "0")}
            </div>
            <div>
              <h3 style={{ fontSize: "1.05rem", marginBottom: "0.3rem" }}>{s.title}</h3>
              <p style={{ color: "var(--ivory-dim)", margin: 0, lineHeight: 1.55 }}>{s.body}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
