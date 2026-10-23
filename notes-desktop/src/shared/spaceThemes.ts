// 空间风格: how every space homepage looks — its colours, type, radii, shadows and the detail of its
// charts and progress (细节). One choice for the whole app, kept with the other preferences: 默认 (the
// app's own design system), one of six examples taken from finished dashboards, or 自定义 (the user's
// own colours and details, started from any of them). The page reads it as the --space-* variables
// (spaceThemeCss), so the components and the pages the assistant writes follow without knowing it.

/** The examples. 默认 follows the app (外观, 强调色); each other one is a look of its own. */
export type SpaceThemePreset = "app" | "sky" | "night" | "glass" | "bento" | "earth" | "vivid";
export type SpaceThemeChoice = SpaceThemePreset | "custom";
/** 字体: 跟随排版 (the note's body font), 系统 (the interface font), or one the app carries. */
export type SpaceFont = "note" | "ui" | "inter" | "jakarta" | "urbanist";
/** 细节: how progress, rings, bars and calendar cells are drawn. */
export type SpaceDecor = "plain" | "capsule" | "led" | "glow" | "bento" | "pebble" | "dots";
/** 卡片: no shadow, a soft one, lifted, or a fine edge (for dark pages). */
export type SpaceShadow = "none" | "soft" | "float" | "edge";

export interface SpacePalette {
  /** The page behind the cards, solid; `pageImage` may paint a gradient over it. */
  page: string;
  pageImage?: string;
  card: string;
  text: string;
  muted: string;
  line: string;
  accent: string;
  onAccent: string;
  /** 强调卡片 (.space-glow): its base and its text. */
  feature: string;
  featureText: string;
  /** 图表系列色, six. */
  series: readonly string[];
  good: string;
  warn: string;
  bad: string;
}

/** The hues a page picks with data-hue (foundation.css). */
export type SpaceHue = "red" | "orange" | "yellow" | "green" | "teal" | "blue" | "indigo" | "purple" | "pink" | "graphite";

export interface SpaceTheme {
  id: SpaceThemePreset;
  name: string;
  description: string;
  /** The finished design it was taken from. */
  source?: { title: string; url: string };
  /** Dark whatever the app's 外观 (its light palette is its dark one). */
  darkOnly?: boolean;
  /** null for 默认: the app's own tokens, nothing overridden. */
  light: SpacePalette | null;
  dark: SpacePalette | null;
  font: SpaceFont;
  radius: number;
  shadow: SpaceShadow;
  decor: SpaceDecor;
  /** data-hue in the look's own colours: each the colour of a flat tile (white text on it). */
  hues?: Partial<Record<SpaceHue, string>>;
}

const hex = /^#[0-9a-f]{6}$/i;
const isHex = (v: unknown): v is string => typeof v === "string" && hex.test(v);

const status = { good: "#2fb67c", warn: "#f4a019", bad: "#ef4b3f" };

const sky: SpaceTheme = {
  id: "sky",
  name: "晴空",
  description: "天空底色上的白卡片，橙色胶囊进度和刻度表盘，进度条带一点光泽。",
  source: { title: "Fitness Dashboard UI Components", url: "https://dribbble.com/shots/27705472-Fitness-Dashboard-UI-Components" },
  light: {
    page: "#cfe2f2",
    pageImage: "linear-gradient(180deg, #a9cdee 0%, #d3e5f4 48%, #e9f0ea 100%)",
    card: "#ffffff",
    text: "#1d1f24",
    muted: "#7d8591",
    line: "#eceff3",
    accent: "#ff7a1a",
    onAccent: "#ffffff",
    feature: "#ffffff",
    featureText: "#1d1f24",
    series: ["#ff7a1a", "#3a8dde", "#2fb67c", "#f4b740", "#a77bf3", "#ff5c8a"],
    ...status,
  },
  dark: {
    page: "#122033",
    pageImage: "linear-gradient(180deg, #0f2440 0%, #13233a 55%, #172a2a 100%)",
    card: "#1b2636",
    text: "#eef2f7",
    muted: "#93a0b2",
    line: "rgba(255, 255, 255, 0.08)",
    accent: "#ff8a33",
    onAccent: "#ffffff",
    feature: "#1b2636",
    featureText: "#eef2f7",
    series: ["#ff8a33", "#5aa6f0", "#3fcf8e", "#f6c45a", "#b38ef7", "#ff7aa0"],
    ...status,
  },
  font: "inter",
  radius: 22,
  shadow: "soft",
  decor: "capsule",
  hues: { red: "#f0612e", orange: "#ff7a1a", yellow: "#e8a317", green: "#25a06c", teal: "#1e9fb0", blue: "#3a8dde", indigo: "#4f6fe0", purple: "#8c6cf0", pink: "#ec5a8c", graphite: "#3b4452" },
};

