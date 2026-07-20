import { useEffect, useState } from "react";
import { useAccount, useChainId, useReadContract, useWriteContract } from "wagmi";
import { formatEther } from "viem";
import { BACKGAMMON_CORE_ADDRESS, BACKGAMMON_CORE_ABI } from "../contracts/backgammonCoreV2";

export default function DoublingCube({ gameId, phase, playerA, playerB, turn, wagerAmount }) {
  const { address } = useAccount();
  const chainId = useChainId();
  const contractAddress = BACKGAMMON_CORE_ADDRESS[chainId];
  const { writeContractAsync, isPending } = useWriteContract();
  const [error, setError] = useState(null);

  const { data: cube, refetch } = useReadContract({
    address: contractAddress,
    abi: BACKGAMMON_CORE_ABI,
    functionName: "getCube",
    args: [gameId],
    query: { enabled: gameId !== undefined && !!contractAddress, refetchInterval: 4000 },
  });

  useEffect(() => {
    refetch?.();
  }, [phase, refetch]);

  if (!cube || wagerAmount === null || wagerAmount === undefined || wagerAmount === 0n) return null;

  const [cubeValue, cubeOwner, doubleOfferedBy] = cube;
  const turnPlayer = turn === 0 ? playerA : playerB;
  const isMyTurn = address && turnPlayer?.toLowerCase() === address.toLowerCase();
  const iOwnCube =
    cubeOwner === "0x0000000000000000000000000000000000000000" ||
    (address && cubeOwner?.toLowerCase() === address.toLowerCase());
  const topUp = wagerAmount * BigInt(cubeValue);

  async function handleOffer() {
    setError(null);
    try {
      await writeContractAsync({
        address: contractAddress,
        abi: BACKGAMMON_CORE_ABI,
        functionName: "offerDouble",
        args: [gameId],
        value: topUp,
      });
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to offer double");
    }
  }

  async function handleAccept() {
    setError(null);
    try {
      await writeContractAsync({
        address: contractAddress,
        abi: BACKGAMMON_CORE_ABI,
        functionName: "acceptDouble",
        args: [gameId],
        value: topUp,
      });
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to accept double");
    }
  }

  async function handleDecline() {
    setError(null);
    try {
      await writeContractAsync({
        address: contractAddress,
        abi: BACKGAMMON_CORE_ABI,
        functionName: "declineDouble",
        args: [gameId],
      });
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to decline double");
    }
  }

  if (phase === "DoubleOffered") {
    const iOffered = address && doubleOfferedBy?.toLowerCase() === address.toLowerCase();
    return (
      <div className="panel" style={{ padding: "1.2rem 1.4rem", marginBottom: "1rem", textAlign: "center" }}>
        <div className="eyebrow">Doubling cube</div>
        {iOffered ? (
          <p style={{ margin: "0.5rem 0 0", color: "var(--ivory-dim)" }}>
            You offered to double to <strong className="mono">{cubeValue * 2}x</strong> — waiting for your opponent…
          </p>
        ) : (
          <>
            <p style={{ margin: "0.5rem 0 0.9rem" }}>
              Your opponent offered to double the stake to <strong className="mono">{cubeValue * 2}x</strong>
              {" "}({formatEther(topUp)} BNB top-up each).
            </p>
            <div style={{ display: "flex", gap: "0.6rem", justifyContent: "center" }}>
              <button className="btn-primary" disabled={isPending} onClick={handleAccept}>
                {isPending ? "Confirm in wallet…" : `Accept (${formatEther(topUp)} BNB)`}
              </button>
              <button className="btn-ghost" disabled={isPending} onClick={handleDecline}>
                Decline (forfeit at {cubeValue}x)
              </button>
            </div>
          </>
        )}
        {error && <p style={{ color: "var(--oxblood-bright)", marginTop: "0.8rem" }}>{error}</p>}
      </div>
    );
  }

  const canOffer = phase === "CommitRoll" && isMyTurn && iOwnCube && cubeValue < 8;

  return (
    <div className="panel" style={{ padding: "0.8rem 1.2rem", marginBottom: "1rem", display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "0.6rem" }}>
      <div className="mono" style={{ fontSize: "0.85rem", color: "var(--ivory-dim)" }}>
        Cube: <span style={{ color: "var(--brass-bright)" }}>{cubeValue}x</span>
        {cubeOwner !== "0x0000000000000000000000000000000000000000" && (
          <> · owned by {address && cubeOwner?.toLowerCase() === address.toLowerCase() ? "you" : "opponent"}</>
        )}
      </div>
      {canOffer && (
        <button className="btn-ghost" disabled={isPending} onClick={handleOffer}>
          {isPending ? "Confirm in wallet…" : `Offer double to ${cubeValue * 2}x (${formatEther(topUp)} BNB)`}
        </button>
      )}
      {error && <p style={{ color: "var(--oxblood-bright)", width: "100%" }}>{error}</p>}
    </div>
  );
}
