import { useState } from "react";
import { useChainId, useWriteContract } from "wagmi";
import { parseEther } from "viem";
import { BACKGAMMON_CORE_ADDRESS, BACKGAMMON_CORE_ABI } from "../contracts/backgammonCore";

// BackgammonCore has not had a professional Solidity audit yet (see
// backgammon/README.md). Keep real-money wagering off on mainnet until
// that's done -- testnet wagering is fine since tBNB has no value.
const MAINNET_WAGERING_ENABLED = false;

export default function Lobby({ onEnterGame }) {
  const chainId = useChainId();
  const address = BACKGAMMON_CORE_ADDRESS[chainId];
  const { writeContractAsync, isPending } = useWriteContract();

  const wagerAllowed = MAINNET_WAGERING_ENABLED || chainId !== 56;
  const [mode, setMode] = useState("free"); // "free" | "wager"
  const [stake, setStake] = useState("0.05");
  const [joinId, setJoinId] = useState("");

  async function handleCreate() {
    const wagerAmount = mode === "wager" && wagerAllowed ? parseEther(stake) : 0n;
    const hash = await writeContractAsync({
      address,
      abi: BACKGAMMON_CORE_ABI,
      functionName: "createGame",
      args: [wagerAmount, "0x0000000000000000000000000000000000000000"],
      value: wagerAmount,
    });
    // In production: wait for the tx receipt and read the GameCreated event
    // to get the real gameId instead of guessing.
    onEnterGame?.(hash);
  }

  async function handleJoin() {
    if (!joinId) return;
    await writeContractAsync({
      address,
      abi: BACKGAMMON_CORE_ABI,
      functionName: "joinGame",
      args: [BigInt(joinId)],
    });
    onEnterGame?.(joinId);
  }

  return (
    <div className="lobby-grid" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1.25rem" }}>
      <div className="panel" style={{ padding: "1.5rem" }}>
        <div className="eyebrow">New table</div>
        <h3 style={{ margin: "0.4rem 0 1rem" }}>Start a game</h3>

        <div style={{ display: "flex", gap: "0.5rem", marginBottom: "1rem" }}>
          <button
            className={mode === "free" ? "btn-primary" : "btn-ghost"}
            onClick={() => setMode("free")}
          >
            Free play
          </button>
          <button
            className={mode === "wager" ? "btn-primary" : "btn-ghost"}
            onClick={() => setMode("wager")}
            disabled={!wagerAllowed}
            title={wagerAllowed ? undefined : "Wagering is disabled on mainnet until BackgammonCore has a professional audit"}
          >
            Wager BNB
          </button>
        </div>

        {!wagerAllowed && (
          <p style={{ color: "var(--ivory-dim)", fontSize: "0.8rem", marginBottom: "1rem" }}>
            Real-money wagering is disabled on mainnet until BackgammonCore
            has a professional audit. Switch to BSC Testnet to try wagered
            games with tBNB.
          </p>
        )}

        {mode === "wager" && wagerAllowed && (
          <label style={{ display: "block", marginBottom: "1rem" }}>
            <span className="mono" style={{ fontSize: "0.8rem", color: "var(--ivory-dim)" }}>
              Stake per player (BNB)
            </span>
            <input
              value={stake}
              onChange={(e) => setStake(e.target.value)}
              className="mono"
              style={{
                display: "block",
                width: "100%",
                marginTop: "0.4rem",
                padding: "0.6rem",
                background: "var(--ink)",
                border: "1px solid var(--line)",
                color: "var(--ivory)",
                borderRadius: "3px",
              }}
            />
          </label>
        )}

        <button className="btn-primary" disabled={isPending} onClick={handleCreate}>
          {isPending ? "Confirm in wallet…" : "Create table"}
        </button>
      </div>

      <div className="panel" style={{ padding: "1.5rem" }}>
        <div className="eyebrow">Have a table ID?</div>
        <h3 style={{ margin: "0.4rem 0 1rem" }}>Join a game</h3>
        <input
          value={joinId}
          onChange={(e) => setJoinId(e.target.value)}
          placeholder="Game ID"
          className="mono"
          style={{
            display: "block",
            width: "100%",
            marginBottom: "1rem",
            padding: "0.6rem",
            background: "var(--ink)",
            border: "1px solid var(--line)",
            color: "var(--ivory)",
            borderRadius: "3px",
          }}
        />
        <button className="btn-primary" disabled={isPending} onClick={handleJoin}>
          {isPending ? "Confirm in wallet…" : "Join table"}
        </button>
      </div>
    </div>
  );
}
