export default function Spinner({ label }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", color: "var(--ivory-dim)" }}>
      <span className="bg-spinner" aria-hidden="true" />
      <span>{label}</span>
    </div>
  );
}
