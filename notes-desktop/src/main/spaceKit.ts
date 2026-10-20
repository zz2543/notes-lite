// What every space homepage gets before its own content: the style kit on the app's design tokens, the
// page settings (排版, 强调色, motion presets) and the scripts (the `space` interface, then the
// components). Nothing here reaches the notes; that is the interface's bridge.
import { spring } from "motion";
import tokens from "../renderer/src/tokens.css?raw";
import { motionPresets, spaceCardEnter } from "../shared/motion";
import type { Preferences } from "../shared/preferences";
import { typographyVariables } from "../shared/typography";
import { spaceShim } from "./spaceShim";
import components from "./spaceKit/components.js?raw";
import kit from "./spaceKit/style.css?raw";

/** The id of the style element holding the page settings; the homepage's preload replaces its text. */
export const settingsStyleId = "space-settings";

export const kitStyle = `${tokens}\n${kit}`;
export const kitScripts = [spaceShim, components];

/** The design system's blur ease (动效 · 模糊), which no spring carries. */
const ease = "cubic-bezier(0.2, 0.8, 0.2, 1)";

/**
 * The settings as CSS variables on the page's root: the typography of the notes, the accent (the chosen
 * preset, or the system's colour), and the motion presets at the chosen intensity as CSS springs.
 */
export function spacePageSettings(preferences: Preferences, systemAccent: string | null): string {
  const presets = motionPresets(preferences.motion);
  const variables: Record<string, string> = { ...typographyVariables(preferences.typography) };
  const accent = preferences.accent === "system" ? systemAccent : `var(--accent-${preferences.accent})`;
  if (accent) variables["--accent"] = accent;
  for (const name of ["pop", "slide", "expand", "emerge"] as const) {
    const { visualDuration = 0, bounce = 0 } = presets[name] as { visualDuration?: number; bounce?: number };
    // `spring()` reads as "<duration>ms linear(…)": the time the curve takes to settle, then the curve.
    const [duration, ...curve] = spring(visualDuration, bounce).toString().split(" ");
    variables[`--space-${name}-duration`] = duration!;
    variables[`--space-${name}-easing`] = curve.join(" ");
    variables[`--space-${name}-visual`] = `${visualDuration}s`;
  }
  const blur = (presets.emerge as { filter?: { duration: number } }).filter;
  variables["--space-blur-duration"] = `${blur?.duration ?? 0.28}s`;
  variables["--space-ease"] = ease;
  const round = (n: number) => Math.round(n * 1000) / 1000;
  variables["--space-enter-rise"] = `${round(spaceCardEnter.rise * presets.amplitude)}px`;
  variables["--space-enter-scale"] = `${round(1 - spaceCardEnter.scale * presets.amplitude)}`;
  variables["--space-enter-blur"] = `${round(spaceCardEnter.blur * presets.amplitude)}px`;
  variables["--space-stagger"] = `${spaceCardEnter.stagger}s`;
  return `:root {\n${Object.entries(variables)
    .map(([name, value]) => `  ${name}: ${value};`)
    .join("\n")}\n}`;
}
