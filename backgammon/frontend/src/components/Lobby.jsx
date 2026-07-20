import { useEffect, useState } from "react";
import { useAccount, useChainId, usePublicClient, useWriteContract } from "wagmi";
import { formatEther, parseEther, parseEventLogs } from "viem";
import { BACKGAMMON_CORE_ADDRESS, BACKGAMMON_CORE_ABI, BACKGAMMON_CORE_DEPLOY_BLOCK } from "../contracts/backgammonCoreV2";
import { getLogsSafe } from "../contracts/getLogsSafe";
import Spinner from "./Spinner";

// BackgammonCoreV2 has not had a professional Solidity audit (see
// backgammon/README.md). Enabled on mainnet at the operator's explicit
// request and acknowledged risk -- real BNB wagers are settled by
// unaudited contract code. Keep the in-app risk notice below in sync
// with this flag.
const MAINNET_WAGERING_ENABLED = true;

function short(addr) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export default function Lobby({ onEnterGame }) {
  const chainId = useChainId();
  const { address: me } = useAccount();
  const address = BACKGAMMON_CORE_ADDRESS[chainId];
  const publicClient = usePublicClient();
  const { writeContractAsync, isPending } = useWriteContract();

  const wagerAllowed = MAINNET_WAGERING_ENABLED || chainId !== 56;
  const [mode, setMode] = useState("free"); // "free" | "wager"
  const [stake, setStake] = useState("0.05");
  const [joinId, setJoinId] = useState("");
  const [error, setError] = useState(null);

  const [openTables, setOpenTables] = useState(null);
  const [tablesError, setTablesError] = useState(null);
  const [limitedHistory, setLimitedHistory] = useState(false);

  async function loadOpenTables() {
    if (!address || !publicClient) return;
    setTablesError(null);
    try {
      const [created, joined] = await Promise.all([
        getLogsSafe(publicClient, {
          address,
          event: BACKGAMMON_CORE_ABI.find((e) => e.name === "GameCreated"),
          fromBlock: BACKGAMMON_CORE_DEPLOY_BLOCK[chainId],
        }),
        getLogsSafe(publicClient, {
          address,
          event: BACKGAMMON_CORE_ABI.find((e) => e.name === "GameJoined"),
          fromBlock: BACKGAMMON_CORE_DEPLOY_BLOCK[chainId],
        }),
      ]);
      setLimitedHistory(created.limitedHistory || joined.limitedHistory);
      const joinedIds = new Set(joined.logs.map((l) => l.args.gameId.toString()));
      const rows = created.logs
        .filter((l) => !joinedIds.has(l.args.gameId.toString()))
        .map((l) => ({
          gameId: l.args.gameId,
          creator: l.args.creator,
          wager: l.args.wager,
        }))
        .reverse();
      setOpenTables(rows);
    } catch (e) {
      setTablesError(e.shortMessage || e.message || "Failed to load open tables");
    }
  }

  useEffect(() => {
    loadOpenTables();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chainId, publicClient, address]);

  async function handleCreate() {
    setError(null);
    try {
      const wagerAmount = mode === "wager" && wagerAllowed ? parseEther(stake) : 0n;
      const hash = await writeContractAsync({
        address,
        abi: BACKGAMMON_CORE_ABI,
        functionName: "createGame",
        args: [wagerAmount, "0x0000000000000000000000000000000000000000"],
        value: wagerAmount,
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const [event] = parseEventLogs({
        abi: [BACKGAMMON_CORE_ABI.find((e) => e.name === "GameCreated")],
        logs: receipt.logs,
      });
      if (!event) throw new Error("Game was created but the confirmation event wasn't found");
      onEnterGame?.(event.args.gameId, wagerAmount);
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to create table");
    }
  }

  async function joinById(id, wagerAmount) {
    setError(null);
    try {
      await writeContractAsync({
        address,
        abi: BACKGAMMON_CORE_ABI,
        functionName: "joinGame",
        args: [id],
      });
      onEnterGame?.(id, wagerAmount);
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to join table");
    }
  }

  async function handleJoin() {
    if (!joinId) return;
    await joinById(BigInt(joinId));
  }

  return (
    <div>
      <div className="lobby-grid" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1.25rem", marginBottom: "1.25rem" }}>
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

          {wagerAllowed && mode === "wager" && chainId === 56 && (
            <p style={{ color: "var(--oxblood-bright)", fontSize: "0.78rem", marginBottom: "1rem" }}>
              ⚠ BackgammonCoreV2 has not had a professional security audit.
              You're wagering real BNB against unaudited contract code —
              play at your own risk.
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

      {error && (
        <p className="panel" style={{ padding: "0.9rem 1.2rem", color: "var(--oxblood-bright)", marginBottom: "1.25rem" }}>
          {error}
        </p>
      )}

      <div className="panel" style={{ padding: "1.5rem" }}>
        <div className="eyebrow">Waiting for an opponent</div>
        <h3 style={{ margin: "0.4rem 0 1rem" }}>Open tables</h3>

        {limitedHistory && !tablesError && (
          <p style={{ color: "var(--ivory-dim)", fontSize: "0.78rem", marginBottom: "1rem" }}>
            This public RPC only keeps recent block history — showing recent
            tables only.
          </p>
        )}
        {tablesError && <p style={{ color: "var(--oxblood-bright)" }}>{tablesError}</p>}
        {!tablesError && openTables === null && <Spinner label="Loading open tables…" />}
        {!tablesError && openTables && openTables.length === 0 && (
          <p style={{ color: "var(--ivory-dim)" }}>No open tables right now — create one above.</p>
        )}

        <div style={{ display: "grid", gap: "0.6rem" }}>
          {openTables?.map((t) => (
            <div
              key={t.gameId.toString()}
              className="panel panel-interactive"
              style={{ padding: "0.8rem 1rem", display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "0.5rem" }}
            >
              <div className="mono" style={{ fontSize: "0.85rem" }}>
                #{t.gameId.toString()} · {t.wager > 0n ? `${formatEther(t.wager)} BNB wager` : "free play"} · by {short(t.creator)}
              </div>
              {me?.toLowerCase() === t.creator.toLowerCase() ? (
                <span className="mono" style={{ fontSize: "0.8rem", color: "var(--ivory-dim)" }}>Your table</span>
              ) : (
                <button className="btn-ghost" disabled={isPending} onClick={() => joinById(t.gameId, t.wager)}>
                  Join
                </button>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