const nightPalette: SpacePalette = {
  page: "#0f0f11",
  card: "#1d1d20",
  text: "#f3f3f5",
  muted: "#9b9ba4",
  line: "rgba(255, 255, 255, 0.08)",
  accent: "#7c6cff",
  onAccent: "#ffffff",
  feature: "#26262a",
  featureText: "#ffffff",
  series: ["#7c6cff", "#4fd1ff", "#ff6b81", "#ff9f43", "#3ddc97", "#c77dff"],
  good: "#3ddc97",
  warn: "#ff9f43",
  bad: "#ff6b81",
};

const night: SpaceTheme = {
  id: "night",
  name: "暗夜",
  description: "深色卡片上的渐变柱、LED 分段条和白色圆形按钮，像运动手环的数据页。",
  source: { title: "Fitness App Health Metrics Dashboard", url: "https://dribbble.com/shots/27473506-Fitness-App-Health-Metrics-Dashboard" },
  darkOnly: true,
  light: nightPalette,
  dark: nightPalette,
  font: "inter",
  radius: 20,
  shadow: "edge",
  decor: "led",
};

const glassPalette: SpacePalette = {
  page: "#0b0d0c",
  pageImage: "radial-gradient(90% 70% at 50% 40%, #1c201e 0%, #0b0d0c 70%)",
  card: "rgba(255, 255, 255, 0.055)",
  text: "#f4f6f5",
  muted: "#98a19c",
  line: "rgba(255, 255, 255, 0.09)",
  accent: "#3ddc5a",
  onAccent: "#06200c",
  feature: "#123d1c",
  featureText: "#ffffff",
  series: ["#3ddc5a", "#ff7aa8", "#5aa7ff", "#ffc94a", "#b18cff", "#46e0d0"],
  good: "#3ddc5a",
  warn: "#ffc94a",
  bad: "#ff6b6b",
};

const glass: SpaceTheme = {
  id: "glass",
  name: "玻璃",
  description: "深色毛玻璃小组件，发光的绿色弧线、打卡圆点和涨跌小标签。",
  source: { title: "App Widget UI", url: "https://dribbble.com/shots/27244970-App-Widget-UI" },
  darkOnly: true,
  light: glassPalette,
  dark: glassPalette,
  font: "inter",
  radius: 26,
  shadow: "edge",
  decor: "glow",
};

const bento: SpaceTheme = {
  id: "bento",
  name: "便当",
  description: "浅灰底上大小不一的卡片，黑色强调卡、密集细柱、圆形日历格和三色进度。",
  source: { title: "BoozUI – Health & Fitness Dashboard UI", url: "https://dribbble.com/shots/24747077-BoozUI-Health-Fitness-Dashboard-UI" },
  light: {
    page: "#e9e9ea",
    card: "#ffffff",
    text: "#111112",
    muted: "#85858b",
    line: "#ececee",
    accent: "#ff5a0a",
    onAccent: "#ffffff",
    feature: "#141414",
    featureText: "#ffffff",
    series: ["#ff5a0a", "#3ad12b", "#ffc800", "#6c63ff", "#3ec5e6", "#ff6fb5"],
    good: "#3ad12b",
    warn: "#ffc800",
    bad: "#ff4d2e",
  },
  dark: {
    page: "#0e0e0f",
    card: "#1c1c1e",
    text: "#f2f2f3",
    muted: "#94949a",
    line: "rgba(255, 255, 255, 0.08)",
    accent: "#ff6a1f",
    onAccent: "#ffffff",
    feature: "#000000",
    featureText: "#ffffff",
    series: ["#ff6a1f", "#4ade3a", "#ffd21f", "#857dff", "#4fd0ee", "#ff7fc0"],
    good: "#4ade3a",
    warn: "#ffd21f",
    bad: "#ff5a3c",
  },
  font: "inter",
  radius: 28,
  shadow: "none",
  decor: "bento",
  hues: { red: "#ff5a0a", orange: "#ff7a2f", yellow: "#eaa800", green: "#1f8f4e", teal: "#14857a", blue: "#141414", indigo: "#141414", purple: "#5b3df5", pink: "#ff3d7f", graphite: "#141414" },
};

