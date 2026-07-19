import { useEffect, useState } from "react";
import { useAccount, useChainId, usePublicClient, useWriteContract } from "wagmi";
import { parseEther, formatEther } from "viem";
import { TOURNAMENT_ADDRESS, TOURNAMENT_ABI, TOURNAMENT_DEPLOY_BLOCK } from "../contracts/backgammonTournament";
import { getLogsSafe } from "../contracts/getLogsSafe";

function short(addr) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export default function Tournaments() {
  const chainId = useChainId();
  const { address: me } = useAccount();
  const publicClient = usePublicClient();
  const { writeContractAsync, isPending } = useWriteContract();

  const [tournaments, setTournaments] = useState(null);
  const [error, setError] = useState(null);
  const [limitedHistory, setLimitedHistory] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [entryFee, setEntryFee] = useState("0.01");
  const [maxPlayers, setMaxPlayers] = useState("8");

  const contractAddress = TOURNAMENT_ADDRESS[chainId];

  async function load() {
    if (!contractAddress || !publicClient) return;
    setError(null);
    try {
      const [created, finalized] = await Promise.all([
        getLogsSafe(publicClient, {
          address: contractAddress,
          event: TOURNAMENT_ABI.find((e) => e.name === "TournamentCreated"),
          fromBlock: TOURNAMENT_DEPLOY_BLOCK[chainId],
        }),
        getLogsSafe(publicClient, {
          address: contractAddress,
          event: TOURNAMENT_ABI.find((e) => e.name === "TournamentFinalized"),
          fromBlock: TOURNAMENT_DEPLOY_BLOCK[chainId],
        }),
      ]);
      const createdLogs = created.logs;
      setLimitedHistory(created.limitedHistory || finalized.limitedHistory);

      const finalizedIds = new Set(finalized.logs.map((l) => l.args.id.toString()));

      const rows = await Promise.all(
        createdLogs.map(async (log) => {
          const id = log.args.id;
          const players = await publicClient.readContract({
            address: contractAddress,
            abi: TOURNAMENT_ABI,
            functionName: "getPlayers",
            args: [id],
          });
          return {
            id,
            organizer: log.args.organizer,
            entryFee: log.args.entryFee,
            maxPlayers: log.args.maxPlayers,
            playerCount: players.length,
            joined: me ? players.some((p) => p.toLowerCase() === me.toLowerCase()) : false,
            finalized: finalizedIds.has(id.toString()),
          };
        })
      );

      setTournaments(rows.reverse());
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to load tournaments");
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chainId, publicClient, me]);

  async function handleCreate() {
    await writeContractAsync({
      address: contractAddress,
      abi: TOURNAMENT_ABI,
      functionName: "createTournament",
      args: [
        "0x0000000000000000000000000000000000000000",
        parseEther(entryFee),
        BigInt(maxPlayers),
        [6000, 3000, 1000], // 60/30/10 payout split across 1st/2nd/3rd
      ],
    });
    setShowCreate(false);
    load();
  }

  async function handleRegister(t) {
    await writeContractAsync({
      address: contractAddress,
      abi: TOURNAMENT_ABI,
      functionName: "register",
      args: [t.id],
      value: t.entryFee,
    });
    load();
  }

  async function handleClaim(t) {
    await writeContractAsync({
      address: contractAddress,
      abi: TOURNAMENT_ABI,
      functionName: "claimPrize",
      args: [t.id],
    });
    load();
  }

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.2rem" }}>
        <div>
          <div className="eyebrow">Compete</div>
          <h2 style={{ margin: "0.4rem 0 0" }}>Tournaments</h2>
        </div>
        <button className="btn-primary" onClick={() => setShowCreate((s) => !s)}>
          {showCreate ? "Cancel" : "Create tournament"}
        </button>
      </div>

      {showCreate && (
        <div className="panel" style={{ padding: "1.2rem", marginBottom: "1.2rem" }}>
          <label style={{ display: "block", marginBottom: "0.8rem" }}>
            <span className="mono" style={{ fontSize: "0.8rem", color: "var(--ivory-dim)" }}>Entry fee (BNB)</span>
            <input
              value={entryFee}
              onChange={(e) => setEntryFee(e.target.value)}
              className="mono"
              style={{ display: "block", width: "100%", marginTop: "0.3rem", padding: "0.5rem", background: "var(--ink)", border: "1px solid var(--line)", color: "var(--ivory)", borderRadius: "3px" }}
            />
          </label>
          <label style={{ display: "block", marginBottom: "1rem" }}>
            <span className="mono" style={{ fontSize: "0.8rem", color: "var(--ivory-dim)" }}>Max players</span>
            <input
              value={maxPlayers}
              onChange={(e) => setMaxPlayers(e.target.value)}
              className="mono"
              style={{ display: "block", width: "100%", marginTop: "0.3rem", padding: "0.5rem", background: "var(--ink)", border: "1px solid var(--line)", color: "var(--ivory)", borderRadius: "3px" }}
            />
          </label>
          <p style={{ fontSize: "0.78rem", color: "var(--ivory-dim)" }}>
            Prize pool splits 60% / 30% / 10% across 1st / 2nd / 3rd place.
            Standings are submitted by the organizer once matches finish.
          </p>
          <button className="btn-primary" disabled={isPending} onClick={handleCreate}>
            {isPending ? "Confirm in wallet…" : "Create"}
          </button>
        </div>
      )}

      {limitedHistory && !error && (
        <p style={{ color: "var(--ivory-dim)", fontSize: "0.78rem", marginBottom: "1rem" }}>
          This public RPC only keeps recent block history — showing recent
          activity only. Point the app at an archive RPC for full history.
        </p>
      )}
      {error && <p style={{ color: "var(--oxblood-bright)" }}>{error}</p>}
      {!error && tournaments === null && <p style={{ color: "var(--ivory-dim)" }}>Loading tournaments…</p>}
      {!error && tournaments && tournaments.length === 0 && (
        <p style={{ color: "var(--ivory-dim)" }}>No tournaments yet on this network. Be the first to create one.</p>
      )}

      <div style={{ display: "grid", gap: "0.8rem" }}>
        {tournaments?.map((t) => (
          <div key={t.id.toString()} className="panel" style={{ padding: "1rem 1.2rem", display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "0.6rem" }}>
            <div>
              <div className="mono" style={{ fontSize: "0.9rem" }}>Tournament #{t.id.toString()}</div>
              <div style={{ color: "var(--ivory-dim)", fontSize: "0.82rem" }}>
                {formatEther(t.entryFee)} BNB entry · {t.playerCount}/{t.maxPlayers.toString()} players · organizer {short(t.organizer)}
                {t.finalized && " · finalized"}
              </div>
            </div>
            {!t.finalized && !t.joined && (
              <button className="btn-ghost" disabled={isPending} onClick={() => handleRegister(t)}>
                Register
              </button>
            )}
            {!t.finalized && t.joined && <span className="mono" style={{ fontSize: "0.8rem", color: "var(--brass-bright)" }}>Registered</span>}
            {t.finalized && (
              <button className="btn-ghost" disabled={isPending} onClick={() => handleClaim(t)}>
                Claim prize
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
