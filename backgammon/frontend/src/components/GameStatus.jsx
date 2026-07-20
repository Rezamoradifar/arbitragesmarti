import { useAccount, useChainId, useReadContract } from "wagmi";
import { BACKGAMMON_CORE_ADDRESS, BACKGAMMON_CORE_ABI, GAME_PHASE } from "../contracts/backgammonCoreV2";
import DiceRoll from "./DiceRoll";
import MovePanel from "./MovePanel";
import Timer from "./Timer";
import DoublingCube from "./DoublingCube";

export default function GameStatus({ gameId, wagerAmount }) {
  const { address } = useAccount();
  const chainId = useChainId();
  const contractAddress = BACKGAMMON_CORE_ADDRESS[chainId];

  const { data: gameState } = useReadContract({
    address: contractAddress,
    abi: BACKGAMMON_CORE_ABI,
    functionName: "getGame",
    args: [gameId],
    query: { enabled: gameId !== undefined && !!contractAddress, refetchInterval: 4000 },
  });

  if (!gameState) return null;

  const [playerA, playerB, phaseIdx, turn] = gameState;
  const phase = GAME_PHASE[phaseIdx] ?? "None";
  const turnPlayer = turn === 0 ? playerA : playerB;
  const isMyTurn = address && turnPlayer?.toLowerCase() === address.toLowerCase();
  const turnLabel = turn === 0 ? "Player A" : "Player B";

  return (
    <>
      <div className="status-row" style={{ display: "flex", gap: "1rem", margin: "1.5rem 0" }}>
        <div className="panel" style={{ flex: 1, padding: "1rem 1.2rem" }}>
          <div className="eyebrow">Phase</div>
          <div style={{ fontFamily: "var(--display)", fontSize: "1.2rem", marginTop: "0.3rem" }}>{phase}</div>
        </div>
        <div className="panel" style={{ flex: 1, padding: "1rem 1.2rem" }}>
          <div className="eyebrow">Turn</div>
          <div style={{ fontFamily: "var(--display)", fontSize: "1.2rem", marginTop: "0.3rem", color: "var(--oxblood-bright)" }}>
            {turnLabel}
          </div>
        </div>
        <div className="panel" style={{ flex: 1, padding: "1rem 1.2rem" }}>
          <div className="eyebrow">Table</div>
          <div className="mono" style={{ fontSize: "1.2rem", marginTop: "0.3rem", color: "var(--brass-bright)" }}>
            #{gameId.toString().padStart(4, "0")}
          </div>
        </div>
      </div>

      {(phase === "CommitRoll" || phase === "RevealRoll") && isMyTurn === undefined ? null : null}

      <Timer gameId={gameId} phase={phase} />

      <DoublingCube
        gameId={gameId}
        phase={phase}
        playerA={playerA}
        playerB={playerB}
        turn={turn}
        wagerAmount={wagerAmount}
      />

      {phase === "CommitRoll" || phase === "RevealRoll" ? (
        <DiceRoll gameId={gameId} phase={phase} />
      ) : phase === "DoubleOffered" ? null : phase === "Move" ? (
        <MovePanel gameId={gameId} isMyTurn={isMyTurn} />
      ) : phase === "Finished" ? (
        <div className="panel" style={{ padding: "1.5rem", textAlign: "center" }}>
          <div className="eyebrow">Game over</div>
          <p style={{ marginTop: "0.6rem" }}>Winner: <span className="mono">{gameState[6]}</span></p>
        </div>
      ) : null}
    </>
  );
}