const earth: SpaceTheme = {
  id: "earth",
  name: "大地",
  description: "棕、橄榄绿、橙和薰衣草紫，圆润的色块卡片配圆形箭头按钮，同心圆弧和圆点格。",
  source: { title: "Freud UI Kit", url: "https://dribbble.com/shots/23689369-Freud-UI-Kit-AI-Mental-Health-App-Smart-Dashboard-UIUX" },
  light: {
    page: "#ffffff",
    card: "#f5f3f1",
    text: "#4b2e1e",
    muted: "#8f7a6c",
    line: "#e6e1dc",
    accent: "#4f3422",
    onAccent: "#ffffff",
    feature: "#4f3422",
    featureText: "#ffffff",
    series: ["#9db068", "#f0861f", "#a18be6", "#736b65", "#c79a7c", "#e5b94e"],
    good: "#7f9a45",
    warn: "#f0861f",
    bad: "#d4593a",
  },
  dark: {
    page: "#1d1611",
    card: "#2a211a",
    text: "#f3e9df",
    muted: "#b5a08f",
    line: "rgba(255, 240, 225, 0.09)",
    accent: "#d9a67c",
    onAccent: "#2a1a10",
    feature: "#5a3c28",
    featureText: "#ffffff",
    series: ["#a9bd72", "#f39a3c", "#ad9bf0", "#a49a92", "#d4a888", "#ecc565"],
    good: "#a9bd72",
    warn: "#f39a3c",
    bad: "#e06a4a",
  },
  font: "urbanist",
  radius: 30,
  shadow: "none",
  decor: "pebble",
  hues: { red: "#e0711b", orange: "#ed7e1c", yellow: "#d6a21e", green: "#7d9447", teal: "#5f9e8f", blue: "#6c8fd9", indigo: "#8f7ae6", purple: "#a585e8", pink: "#d9718f", graphite: "#4f3422" },
};

const vivid: SpaceTheme = {
  id: "vivid",
  name: "活力",
  description: "米白底，黄、珊瑚红和黑：一周打卡圆圈、黑卡上的圆点进度、带百分比的环形图和渐变步数条。",
  source: { title: "Fitness Dashboard UI – Smart Activity Tracking", url: "https://dribbble.com/shots/26813558-Fitness-Dashboard-UI-Smart-Activity-Tracking" },
  light: {
    page: "#f1efea",
    card: "#ffffff",
    text: "#1b1b1b",
    muted: "#878279",
    line: "#ece9e3",
    accent: "#f5584a",
    onAccent: "#ffffff",
    feature: "#1f1f1f",
    featureText: "#ffffff",
    series: ["#ffc93d", "#f5584a", "#222222", "#f9893f", "#7fb3a6", "#9f8cf0"],
    good: "#3fae6a",
    warn: "#f9893f",
    bad: "#f5584a",
  },
  dark: {
    page: "#151412",
    card: "#22201d",
    text: "#f4f1eb",
    muted: "#a39e94",
    line: "rgba(255, 250, 240, 0.08)",
    accent: "#ff6a5c",
    onAccent: "#ffffff",
    feature: "#000000",
    featureText: "#ffffff",
    series: ["#ffd04f", "#ff6a5c", "#e8e4dc", "#ff9a52", "#8cc4b6", "#ad9cf5"],
    good: "#4cc17a",
    warn: "#ff9a52",
    bad: "#ff6a5c",
  },
  font: "jakarta",
  radius: 26,
  shadow: "none",
  decor: "dots",
  hues: { red: "#f0544a", orange: "#f37a3a", yellow: "#e9b520", green: "#2f8f63", teal: "#2a9d8f", blue: "#1f1f1f", indigo: "#1f1f1f", purple: "#6b4de6", pink: "#ef5d8c", graphite: "#1f1f1f" },
};

