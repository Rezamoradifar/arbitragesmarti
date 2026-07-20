import { useEffect, useRef, useState } from "react";
import { useAccount, useChainId, useWriteContract } from "wagmi";
import { keccak256, encodePacked, toHex } from "viem";
import { BACKGAMMON_CORE_ADDRESS, BACKGAMMON_CORE_ABI } from "../contracts/backgammonCore";

// Secrets live in localStorage keyed by game+address so a page refresh
// between commit and reveal doesn't lose the value you need to reveal.
function secretKey(gameId, address) {
  return `bg-secret-${gameId}-${address}`;
}

function randomSecret() {
  const bytes = crypto.getRandomValues(new Uint8Array(1));
  const salt = toHex(crypto.getRandomValues(new Uint8Array(32)));
  return { secretValue: bytes[0], salt };
}

export default function DiceRoll({ gameId, phase }) {
  const { address } = useAccount();
  const chainId = useChainId();
  const contractAddress = BACKGAMMON_CORE_ADDRESS[chainId];
  const { writeContractAsync, isPending } = useWriteContract();
  const [hasCommitted, setHasCommitted] = useState(false);
  const [error, setError] = useState(null);
  const [autoRevealing, setAutoRevealing] = useState(false);
  const autoRevealTried = useRef(false);

  useEffect(() => {
    setHasCommitted(!!localStorage.getItem(secretKey(gameId, address)));
  }, [gameId, address, phase]);

  // The contract only enters RevealRoll once BOTH players have committed,
  // so the moment this phase is reached it's always safe to reveal --
  // don't make the player click a second button for something that's
  // already guaranteed to succeed (or fail the same way a manual click would).
  useEffect(() => {
    autoRevealTried.current = false;
  }, [gameId, phase]);

  useEffect(() => {
    if (phase !== "RevealRoll") return;
    if (autoRevealTried.current) return;
    if (!localStorage.getItem(secretKey(gameId, address))) return;
    autoRevealTried.current = true;
    setAutoRevealing(true);
    handleReveal().finally(() => setAutoRevealing(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, gameId, address]);

  async function handleCommit() {
    setError(null);
    const { secretValue, salt } = randomSecret();
    const commitHash = keccak256(
      encodePacked(["uint8", "bytes32", "address"], [secretValue, salt, address])
    );

    try {
      await writeContractAsync({
        address: contractAddress,
        abi: BACKGAMMON_CORE_ABI,
        functionName: "commitRoll",
        args: [gameId, commitHash],
      });
      // Only persist the secret once the commit transaction actually lands --
      // saving it earlier (then failing/rejecting the tx) would strand the
      // button in a permanent "Committed" state with nothing on-chain.
      localStorage.setItem(secretKey(gameId, address), JSON.stringify({ secretValue, salt }));
      setHasCommitted(true);
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to commit roll");
    }
  }

  async function handleReveal() {
    setError(null);
    const raw = localStorage.getItem(secretKey(gameId, address));
    if (!raw) return;
    const { secretValue, salt } = JSON.parse(raw);

    try {
      await writeContractAsync({
        address: contractAddress,
        abi: BACKGAMMON_CORE_ABI,
        functionName: "revealRoll",
        args: [gameId, secretValue, salt],
      });
      localStorage.removeItem(secretKey(gameId, address));
    } catch (e) {
      setError(e.shortMessage || e.message || "Failed to reveal roll");
    }
  }

  if (phase === "CommitRoll") {
    return (
      <div className="panel" style={{ padding: "1.5rem", textAlign: "center" }}>
        <div className="eyebrow">Roll the dice</div>
        <p style={{ color: "var(--ivory-dim)", maxWidth: 380, margin: "0.6rem auto 1.2rem" }}>
          Commit a hidden random value. Once both players have committed,
          you'll reveal it to generate this turn's roll — neither side can
          bias the outcome alone.
        </p>
        <button className="btn-primary" disabled={isPending || hasCommitted} onClick={handleCommit}>
          {hasCommitted ? "Committed — waiting for opponent" : isPending ? "Confirm in wallet…" : "Commit Roll"}
        </button>
        {error && <p style={{ color: "var(--oxblood-bright)", marginTop: "0.8rem" }}>{error}</p>}
      </div>
    );
  }

  if (phase === "RevealRoll") {
    const alreadyRevealed = !localStorage.getItem(secretKey(gameId, address));
    return (
      <div className="panel" style={{ padding: "1.5rem", textAlign: "center" }}>
        <div className="eyebrow">Reveal your roll</div>
        <p style={{ color: "var(--ivory-dim)", maxWidth: 380, margin: "0.6rem auto 1.2rem" }}>
          Both players have committed — reveals happen automatically to
          combine the dice.
        </p>
        {alreadyRevealed && !error ? (
          <p style={{ color: "var(--ivory-dim)" }}>Revealed — waiting for opponent…</p>
        ) : (
          <button className="btn-primary" disabled={isPending} onClick={handleReveal}>
            {isPending || autoRevealing ? "Confirm in wallet…" : error ? "Retry reveal" : "Revealing…"}
          </button>
        )}
        {error && <p style={{ color: "var(--oxblood-bright)", marginTop: "0.8rem" }}>{error}</p>}
      </div>
    );
  }

  return null;
}
