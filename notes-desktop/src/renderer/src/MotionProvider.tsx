import { MotionConfig, spring, type Transition } from "motion/react";
import { createContext, useContext, useLayoutEffect, useMemo, useSyncExternalStore, type ReactNode } from "react";
import { defaultIntensity, menuEnter, motionPresets, travel, type MotionIntensity, type MotionPresets } from "./motion";

const reducedMotion = "(prefers-reduced-motion: reduce)";

/** The system's 减弱动态效果, followed while the app runs. */
export function usePrefersReducedMotion(): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const query = matchMedia(reducedMotion);
      query.addEventListener("change", onChange);
      return () => query.removeEventListener("change", onChange);
    },
    () => matchMedia(reducedMotion).matches,
  );
}

const Presets = createContext<MotionPresets>(motionPresets());

/** The motion presets at the current intensity, already reduced when the system asks for less motion. */
export const useMotion = () => useContext(Presets);

const cssSpring = ({ visualDuration, bounce }: Transition) => spring(visualDuration, bounce).toString();

/**
 * CSS transitions (hover, press) use the same springs, as `--spring-<preset>: <duration> linear(…)`. Under
 * reduced motion tokens.css stops the movement itself, so these stay springs.
 */
function useCssSprings(intensity: MotionIntensity) {
  useLayoutEffect(() => {
    const { pop, slide, expand, emerge, focus, amplitude } = motionPresets(intensity);
    const root = document.documentElement.style;
    // 幅度 for CSS: distances and scale-ins at 标准 (shared/motion.ts), multiplied by it.
    root.setProperty("--motion-amplitude", String(amplitude));
    // Only the 标准 values: tokens.css multiplies them, so its 减弱动态效果 rules still win.
    root.setProperty("--menu-enter-shrink", String(menuEnter.scale));
    root.setProperty("--card-tool-travel", `${travel.cardToolRise}px`);
    root.setProperty("--notice-travel", `${travel.noticeRise}px`);
    for (const [name, preset] of Object.entries({ pop, slide, expand, emerge, focus })) {
      root.setProperty(`--spring-${name}`, cssSpring(preset));
      // What fades beside a spring (a menu, a card button) eases over its visual duration: opacity never bounces.
      root.setProperty(`--fade-${name}`, `${preset.visualDuration}s`);
    }
  }, [intensity]);
}

export function MotionProvider({ intensity = defaultIntensity, children }: { intensity?: MotionIntensity; children: ReactNode }) {
  const reduced = usePrefersReducedMotion();
  const presets = useMemo(() => motionPresets(intensity, { reduced }), [intensity, reduced]);
  useCssSprings(intensity);
  return (
    <MotionConfig transition={presets.slide} reducedMotion={reduced ? "always" : "never"}>
      <Presets.Provider value={presets}>{children}</Presets.Provider>
    </MotionConfig>
  );
}