const app: SpaceTheme = {
  id: "app",
  name: "默认",
  description: "跟随笔记应用自己的外观和强调色，页面和应用原生界面一致。",
  light: null,
  dark: null,
  font: "note",
  radius: 18,
  shadow: "soft",
  decor: "plain",
};

export const spaceThemes: readonly SpaceTheme[] = [app, sky, night, glass, bento, earth, vivid];
export const spaceThemePresets: readonly SpaceThemePreset[] = spaceThemes.map((t) => t.id);
export const spaceThemeChoices: readonly SpaceThemeChoice[] = [...spaceThemePresets, "custom"];
export const spaceTheme = (id: SpaceThemePreset): SpaceTheme => spaceThemes.find((t) => t.id === id) ?? app;

export const spaceFonts: readonly { value: SpaceFont; label: string }[] = [
  { value: "note", label: "跟随排版" },
  { value: "ui", label: "系统" },
  { value: "inter", label: "Inter" },
  { value: "jakarta", label: "Jakarta" },
  { value: "urbanist", label: "Urbanist" },
];
export const spaceDecors: readonly { value: SpaceDecor; label: string }[] = [
  { value: "plain", label: "简洁" },
  { value: "capsule", label: "胶囊" },
  { value: "led", label: "分段" },
  { value: "glow", label: "光晕" },
  { value: "bento", label: "细柱" },
  { value: "pebble", label: "圆润" },
  { value: "dots", label: "圆点" },
];
export const spaceShadows: readonly { value: SpaceShadow; label: string }[] = [
  { value: "none", label: "无" },
  { value: "soft", label: "轻" },
  { value: "float", label: "浮起" },
  { value: "edge", label: "描边" },
];
export const spaceRadiusRange = { min: 0, max: 36, step: 1 } as const;

/**
 * 自定义: the user's own look. The colours are fixed (the same in light and dark: the user chose
 * them); what follows from them (secondary text, lines, the 强调卡片) is worked out (customPalette).
 */
export interface CustomSpaceTheme {
  /** The example it started from. */
  base: SpaceThemePreset;
  page: string;
  card: string;
  text: string;
  /** A colour, or "app": the app's 强调色. */
  accent: string;
  /** 图表配色: three; the other three series mix from them. */
  series: readonly [string, string, string];
  font: SpaceFont;
  radius: number;
  shadow: SpaceShadow;
  decor: SpaceDecor;
}

/** The app's own light look, as colours, for a custom look started from 默认. */
const appLight = { page: "#f5f5f6", card: "#ffffff", text: "#1d1d1f", accent: "app", series: ["#0a84ff", "#30d158", "#ff9f0a"] as const };
const appDark = { page: "#1e1e20", card: "#2a2a2d", text: "#ececef", accent: "app", series: ["#0a84ff", "#30d158", "#ff9f0a"] as const };

/** A custom look that starts from `base` as it looks now (`dark`: the app is dark). */
export function customFrom(base: SpaceThemePreset, dark = false): CustomSpaceTheme {
  const theme = spaceTheme(base);
  const palette = dark ? theme.dark : theme.light;
  const colors = palette
    ? { page: palette.page, card: solid(palette.card, palette.page), text: palette.text, accent: palette.accent, series: [palette.series[0]!, palette.series[1]!, palette.series[2]!] as const }
    : dark ? appDark : appLight;
  return { base, ...colors, series: [...colors.series] as unknown as readonly [string, string, string], font: theme.font, radius: theme.radius, shadow: theme.shadow, decor: theme.decor };
}

export const defaultCustomSpaceTheme: CustomSpaceTheme = customFrom("sky");


