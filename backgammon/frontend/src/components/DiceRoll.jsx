import { useEffect, useState } from "react";
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

  useEffect(() => {
    setHasCommitted(!!localStorage.getItem(secretKey(gameId, address)));
  }, [gameId, address, phase]);

  async function handleCommit() {
    const { secretValue, salt } = randomSecret();
    localStorage.setItem(secretKey(gameId, address), JSON.stringify({ secretValue, salt }));

    const commitHash = keccak256(
      encodePacked(["uint8", "bytes32", "address"], [secretValue, salt, address])
    );

    await writeContractAsync({
      address: contractAddress,
      abi: BACKGAMMON_CORE_ABI,
      functionName: "commitRoll",
      args: [gameId, commitHash],
    });
    setHasCommitted(true);
  }

  async function handleReveal() {
    const raw = localStorage.getItem(secretKey(gameId, address));
    if (!raw) return;
    const { secretValue, salt } = JSON.parse(raw);

    await writeContractAsync({
      address: contractAddress,
      abi: BACKGAMMON_CORE_ABI,
      functionName: "revealRoll",
      args: [gameId, secretValue, salt],
    });
    localStorage.removeItem(secretKey(gameId, address));
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
      </div>
    );
  }

  if (phase === "RevealRoll") {
    return (
      <div className="panel" style={{ padding: "1.5rem", textAlign: "center" }}>
        <div className="eyebrow">Reveal your roll</div>
        <p style={{ color: "var(--ivory-dim)", maxWidth: 380, margin: "0.6rem auto 1.2rem" }}>
          Both players have committed. Reveal your secret to combine the dice.
        </p>
        <button className="btn-primary" disabled={isPending} onClick={handleReveal}>
          {isPending ? "Confirm in wallet…" : "Reveal Roll"}
        </button>
      </div>
    );
  }

  return null;
}
