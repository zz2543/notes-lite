// 设置: what the user chose in the settings panel. Kept with the app (settings.json in its profile),
// never inside a library. Later settings (排版 ticket 16) add a field, its choices
// and its default here; anything missing or unknown on disk reads as the default.

/** 外观: 跟随系统, 浅色, 深色. */
export type ColorScheme = "system" | "light" | "dark";
/** 强调色: the system's, or one of the design system's presets (tokens.css --accent-<name>). */
export type AccentChoice = "system" | "blue" | "purple" | "pink" | "orange" | "green";
/** 笔记列表详细程度: 简洁 (titles), 标准 (and dates), 详细 (and a one-line summary). */
export type ListDetail = "compact" | "standard" | "detailed";
/** 动效强度: 轻, 标准, 强. */
export type MotionIntensity = "light" | "standard" | "strong";
/** 导航模式: 双栏导航 (folder tree, then 当前目录内容) or 单栏导航 (folders and notes in one tree). */
export type Navigation = "double" | "single";

export interface Preferences {
  colorScheme: ColorScheme;
  accent: AccentChoice;
  listDetail: ListDetail;
  motion: MotionIntensity;
  navigation: Navigation;
}

export const choices: { readonly [K in keyof Preferences]: readonly Preferences[K][] } = {
  colorScheme: ["system", "light", "dark"],
  accent: ["system", "blue", "purple", "pink", "orange", "green"],
  listDetail: ["compact", "standard", "detailed"],
  motion: ["light", "standard", "strong"],
  navigation: ["double", "single"],
};

export const defaultPreferences: Preferences = { colorScheme: "system", accent: "system", listDetail: "compact", motion: "strong", navigation: "double" };

/** Whatever was stored (or sent), as preferences: known keys with known values, the rest defaults. */
export function readPreferences(stored: unknown, base: Preferences = defaultPreferences): Preferences {
  const raw = (stored && typeof stored === "object" ? stored : {}) as Record<string, unknown>;
  const pick = <K extends keyof Preferences>(key: K): Preferences[K] =>
    (choices[key] as readonly unknown[]).includes(raw[key]) ? (raw[key] as Preferences[K]) : base[key];
  return Object.fromEntries((Object.keys(choices) as Array<keyof Preferences>).map((key) => [key, pick(key)])) as unknown as Preferences;
}
