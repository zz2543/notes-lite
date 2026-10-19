// PROTOTYPE motion presets. The four named springs are the whole motion vocabulary;
// intensity scales bounce and duration so the user can calibrate by feel.
import { createContext, useContext } from "react";

// 轻弹 and 滑移 drive high-frequency things (selection, hover); intensity barely raises their bounce.
const base = {
  轻弹: { visualDuration: 0.18, bounce: 0.28, frequent: true },
  滑移: { visualDuration: 0.3, bounce: 0.16, frequent: true },
  展开: { visualDuration: 0.32, bounce: 0.22 },
  浮现: { visualDuration: 0.42, bounce: 0.26 },
};

// amp scales travel distances (slide offsets, scale-in) so 强 also moves further, not only bouncier.
const scale = {
  轻: { bounce: 0.35, duration: 0.85, amp: 0.6 },
  标准: { bounce: 1, duration: 1, amp: 1 },
  强: { bounce: 2.6, duration: 1.3, amp: 2 },
};

export function presets(intensity) {
  const s = scale[intensity];
  const out = {};
  for (const [name, p] of Object.entries(base)) {
    const k = p.frequent ? Math.min(s.bounce, 1.15) : s.bounce;
    const d = p.frequent ? Math.min(s.duration, 1.05) : s.duration;
    out[name] = { type: "spring", visualDuration: p.visualDuration * d, bounce: Math.min(0.72, p.bounce * k) };
  }
  out.amp = s.amp;
  out.blur = { duration: 0.28 * s.duration, ease: [0.2, 0.8, 0.2, 1] };
  return out;
}

export const MotionPresets = createContext(presets("标准"));
export const useSpring = () => useContext(MotionPresets);
