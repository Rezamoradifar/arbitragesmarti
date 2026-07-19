import { useEffect, useState } from "react";

export default function FullscreenToggle() {
  const [isFullscreen, setIsFullscreen] = useState(false);

  useEffect(() => {
    const onChange = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);

  async function toggle() {
    try {
      if (!document.fullscreenElement) {
        await document.documentElement.requestFullscreen();
      } else {
        await document.exitFullscreen();
      }
    } catch {
      // Fullscreen API can be denied (iOS Safari doesn't support it on
      // non-video elements) -- fail silently, the app still works fine
      // as a normal responsive page.
    }
  }

  return (
    <button
      className="btn-ghost"
      onClick={toggle}
      title={isFullscreen ? "Exit fullscreen" : "Fullscreen"}
      style={{ padding: "0.5rem 0.7rem" }}
    >
      {isFullscreen ? "⤢" : "⛶"}
    </button>
  );
}
