import { useCallback, useEffect, useState } from "react";

const STORAGE_KEY = "bg-feedback-settings";

function loadSettings() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {
    /* ignore */
  }
  return { sound: true, vibration: true };
}

let audioCtx = null;
function getAudioCtx() {
  if (!audioCtx) {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (Ctx) audioCtx = new Ctx();
  }
  return audioCtx;
}

// Simple synthesized cues -- no external audio files, so nothing to license
// or fail to load. Each event gets a short, distinct tone shape.
const TONES = {
  turnStart: [{ freq: 440, dur: 0.12 }, { freq: 660, dur: 0.12 }],
  diceReveal: [{ freq: 300, dur: 0.06 }, { freq: 500, dur: 0.06 }, { freq: 700, dur: 0.1 }],
  moveSubmitted: [{ freq: 520, dur: 0.09 }],
  timerLow: [{ freq: 880, dur: 0.08 }],
  timeout: [{ freq: 220, dur: 0.3 }],
  gameWon: [{ freq: 523, dur: 0.1 }, { freq: 659, dur: 0.1 }, { freq: 784, dur: 0.2 }],
};

function playTone(sequence) {
  const ctx = getAudioCtx();
  if (!ctx) return;
  let t = ctx.currentTime;
  sequence.forEach(({ freq, dur }) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = "sine";
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(0.2, t + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    osc.connect(gain).connect(ctx.destination);
    osc.start(t);
    osc.stop(t + dur + 0.02);
    t += dur;
  });
}

const VIBRATION_PATTERNS = {
  turnStart: [40],
  diceReveal: [30, 30, 30],
  moveSubmitted: [20],
  timerLow: [15, 60, 15],
  timeout: [200],
  gameWon: [30, 40, 30, 40, 80],
};

export function useFeedback() {
  const [settings, setSettings] = useState(loadSettings);

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  }, [settings]);

  const trigger = useCallback(
    (eventName) => {
      if (settings.sound && TONES[eventName]) {
        try {
          playTone(TONES[eventName]);
        } catch {
          /* audio can fail silently (autoplay policy) -- non-critical */
        }
      }
      if (settings.vibration && VIBRATION_PATTERNS[eventName] && navigator.vibrate) {
        navigator.vibrate(VIBRATION_PATTERNS[eventName]);
      }
    },
    [settings]
  );

  const toggleSound = useCallback(() => setSettings((s) => ({ ...s, sound: !s.sound })), []);
  const toggleVibration = useCallback(() => setSettings((s) => ({ ...s, vibration: !s.vibration })), []);

  return { settings, trigger, toggleSound, toggleVibration };
}