/** Whatever was stored (or sent), as a custom look: known fields with valid values, the rest from `base`. */
export function readCustomSpaceTheme(stored: unknown, base: CustomSpaceTheme = defaultCustomSpaceTheme): CustomSpaceTheme {
  const raw = (stored && typeof stored === "object" ? stored : {}) as Record<string, unknown>;
  const one = <T extends string>(value: unknown, options: readonly { value: T }[], fallback: T): T =>
    options.some((o) => o.value === value) ? (value as T) : fallback;
  const series = Array.isArray(raw.series) ? raw.series : [];
  const radius = typeof raw.radius === "number" && Number.isFinite(raw.radius) ? Math.round(Math.min(spaceRadiusRange.max, Math.max(spaceRadiusRange.min, raw.radius))) : base.radius;
  return {
    base: (spaceThemePresets as readonly unknown[]).includes(raw.base) ? (raw.base as SpaceThemePreset) : base.base,
    page: isHex(raw.page) ? raw.page.toLowerCase() : base.page,
    card: isHex(raw.card) ? raw.card.toLowerCase() : base.card,
    text: isHex(raw.text) ? raw.text.toLowerCase() : base.text,
    accent: raw.accent === "app" ? "app" : isHex(raw.accent) ? raw.accent.toLowerCase() : base.accent,
    series: [0, 1, 2].map((i) => (isHex(series[i]) ? (series[i] as string).toLowerCase() : base.series[i]!)) as unknown as readonly [string, string, string],
    font: one(raw.font, spaceFonts, base.font),
    radius,
    shadow: one(raw.shadow, spaceShadows, base.shadow),
    decor: one(raw.decor, spaceDecors, base.decor),
  };
}

// MARK: colour

function rgb(color: string): [number, number, number] | null {
  const m = hex.exec(color) ? color.slice(1) : null;
  if (!m) return null;
  return [0, 2, 4].map((i) => parseInt(m.slice(i, i + 2), 16)) as [number, number, number];
}
/** Relative luminance (WCAG), 0 (black) to 1 (white); 0.5 for what is not a #rrggbb colour. */
export function luminance(color: string): number {
  const c = rgb(color);
  if (!c) return 0.5;
  const [r, g, b] = c.map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  }) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
/** A translucent colour as the solid one it shows over `under`. */
function solid(color: string, under: string): string {
  const m = /^rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)$/.exec(color);
  const u = rgb(under);
  if (!m || !u) return isHex(color) ? color : under;
  const a = +m[4]!;
  return `#${[1, 2, 3].map((i, k) => Math.round(+m[i]! * a + u[k]! * (1 - a)).toString(16).padStart(2, "0")).join("")}`;
}
const mix = (a: string, b: string, amount: number) => `color-mix(in srgb, ${a} ${Math.round(amount * 100)}%, ${b})`;

/** A custom look as a palette: secondary text, lines and the 强调卡片 follow from its four colours. */
export function customPalette(custom: CustomSpaceTheme, appAccent = "var(--accent)"): SpacePalette {
  const dark = luminance(custom.page) < 0.25;
  const accent = custom.accent === "app" ? appAccent : custom.accent;
  const onAccent = custom.accent === "app" ? "var(--on-accent)" : luminance(custom.accent) > 0.55 ? "#111111" : "#ffffff";
  const [a, b, c] = custom.series;
  return {
    page: custom.page,
    card: custom.card,
    text: custom.text,
    muted: mix(custom.text, custom.card, 0.58),
    line: mix(custom.text, custom.card, 0.1),
    accent,
    onAccent,
    feature: dark ? mix(custom.text, custom.card, 0.12) : custom.text,
    featureText: dark ? custom.text : custom.card,
    series: [a, b, c, mix(a, b, 0.5), mix(b, c, 0.5), mix(c, a, 0.5)],
    good: status.good,
    warn: status.warn,
    bad: status.bad,
  };
}

// MARK: CSS

