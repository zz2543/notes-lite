import { MotionConfig } from "motion/react";
import { createContext, useContext, useMemo, useSyncExternalStore, type ReactNode } from "react";
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

export function MotionProvider({ intensity = defaultIntensity, children }: { intensity?: MotionIntensity; children: ReactNode }) {
  const reduced = usePrefersReducedMotion();
  const presets = useMemo(() => motionPresets(intensity, { reduced }), [intensity, reduced]);
  return (
    <MotionConfig transition={presets.slide} reducedMotion={reduced ? "always" : "never"}>
      <Presets.Provider value={presets}>{children}</Presets.Provider>
    </MotionConfig>
  );
}
