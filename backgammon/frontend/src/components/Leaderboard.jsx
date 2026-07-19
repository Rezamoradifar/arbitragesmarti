import { useEffect, useState } from "react";
import { useChainId, usePublicClient } from "wagmi";
import {
  RATING_REGISTRY_ADDRESS,
  RATING_REGISTRY_ABI,
  RATING_REGISTRY_DEPLOY_BLOCK,
  DEFAULT_RATING,
} from "../contracts/ratingRegistry";
import { getLogsSafe } from "../contracts/getLogsSafe";

function short(addr) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export default function Leaderboard() {
  const chainId = useChainId();
  const publicClient = usePublicClient();
  const [rows, setRows] = useState(null);
  const [error, setError] = useState(null);
  const [limitedHistory, setLimitedHistory] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setRows(null);
      setError(null);
      const address = RATING_REGISTRY_ADDRESS[chainId];
      const fromBlock = RATING_REGISTRY_DEPLOY_BLOCK[chainId];
      if (!address || !publicClient) return;
      try {
        const { logs, limitedHistory: limited } = await getLogsSafe(publicClient, {
          address,
          event: RATING_REGISTRY_ABI.find((e) => e.name === "RatingUpdated"),
          fromBlock,
        });
        if (!cancelled) setLimitedHistory(limited);

        // Keep only the latest rating per player (logs come in ascending order).
        const latest = new Map();
        for (const log of logs) {
          latest.set(log.args.player, Number(log.args.newRating));
        }

        const players = [...latest.entries()];
        const gamesPlayed = await Promise.all(
          players.map(([player]) =>
            publicClient.readContract({
              address,
              abi: RATING_REGISTRY_ABI,
              functionName: "gamesPlayed",
              args: [player],
            })
          )
        );

        const combined = players
          .map(([player, rating], i) => ({ player, rating, gamesPlayed: Number(gamesPlayed[i]) }))
          .sort((a, b) => b.rating - a.rating);

        if (!cancelled) setRows(combined);
      } catch (e) {
        if (!cancelled) setError(e.shortMessage || e.message || "Failed to load leaderboard");
      }
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [chainId, publicClient]);

  return (
    <div className="panel" style={{ padding: "1.5rem" }}>
      <div className="eyebrow">Rankings</div>
      <h2 style={{ margin: "0.4rem 0 1.2rem" }}>Leaderboard</h2>

      {limitedHistory && !error && (
        <p style={{ color: "var(--ivory-dim)", fontSize: "0.78rem", marginTop: "-0.6rem", marginBottom: "1rem" }}>
          This public RPC only keeps recent block history — showing recent
          activity only. Point the app at an archive RPC for full history.
        </p>
      )}
      {error && <p style={{ color: "var(--oxblood-bright)" }}>{error}</p>}
      {!error && rows === null && <p style={{ color: "var(--ivory-dim)" }}>Loading on-chain ratings…</p>}
      {!error && rows && rows.length === 0 && (
        <p style={{ color: "var(--ivory-dim)" }}>
          No rated games finished yet on this network. Ratings start at {DEFAULT_RATING} after your first game.
        </p>
      )}

      {rows && rows.length > 0 && (
        <table className="mono" style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", color: "var(--ivory-dim)", fontSize: "0.8rem" }}>
              <th style={{ padding: "0.5rem 0.4rem" }}>#</th>
              <th style={{ padding: "0.5rem 0.4rem" }}>Player</th>
              <th style={{ padding: "0.5rem 0.4rem" }}>Rating</th>
              <th style={{ padding: "0.5rem 0.4rem" }}>Games</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={r.player} style={{ borderTop: "1px solid var(--line)" }}>
                <td style={{ padding: "0.5rem 0.4rem" }}>{i + 1}</td>
                <td style={{ padding: "0.5rem 0.4rem" }}>{short(r.player)}</td>
                <td style={{ padding: "0.5rem 0.4rem", color: "var(--brass-bright)" }}>{r.rating}</td>
                <td style={{ padding: "0.5rem 0.4rem" }}>{r.gamesPlayed}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
