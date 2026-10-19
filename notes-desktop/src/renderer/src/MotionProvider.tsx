import { MotionConfig, spring, type Transition } from "motion/react";
import { createContext, useContext, useLayoutEffect, useMemo, useSyncExternalStore, type ReactNode } from "react";
import { defaultIntensity, motionPresets, type MotionIntensity, type MotionPresets } from "./motion";

const reducedMotion = "(prefers-reduced-motion: reduce)";

/** The system's 减弱动态效果, followed while the app runs. */
function usePrefersReducedMotion(): boolean {
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
    const { pop, slide, expand, emerge } = motionPresets(intensity);
    const root = document.documentElement.style;
    for (const [name, preset] of Object.entries({ pop, slide, expand, emerge })) root.setProperty(`--spring-${name}`, cssSpring(preset));
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