/** A font as a font-family value; the app's own faces stay behind it for Chinese. */
export function spaceFontStack(font: SpaceFont): string | null {
  const ui = `var(--font-ui, system-ui, -apple-system, "PingFang SC", "Microsoft YaHei UI", sans-serif)`;
  switch (font) {
    case "note": return null;
    case "ui": return ui;
    case "inter": return `"Inter", ${ui}`;
    case "jakarta": return `"Plus Jakarta Sans", ${ui}`;
    case "urbanist": return `"Urbanist", ${ui}`;
  }
}
/** The family a font file carries, for its @font-face. */
export const spaceFontFamily: Partial<Record<SpaceFont, string>> = { inter: "Inter", jakarta: "Plus Jakarta Sans", urbanist: "Urbanist" };

function shadowOf(shadow: SpaceShadow, dark: boolean): string {
  switch (shadow) {
    case "none": return "none";
    case "soft": return dark ? "inset 0 0 0 1px rgba(255, 255, 255, 0.06), 0 2px 10px rgba(0, 0, 0, 0.3)" : "0 1px 2px rgba(20, 30, 50, 0.04), 0 4px 18px rgba(20, 30, 50, 0.06)";
    case "float": return dark ? "inset 0 0 0 1px rgba(255, 255, 255, 0.07), 0 18px 40px -12px rgba(0, 0, 0, 0.7)" : "0 18px 40px -16px rgba(30, 30, 50, 0.28), 0 2px 6px rgba(30, 30, 50, 0.05)";
    case "edge": return dark ? "inset 0 0 0 1px rgba(255, 255, 255, 0.08)" : "inset 0 0 0 1px rgba(0, 0, 0, 0.08)";
  }
}

/** What a look needs to be drawn: its palettes (light, dark) and details. null for 默认. */
export interface ResolvedSpaceTheme {
  id: SpaceThemeChoice;
  light: SpacePalette;
  dark: SpacePalette;
  font: SpaceFont;
  radius: number;
  shadow: SpaceShadow;
  decor: SpaceDecor;
  hues?: Partial<Record<SpaceHue, string>>;
}

export function resolveSpaceTheme(choice: SpaceThemeChoice, custom: CustomSpaceTheme): ResolvedSpaceTheme | null {
  if (choice === "custom") {
    const palette = customPalette(custom);
    return { id: "custom", light: palette, dark: palette, font: custom.font, radius: custom.radius, shadow: custom.shadow, decor: custom.decor, hues: spaceTheme(custom.base).hues };
  }
  const theme = spaceTheme(choice);
  if (!theme.light || !theme.dark) return null;
  return { id: theme.id, light: theme.light, dark: theme.dark, font: theme.font, radius: theme.radius, shadow: theme.shadow, decor: theme.decor, hues: theme.hues };
}

/** One palette as the homepage's variables (style.css, foundation.css). */
function pageVariables(t: ResolvedSpaceTheme, p: SpacePalette, dark: boolean): Record<string, string> {
  const variables: Record<string, string> = {
    "--space-bg": p.page,
    "--space-page-image": p.pageImage ?? "none",
    "--space-card": p.card,
    "--space-widget": p.card,
    "--space-text": p.text,
    "--space-muted": p.muted,
    "--space-line": p.line,
    "--space-hover": mix(p.text, "transparent", 0.07),
    "--space-scrollbar": mix(p.text, "transparent", 0.24),
    "--space-accent": p.accent,
    "--space-on-accent": p.onAccent,
    "--space-feature": p.feature,
    "--space-feature-text": p.featureText,
    "--space-good": p.good,
    "--space-warn": p.warn,
    "--space-bad": p.bad,
    "--space-shadow": shadowOf(t.shadow, dark),
    "--space-shadow-raised": shadowOf("float", dark),
  };
  p.series.forEach((color, i) => (variables[`--space-chart-${i + 1}`] = color));
  return variables;
}

