import { useReadContract } from "wagmi";
import { BACKGAMMON_CORE_ADDRESS, BACKGAMMON_CORE_ABI } from "../contracts/backgammonCore";
import { useChainId } from "wagmi";

const W = 760;
const H = 520;
const BAR_W = 46;
const POINT_W = (W - BAR_W) / 12;
const TRI_H = 210;
const CHECKER_R = 17;

// Point layout: bottom row = points 0..11 (left -> right), top row = points 12..23 (right -> left),
// mirroring standard board orientation. Verify this against your contract's point-numbering
// convention (see BackgammonCore.sol _initBoard) before shipping — this is a visual mapping only.
function pointX(i) {
  const half = i < 6 || (i >= 12 && i < 18) ? 0 : 1;
  const col = i < 12 ? i % 6 : 11 - (i % 6) - (i >= 18 ? 0 : 0);
  const localCol = i < 12 ? i % 6 : i % 6;
  const side = i < 6 || (i >= 18 && i < 24) ? "right" : "left";
  const base = i < 12 ? (i < 6 ? i : i) : (i < 18 ? i - 12 : i - 12);
  const slot = i % 12;
  const x = slot < 6 ? slot : slot; // 0..11 across, bar splits after col 5
  const offset = x < 6 ? x : x + 1; // shift right half past the bar
  return offset * POINT_W;
}

function Triangle({ i }) {
  const x = pointX(i);
  const top = i >= 12;
  const dark = i % 2 === 0;
  const fill = dark ? "#16281f" : "#2a4636";
  const points = top
    ? `${x},0 ${x + POINT_W},0 ${x + POINT_W / 2},${TRI_H}`
    : `${x},${H} ${x + POINT_W},${H} ${x + POINT_W / 2},${H - TRI_H}`;
  return <polygon points={points} fill={fill} stroke="rgba(0,0,0,0.25)" strokeWidth="1" />;
}

function Checkers({ i, count }) {
  if (count === 0) return null;
  const x = pointX(i) + POINT_W / 2;
  const top = i >= 12;
  const player = count > 0 ? "A" : "B";
  const n = Math.abs(count);
  const color = player === "A" ? "var(--oxblood-bright)" : "var(--ivory)";
  const stroke = player === "A" ? "#4a1414" : "#8a8172";

  return (
    <>
      {Array.from({ length: Math.min(n, 5) }).map((_, k) => {
        const cy = top ? 24 + k * (CHECKER_R * 2 + 2) : H - 24 - k * (CHECKER_R * 2 + 2);
        return <circle key={k} cx={x} cy={cy} r={CHECKER_R} fill={color} stroke={stroke} strokeWidth="2" />;
      })}
      {n > 5 && (
        <text
          x={x}
          y={top ? 24 + 4 * (CHECKER_R * 2 + 2) : H - 24 - 4 * (CHECKER_R * 2 + 2)}
          textAnchor="middle"
          fontFamily="var(--mono)"
          fontSize="13"
          fill={player === "A" ? "var(--ivory)" : "var(--ink)"}
        >
          {n}
        </text>
      )}
    </>
  );
}

export default function Board({ gameId }) {
  const chainId = useChainId();
  const address = BACKGAMMON_CORE_ADDRESS[chainId];

  const { data: board } = useReadContract({
    address,
    abi: BACKGAMMON_CORE_ABI,
    functionName: "getBoard",
    args: [gameId],
    query: { enabled: gameId !== undefined && !!address },
  });

  const { data: gameState } = useReadContract({
    address,
    abi: BACKGAMMON_CORE_ABI,
    functionName: "getGame",
    args: [gameId],
    query: { enabled: gameId !== undefined && !!address },
  });

  const points = board || Array(24).fill(0);
  const bar = gameState ? gameState[4] : [0, 0];
  const borneOff = gameState ? gameState[5] : [0, 0];

  return (
    <div className="panel" style={{ padding: "1.5rem", position: "relative" }}>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ display: "block", maxWidth: 760 }}>
        <rect x="0" y="0" width={W} height={H} fill="var(--felt)" rx="6" />
        <rect x={POINT_W * 6} y="0" width={BAR_W} height={H} fill="var(--felt-dark)" />
        {Array.from({ length: 24 }).map((_, i) => (
          <Triangle key={i} i={i} />
        ))}
        {points.map((count, i) => (
          <Checkers key={i} i={i} count={Number(count)} />
        ))}
      </svg>

      <div style={{ display: "flex", justifyContent: "space-between", marginTop: "1rem" }}>
        <div className="mono" style={{ fontSize: "0.8rem", color: "var(--oxblood-bright)" }}>
          Player A — bar: {bar?.[0] ?? 0} · off: {borneOff?.[0] ?? 0}
        </div>
        <div className="mono" style={{ fontSize: "0.8rem", color: "var(--ivory-dim)" }}>
          Player B — bar: {bar?.[1] ?? 0} · off: {borneOff?.[1] ?? 0}
        </div>
      </div>
    </div>
  );
}
