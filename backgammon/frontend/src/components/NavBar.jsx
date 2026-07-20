import { HomeIcon, DiceIcon, TrophyIcon, ChartIcon, BookIcon } from "./icons";

const TABS = [
  { id: "home", label: "Home", Icon: HomeIcon },
  { id: "play", label: "Play", Icon: DiceIcon },
  { id: "tournaments", label: "Tournaments", Icon: TrophyIcon },
  { id: "leaderboard", label: "Leaderboard", Icon: ChartIcon },
  { id: "how-to-play", label: "How to Play", Icon: BookIcon },
];

export default function NavBar({ active, onChange }) {
  return (
    <nav style={{ display: "flex", gap: "0.4rem", flexWrap: "wrap" }}>
      {TABS.map((t) => (
        <button
          key={t.id}
          className={active === t.id ? "btn-primary" : "btn-ghost"}
          onClick={() => onChange(t.id)}
          style={{ padding: "0.5rem 0.9rem", fontSize: "0.85rem", display: "inline-flex", alignItems: "center" }}
        >
          <t.Icon width={15} height={15} className="nav-icon" />
          {t.label}
        </button>
      ))}
    </nav>
  );
}