/** What 细节 sets as plain values (the shapes that need more are in foundation.css, by --space-decor). */
function decorVariables(decor: SpaceDecor, radius: number): Record<string, string> {
  const round = ["capsule", "pebble", "dots"].includes(decor);
  const sizes: Record<SpaceDecor, [progress: number, ring: number, weight: number]> = {
    plain: [8, 9, 750],
    capsule: [14, 10, 700],
    led: [12, 8, 650],
    glow: [8, 8, 600],
    bento: [6, 7, 600],
    pebble: [16, 14, 600],
    dots: [18, 12, 800],
  };
  const [progress, ring, weight] = sizes[decor];
  return {
    "--space-control-radius": `${Math.max(4, Math.round(radius * 0.36))}px`,
    // Buttons and segmented controls: pills where the look is round.
    "--space-button-radius": round ? "999px" : `${Math.max(4, Math.round(radius * 0.36))}px`,
    // 强调卡片 with a hue: drifting glow (光晕), or a flat tile in the look's own colours.
    "--space-glow-cards": decor === "glow" ? "glow" : "flat",
    "--space-input-radius": round ? "999px" : `${Math.max(4, Math.round(radius * 0.36))}px`,
    "--space-cell-radius": decor === "led" ? "4px" : round ? "50%" : `${Math.max(3, Math.round(radius * 0.25))}px`,
    "--space-bar-radius": decor === "led" || decor === "bento" ? "2px" : round ? "999px" : "5px",
    "--space-progress-height": `${progress}px`,
    "--space-ring-stroke": `${ring}px`,
    "--space-number-weight": `${weight}`,
  };
}

const block = (selector: string, variables: Record<string, string>) =>
  `${selector} {\n${Object.entries(variables)
    .map(([name, value]) => `  ${name}: ${value};`)
    .join("\n")}\n}`;

/**
 * The look as CSS for a homepage: the variables on its root, light and dark. Empty for 默认. `fontFace`
 * answers the @font-face rule of a font the app carries (main has the files; the settings preview has none).
 */
export function spaceThemeCss(theme: ResolvedSpaceTheme | null, fontFace: (font: SpaceFont) => string = () => ""): string {
  if (!theme) return "";
  const r = theme.radius;
  const shared: Record<string, string> = {
    "--space-theme": theme.id,
    "--space-decor": theme.decor,
    "--space-radius": `${r}px`,
    "--space-radius-l": `${r}px`,
    "--space-radius-m": `${Math.round(r * 0.62)}px`,
    "--space-radius-s": `${Math.round(r * 0.42)}px`,
    "--space-themed": "yes",
    ...decorVariables(theme.decor, r),
  };
  for (const [hue, color] of Object.entries(theme.hues ?? {})) {
    shared[`--space-${hue}`] = color;
    shared[`--space-${hue}-deep`] = color;
    shared[`--space-${hue}-tint`] = mix(color, "#ffffff", 0.45);
    shared[`--space-${hue}-glow`] = mix(color, "#ffffff", 0.75);
  }
  const stack = spaceFontStack(theme.font);
  if (stack) {
    shared["--space-font"] = stack;
    shared["--space-heading-font"] = stack;
    shared["--space-ui-font"] = stack;
  }
  const light = { ...shared, ...pageVariables(theme, theme.light, theme.light === theme.dark && luminance(solid(theme.light.page, "#000000")) < 0.25) };
  const parts = [fontFace(theme.font), block(":root", light)];
  if (theme.dark !== theme.light) parts.push(`@media (prefers-color-scheme: dark) {\n${block(":root", pageVariables(theme, theme.dark, true))}\n}`);
  return parts.filter(Boolean).join("\n");
}

/** The look on the app's own space card around the homepage (its title row): the page colour and text. */
export function spaceThemeChromeCss(theme: ResolvedSpaceTheme | null, selector = '.card[data-kind="space"]'): string {
  if (!theme) return "";
  // The title row sits right above the page: where the page fades from the top, it takes that colour.
  const top = (p: SpacePalette) => /^linear-gradient\(180deg,\s*(#[0-9a-f]{6})/i.exec(p.pageImage ?? "")?.[1] ?? p.page;
  const chrome = (p: SpacePalette) => ({
    "--space-surface": top(p),
    "--card-fg": p.text,
    "--card-path": mix(p.text, "transparent", 0.62),
    "--space-muted": p.muted,
    "--hover": mix(p.text, "transparent", 0.08),
  });
  const parts = [block(selector, chrome(theme.light))];
  if (theme.dark !== theme.light) parts.push(`@media (prefers-color-scheme: dark) {\n${block(selector, chrome(theme.dark))}\n}`);
  return parts.join("\n");
}
