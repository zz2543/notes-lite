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
import foundation from "./spaceKit/foundation.css?raw";
import kit from "./spaceKit/style.css?raw";
import inter from "./spaceKit/fonts/Inter.woff2.b64?raw";
import jakarta from "./spaceKit/fonts/PlusJakartaSans.woff2.b64?raw";
import urbanist from "./spaceKit/fonts/Urbanist.woff2.b64?raw";

/** The id of the style element holding the page settings; the homepage's preload replaces its text. */
export const settingsStyleId = "space-settings";

/**
 * The fonts the 风格参考 use, at their own address: variable faces, Latin only (Chinese falls to the
 * system's). Kept in the repo as base64 text (spaceKit/fonts/*.woff2.b64) and decoded on request; a
 * page only fetches one when its CSS names the family.
 */
const fontFiles = { Inter: ["inter", inter], "Plus Jakarta Sans": ["jakarta", jakarta], Urbanist: ["urbanist", urbanist] } as const;
export const kitFonts: Record<string, () => Buffer> = Object.fromEntries(
  Object.values(fontFiles).map(([file, text]) => [`/kit/fonts/${file}.woff2`, () => Buffer.from(text, "base64")]),
);
const fontFaces = Object.entries(fontFiles)
  .map(([family, [file]]) => `@font-face { font-family: "${family}"; font-weight: 100 900; font-display: block; src: url(/kit/fonts/${file}.woff2) format("woff2"); }`)
  .join("\n");

export const kitStyle = `${tokens}\n${fontFaces}\n${kit}\n${foundation}`;

/** The libraries the app carries for homepages (space.load), served at their own address on demand. */
export const kitLibraries: Record<string, () => Promise<string>> = {
  "/kit/echarts.js": async () => (await import("echarts/dist/echarts.min.js?raw")).default,
  "/kit/react.js": async () => (await import("virtual:space-react")).default,
};
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
  variables["--space-motion-amplitude"] = `${presets.amplitude}`;
  return `:root {\n${Object.entries(variables)
    .map(([name, value]) => `  ${name}: ${value};`)
    .join("\n")}\n}`;
}
