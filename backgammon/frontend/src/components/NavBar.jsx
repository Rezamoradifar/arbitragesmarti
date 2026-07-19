const TABS = [
  { id: "home", label: "Home" },
  { id: "play", label: "Play" },
  { id: "tournaments", label: "Tournaments" },
  { id: "leaderboard", label: "Leaderboard" },
  { id: "how-to-play", label: "How to Play" },
];

export default function NavBar({ active, onChange }) {
  return (
    <nav style={{ display: "flex", gap: "0.4rem", flexWrap: "wrap" }}>
      {TABS.map((t) => (
        <button
          key={t.id}
          className={active === t.id ? "btn-primary" : "btn-ghost"}
          onClick={() => onChange(t.id)}
          style={{ padding: "0.5rem 0.9rem", fontSize: "0.85rem" }}
        >
          {t.label}
        </button>
      ))}
    </nav>
  );
}
