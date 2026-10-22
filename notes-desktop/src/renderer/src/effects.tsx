import { BorderBeam, type BorderBeamSize } from "border-beam";
import { Liquid } from "liquid-gooey";
import { useLayoutEffect, useState, useSyncExternalStore, type ReactNode } from "react";
import { ThinkingOrb, type OrbState } from "thinking-orbs";
import "./effects.css";
import { usePrefersReducedMotion } from "./MotionProvider";
import { usePreferences } from "./preferences";
import type { AgentActivity } from "../../shared/conversation";
import type { Preferences } from "../../shared/preferences";

// 界面特效 (设置 › 动画): the effects from the design libraries, each behind its own switch and all of
// them behind 界面特效. With an effect off its place renders exactly what it did before it; this file is
// the only one importing the libraries, so taking an effect out is deleting its wrapper here and its use.

type EffectKey = "effectBeam" | "effectOrbs" | "effectGooey";

/** Whether one effect shows: its own switch and 界面特效 both on. */
export function useVisualEffect(key: EffectKey): boolean {
  const { preferences } = usePreferences();
  return effectOn(preferences, key);
}

export const effectOn = (preferences: Preferences, key: EffectKey) => preferences.effects === "on" && preferences[key] === "on";

const darkQuery = "(prefers-color-scheme: dark)";

/** The app's own light or dark (main sets the system theme to the 外观 chosen, so this follows it). */
export function usePrefersDark(): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const query = matchMedia(darkQuery);
      query.addEventListener("change", onChange);
      return () => query.removeEventListener("change", onChange);
    },
    () => matchMedia(darkQuery).matches,
  );
}

/**
 * 流光边框: a beam running around `children` while `active` (or, for the pulse sizes, a glow breathing
 * in it). Off, or under 减弱动态效果, the children render as they are, unwrapped.
 */
export function Beam({ active, size, className, children }: { active: boolean; size: BorderBeamSize; className?: string; children: ReactNode }) {
  const on = useVisualEffect("effectBeam");
  const reduced = usePrefersReducedMotion();
  const dark = usePrefersDark();
  if (!on) return <>{children}</>;
  return (
    <BorderBeam size={size} theme={dark ? "dark" : "light"} active={active && !reduced} className={className}>
      {children}
    </BorderBeam>
  );
}

/** 思考光球: a small orb in a state of thinking. Decorative: the text beside it says the same. */
export function Orb({ state, className }: { state: OrbState; className?: string }) {
  const on = useVisualEffect("effectOrbs");
  const reduced = usePrefersReducedMotion();
  const dark = usePrefersDark();
  if (!on) return null;
  return <ThinkingOrb state={state} size={20} theme={dark ? "dark" : "light"} paused={reduced} className={className} aria-hidden />;
}

/** The orb for what the assistant is doing in one step of its timeline. */
const stepOrbs: Record<AgentActivity, OrbState> = { searching: "searching", writing: "composing", reading: "working", running: "working", thinking: "breathing" };
export const orbFor = (activity: AgentActivity): OrbState => stepOrbs[activity];

/** A design-system variable as its value now, for libraries that draw it themselves. */
function useCssVariable(name: string, element: HTMLElement | null = null): string {
  const dark = usePrefersDark();
  const [value, setValue] = useState("");
  useLayoutEffect(() => {
    setValue(getComputedStyle(element ?? document.documentElement).getPropertyValue(name).trim());
  }, [name, element, dark]);
  return value;
}

/**
 * 液态滑块: the chosen segment's pill as a drop of liquid that stretches and trails as it slides to
 * the next one. `target` is the element the pill sits under; the pill follows it with `transition`.
 */
export function LiquidPill({ container, target, fill, shadow, className }: { container: HTMLElement | null; target: HTMLElement | null; fill: string; shadow: string; className: string }) {
  const reduced = usePrefersReducedMotion();
  const shadowValue = useCssVariable(shadow, container);
  const [box, setBox] = useState<{ x: number; y: number; width: number; height: number; radius: number }>();
  useLayoutEffect(() => {
    if (!container || !target) return;
    const measure = () => {
      const outer = container.getBoundingClientRect();
      const inner = target.getBoundingClientRect();
      setBox({
        x: inner.left - outer.left,
        y: inner.top - outer.top,
        width: inner.width,
        height: inner.height,
        radius: parseFloat(getComputedStyle(target).borderTopLeftRadius) || 0,
      });
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(container);
    observer.observe(target);
    return () => observer.disconnect();
  }, [container, target]);
  if (!box) return null;
  return (
    <Liquid className={`liquid-pill ${className}`} fill={`var(${fill})`} shadow={shadowValue || undefined} aria-hidden>
      <Liquid.Item effect="move" move={{ stretch: 0.6, trail: 0.35 }} radius={box.radius}>
        <div
          className="liquid-pill-drop"
          style={{
            width: box.width,
            height: box.height,
            borderRadius: box.radius,
            transform: `translate(${box.x}px, ${box.y}px)`,
            transition: reduced ? "none" : "transform var(--spring-slide), width var(--spring-slide)",
          }}
        />
      </Liquid.Item>
    </Liquid>
  );
}

/**
 * 液态滑块 for a control whose own part moves (the side switch's knob): `children` laid out as before,
 * `moving` (one element) drawn as liquid that stretches and trails behind where it goes.
 */
export function LiquidGroup({ fill, shadow, className, children, moving }: { fill: string; shadow?: string; className: string; children: ReactNode; moving: ReactNode }) {
  const shadowValue = useCssVariable(shadow ?? "--liquid-none");
  return (
    <Liquid className={className} fill={`var(${fill})`} shadow={shadowValue || undefined}>
      {children}
      <Liquid.Item effect="move" move={{ stretch: 0.6, trail: 0.35 }}>
        {moving}
      </Liquid.Item>
    </Liquid>
  );
}
