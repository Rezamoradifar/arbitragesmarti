import { useFeedbackContext } from "../context/FeedbackContext";

export default function SettingsToggle() {
  const { settings, toggleSound, toggleVibration } = useFeedbackContext();

  return (
    <div style={{ display: "flex", gap: "0.4rem" }}>
      <button
        className="btn-ghost"
        onClick={toggleSound}
        aria-pressed={settings.sound}
        title={settings.sound ? "Sound on" : "Sound off"}
        style={{ padding: "0.5rem 0.7rem", opacity: settings.sound ? 1 : 0.5 }}
      >
        {settings.sound ? "🔊" : "🔇"}
      </button>
      <button
        className="btn-ghost"
        onClick={toggleVibration}
        aria-pressed={settings.vibration}
        title={settings.vibration ? "Vibration on" : "Vibration off"}
        style={{ padding: "0.5rem 0.7rem", opacity: settings.vibration ? 1 : 0.5 }}
      >
        {settings.vibration ? "📳" : "📴"}
      </button>
    </div>
  );
}
