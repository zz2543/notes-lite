// 排版设置: how a note's text is set — fonts, size, leading, paragraph gap, measure, heading ratio and
// 中英文自动间距. One set for the whole app, stored with the other preferences (never in a library).
// The page applies them as the CSS variables tokens.css declares (typographyVariables).

/** A font preset, or a font installed on this computer (`installed:<family>`). */
export type FontChoice = FontPreset | `installed:${string}`;
/** 系统无衬线, 思源宋体, Source Serif 4 + 思源宋体, 等宽 (the platform's monospace). */
export type FontPreset = "system" | "songti" | "serif" | "mono";

export interface Typography {
  bodyFont: FontChoice;
  headingFont: FontChoice;
  codeFont: FontChoice;
  /** 字号, px. */
  size: number;
  /** 行距, a multiple of the size. */
  leading: number;
  /** 段距, em. */
  paraGap: number;
  /** 版心宽度, px. */
  measure: number;
  /** 标题大小比例. */
  headingRatio: number;
  /** 中英文自动间距: display only, the file is never changed. */
  autospace: boolean;
}

export type NumericSetting = "size" | "leading" | "paraGap" | "measure" | "headingRatio";

/** The ranges of design-system.md 正文排版, and the step a slider moves in. */
export const ranges: { readonly [K in NumericSetting]: { min: number; max: number; step: number } } = {
  size: { min: 14, max: 22, step: 0.5 },
  leading: { min: 1.4, max: 2.2, step: 0.05 },
  paraGap: { min: 0, max: 1.6, step: 0.05 },
  measure: { min: 480, max: 900, step: 10 },
  headingRatio: { min: 1.2, max: 2, step: 0.05 },
};

export const fontPresets: readonly FontPreset[] = ["system", "songti", "serif", "mono"];
/** Code is set in a monospace: the platform's, or an installed one. */
export const codeFontPresets: readonly FontPreset[] = ["mono"];

export const defaultTypography: Typography = {
  bodyFont: "system",
  headingFont: "system",
  codeFont: "mono",
  size: 17,
  leading: 1.8,
  paraGap: 0.9,
  measure: 680,
  headingRatio: 1.6,
  autospace: true,
};

const installedPrefix = "installed:";

export const installedFont = (family: string): FontChoice => `${installedPrefix}${family}`;
export const installedFamily = (choice: FontChoice): string | undefined =>
  choice.startsWith(installedPrefix) ? choice.slice(installedPrefix.length) : undefined;

function readFont(value: unknown, presets: readonly FontPreset[], fallback: FontChoice): FontChoice {
  if (typeof value !== "string") return fallback;
  if ((presets as readonly string[]).includes(value)) return value as FontPreset;
  const family = installedFamily(value as FontChoice);
  return family && family.trim() && family.length <= 200 ? (value as FontChoice) : fallback;
}

function readNumber(value: unknown, key: NumericSetting, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  const { min, max, step } = ranges[key];
  const snapped = min + Math.round((Math.min(max, Math.max(min, value)) - min) / step) * step;
  // Round away float dust (1.4 + 8 × 0.05 = 1.8000000000000003).
  return Number(snapped.toFixed(4));
}

/** Whatever was stored (or sent), as typography: known fields with valid values, the rest from `base`. */
export function readTypography(stored: unknown, base: Typography = defaultTypography): Typography {
  const raw = (stored && typeof stored === "object" ? stored : {}) as Record<string, unknown>;
  return {
    bodyFont: readFont(raw.bodyFont, fontPresets, base.bodyFont),
    headingFont: readFont(raw.headingFont, fontPresets, base.headingFont),
    codeFont: readFont(raw.codeFont, codeFontPresets, base.codeFont),
    size: readNumber(raw.size, "size", base.size),
    leading: readNumber(raw.leading, "leading", base.leading),
    paraGap: readNumber(raw.paraGap, "paraGap", base.paraGap),
    measure: readNumber(raw.measure, "measure", base.measure),
    headingRatio: readNumber(raw.headingRatio, "headingRatio", base.headingRatio),
    autospace: typeof raw.autospace === "boolean" ? raw.autospace : base.autospace,
  };
}

/** The font stacks tokens.css declares for the presets. */
const presetStacks: { readonly [P in FontPreset]: string } = {
  system: "var(--font-ui)",
  songti: "var(--font-songti)",
  serif: "var(--font-serif)",
  mono: "var(--font-mono)",
};

/** A choice as a font-family value. An installed family falls back to the face its role uses by default. */
export function fontStack(choice: FontChoice, fallback: FontPreset): string {
  const family = installedFamily(choice);
  if (family === undefined) return presetStacks[choice as FontPreset];
  return `"${family.replace(/[\\"]/g, (c) => `\\${c}`)}", ${presetStacks[fallback]}`;
}

/** The CSS variables (tokens.css, markdown.css) that set notes in this typography. */
export function typographyVariables(t: Typography): Record<string, string> {
  return {
    "--body-font": fontStack(t.bodyFont, "system"),
    "--heading-font": fontStack(t.headingFont, "system"),
    "--code-font": fontStack(t.codeFont, "mono"),
    "--body-size": `${t.size}px`,
    "--body-leading": `${t.leading}`,
    "--para-gap": `${t.paraGap}em`,
    "--measure": `${t.measure}px`,
    "--heading-ratio": `${t.headingRatio}`,
    "--text-autospace": t.autospace ? "normal" : "no-autospace",
  };
}
