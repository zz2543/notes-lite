import { agents, modelName, type AgentId } from "./agentKinds";
import { defaultTypography, readTypography, type Typography } from "./typography";

// 设置: what the user chose in the settings panel. Kept with the app (settings.json in its profile),
// never inside a library. A later setting adds a field, its choices and its default here; anything
// missing or unknown on disk reads as the default. 排版 is a group of its own (typography.ts).

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
/** 写入审查: 每轮结束后审查 (a card after each assistant turn) or 直接保留. */
export type ReviewMode = "review" | "keep";
/** 界面特效 and each of its effects: on or off. Off is the interface as it was before them. */
export type Toggle = "on" | "off";

export interface Preferences {
  colorScheme: ColorScheme;
  accent: AccentChoice;
  listDetail: ListDetail;
  motion: MotionIntensity;
  navigation: Navigation;
  assistantReview: ReviewMode;
  /** 界面特效 (设置 › 动画): all of them; off leaves the interface exactly as without them. */
  effects: Toggle;
  /** 流光边框: a beam around the assistant's composer while it works, and on 让助手生成主页. */
  effectBeam: Toggle;
  /** 思考光球: an orb beside 正在思考… and beside the step the assistant is on. */
  effectOrbs: Toggle;
  /** 液态滑块: the selection in segmented controls and the side switch moves as a liquid drop. */
  effectGooey: Toggle;
  /** 排版: a change may carry only the fields it changes; the rest stay. */
  typography: Typography;
  /**
   * 模型选择: the model last chosen beside each agent's name, for its next new conversation; an agent
   * not here runs its own default. A change carries only the agents it changes, "" for back to 默认.
   */
  agentModels: Partial<Record<AgentId, string>>;
}

/** The settings that are one of a few choices. */
type ChoiceKey = Exclude<keyof Preferences, "typography" | "agentModels">;

export const choices: { readonly [K in ChoiceKey]: readonly Preferences[K][] } = {
  colorScheme: ["system", "light", "dark"],
  accent: ["system", "blue", "purple", "pink", "orange", "green"],
  listDetail: ["compact", "standard", "detailed"],
  motion: ["light", "standard", "strong"],
  navigation: ["double", "single"],
  assistantReview: ["review", "keep"],
  effects: ["on", "off"],
  effectBeam: ["on", "off"],
  effectOrbs: ["on", "off"],
  effectGooey: ["on", "off"],
};

export const defaultPreferences: Preferences = {
  colorScheme: "system",
  accent: "system",
  listDetail: "compact",
  motion: "strong",
  navigation: "double",
  assistantReview: "review",
  effects: "on",
  effectBeam: "on",
  effectOrbs: "on",
  effectGooey: "on",
  typography: defaultTypography,
  agentModels: {},
};

/** Whatever was stored (or sent), as preferences: known keys with known values, the rest from `base`. */
export function readPreferences(stored: unknown, base: Preferences = defaultPreferences): Preferences {
  const raw = (stored && typeof stored === "object" ? stored : {}) as Record<string, unknown>;
  const pick = <K extends ChoiceKey>(key: K): Preferences[K] =>
    (choices[key] as readonly unknown[]).includes(raw[key]) ? (raw[key] as Preferences[K]) : base[key];
  const picked = Object.fromEntries((Object.keys(choices) as ChoiceKey[]).map((key) => [key, pick(key)])) as Omit<Preferences, "typography" | "agentModels">;
  return { ...picked, typography: readTypography(raw.typography, base.typography), agentModels: readAgentModels(raw.agentModels, base.agentModels) };
}

function readAgentModels(stored: unknown, base: Preferences["agentModels"]): Preferences["agentModels"] {
  const raw = (stored && typeof stored === "object" ? stored : {}) as Record<string, unknown>;
  const models = { ...base };
  for (const { id } of agents) {
    const value = raw[id];
    if (value === "") delete models[id];
    else if (typeof value === "string" && modelName(value)) models[id] = modelName(value);
  }
  return models;
}
