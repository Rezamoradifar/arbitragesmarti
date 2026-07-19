import { useEffect, useRef, useState } from "react";
import { useChainId, useReadContract, useWriteContract } from "wagmi";
import { BACKGAMMON_CORE_ADDRESS, BACKGAMMON_CORE_ABI } from "../contracts/backgammonCore";
import { useFeedbackContext } from "../context/FeedbackContext";

export default function Timer({ gameId, phase }) {
  const chainId = useChainId();
  const address = BACKGAMMON_CORE_ADDRESS[chainId];
  const { writeContractAsync, isPending } = useWriteContract();
  const { trigger } = useFeedbackContext();

  const { data: timing } = useReadContract({
    address,
    abi: BACKGAMMON_CORE_ABI,
    functionName: "getTiming",
    args: [gameId],
    query: { enabled: !!address && gameId !== undefined, refetchInterval: 5000 },
  });

  const [remaining, setRemaining] = useState(null);
  const lowFired = useRef(false);
  const expiredFired = useRef(false);

  useEffect(() => {
    if (!timing) return;
    const deadline = Number(timing[0]);
    const total = Number(timing[1]);
    lowFired.current = false;
    expiredFired.current = false;

    const tick = () => {
      const now = Math.floor(Date.now() / 1000);
      const left = Math.max(0, deadline - now);
      setRemaining({ left, total });

      if (left <= 10 && left > 0 && !lowFired.current) {
        lowFired.current = true;
        trigger("timerLow");
      }
      if (left === 0 && !expiredFired.current) {
        expiredFired.current = true;
        trigger("timeout");
      }
    };

    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [timing, trigger]);

  if (phase === "Finished" || phase === "None" || phase === "WaitingForOpponent" || !remaining) return null;

  const pct = remaining.total > 0 ? Math.max(0, Math.min(100, (remaining.left / remaining.total) * 100)) : 0;
  const urgent = remaining.left <= 15;

  async function handleClaimTimeout() {
    await writeContractAsync({
      address,
      abi: BACKGAMMON_CORE_ABI,
      functionName: "claimTimeout",
      args: [gameId],
    });
  }

  return (
    <div className="panel" style={{ padding: "1rem 1.2rem", marginBottom: "1rem" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.5rem" }}>
        <span className="eyebrow">Time to act</span>
        <span className="mono" style={{ color: urgent ? "var(--oxblood-bright)" : "var(--brass-bright)", fontWeight: 600 }}>
          {remaining.left}s
        </span>
      </div>
      <div style={{ height: 6, background: "var(--ink)", borderRadius: 3, overflow: "hidden" }}>
        <div
          style={{
            height: "100%",
            width: `${pct}%`,
            background: urgent ? "var(--oxblood-bright)" : "var(--brass)",
            transition: "width 1s linear, background 300ms ease",
          }}
        />
      </div>
      {remaining.left === 0 && (
        <button
          className="btn-primary"
          style={{ marginTop: "0.9rem", width: "100%" }}
          disabled={isPending}
          onClick={handleClaimTimeout}
        >
          {isPending ? "Confirm in wallet…" : "Claim win — opponent timed out"}
        </button>
      )}
    </div>
  );
}
