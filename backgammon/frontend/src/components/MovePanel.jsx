import { useState } from "react";
import { useChainId, useReadContract, useWriteContract } from "wagmi";
import { BACKGAMMON_CORE_ADDRESS, BACKGAMMON_CORE_ABI } from "../contracts/backgammonCore";

function pointLabel(v) {
  if (v === "24" || v === 24) return "Bar/Off";
  return v;
}

export default function MovePanel({ gameId, isMyTurn }) {
  const chainId = useChainId();
  const address = BACKGAMMON_CORE_ADDRESS[chainId];
  const { writeContractAsync, isPending } = useWriteContract();
  const [queued, setQueued] = useState([]);
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [error, setError] = useState(null);

  const { data: dice } = useReadContract({
    address,
    abi: BACKGAMMON_CORE_ABI,
    functionName: "getDice",
    args: [gameId],
    query: { enabled: !!address && gameId !== undefined },
  });

  const remainingPips = dice ? dice[0].filter((p) => p > 0) : [];

  function addMove() {
    if (from === "" || to === "") return;
    setQueued((q) => [...q, { from: Number(from), to: Number(to) }]);
    setFrom("");
    setTo("");
  }

  function removeMove(idx) {
    setQueued((q) => q.filter((_, i) => i !== idx));
  }

  async function handleSubmit() {
    setError(null);
    try {
      await writeContractAsync({
        address,
        abi: BACKGAMMON_CORE_ABI,
        functionName: "submitMoves",
        args: [gameId, queued],
      });
      setQueued([]);
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to submit moves");
    }
  }

  if (!isMyTurn) {
    return (
      <div className="panel" style={{ padding: "1.5rem", textAlign: "center" }}>
        <div className="eyebrow">Waiting</div>
        <p style={{ color: "var(--ivory-dim)", margin: "0.6rem 0 0" }}>
          Your opponent is moving. Board updates live once they submit.
        </p>
      </div>
    );
  }

  return (
    <div className="panel" style={{ padding: "1.5rem" }}>
      <div className="eyebrow">Your move</div>
      <div style={{ display: "flex", gap: "0.4rem", margin: "0.8rem 0 1.2rem" }}>
        {remainingPips.map((p, i) => (
          <div
            key={i}
            className="mono"
            style={{
              width: 34,
              height: 34,
              borderRadius: 4,
              background: "var(--brass)",
              color: "var(--ink)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontWeight: 600,
            }}
          >
            {p}
          </div>
        ))}
      </div>

      <div style={{ display: "flex", gap: "0.5rem", alignItems: "flex-end", marginBottom: "1rem" }}>
        <label style={{ flex: 1 }}>
          <span className="mono" style={{ fontSize: "0.75rem", color: "var(--ivory-dim)" }}>From (0-23, 24=bar)</span>
          <input
            value={from}
            onChange={(e) => setFrom(e.target.value)}
            className="mono"
            style={{ display: "block", width: "100%", marginTop: "0.3rem", padding: "0.5rem", background: "var(--ink)", border: "1px solid var(--line)", color: "var(--ivory)", borderRadius: "3px" }}
          />
        </label>
        <label style={{ flex: 1 }}>
          <span className="mono" style={{ fontSize: "0.75rem", color: "var(--ivory-dim)" }}>To (0-23, 24=off)</span>
          <input
            value={to}
            onChange={(e) => setTo(e.target.value)}
            className="mono"
            style={{ display: "block", width: "100%", marginTop: "0.3rem", padding: "0.5rem", background: "var(--ink)", border: "1px solid var(--line)", color: "var(--ivory)", borderRadius: "3px" }}
          />
        </label>
        <button className="btn-ghost" onClick={addMove}>Add</button>
      </div>

      {queued.length > 0 && (
        <div style={{ marginBottom: "1rem" }}>
          {queued.map((m, i) => (
            <div key={i} className="mono" style={{ display: "flex", justifyContent: "space-between", padding: "0.4rem 0", borderBottom: "1px solid var(--line)", fontSize: "0.85rem" }}>
              <span>{pointLabel(m.from)} → {pointLabel(m.to)}</span>
              <button className="btn-ghost" style={{ padding: "0.1rem 0.5rem" }} onClick={() => removeMove(i)}>✕</button>
            </div>
          ))}
        </div>
      )}

      <button className="btn-primary" disabled={isPending || queued.length === 0} onClick={handleSubmit}>
        {isPending ? "Confirm in wallet…" : `Submit ${queued.length} move${queued.length === 1 ? "" : "s"}`}
      </button>
      {error && <p style={{ color: "var(--oxblood-bright)", marginTop: "0.8rem" }}>{error}</p>}
    </div>
  );
}
