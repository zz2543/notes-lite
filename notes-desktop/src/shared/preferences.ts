import { agents, modelName, type AgentId } from "./agentKinds";
import { attachmentFolderOf, attachmentNamings, defaultAttachmentSettings, type AttachmentNaming } from "./attachments";
import type { PermissionMode } from "./conversation";
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

export interface Preferences {
  colorScheme: ColorScheme;
  accent: AccentChoice;
  listDetail: ListDetail;
  motion: MotionIntensity;
  navigation: Navigation;
  assistantReview: ReviewMode;
  /** 助手权限: 执行前询问 (commands, the web and files outside the folder wait for the user) or 完全权限. */
  assistantPermissions: PermissionMode;
  /** 排版: a change may carry only the fields it changes; the rest stay. */
  typography: Typography;
  /**
   * 模型选择: the model last chosen beside each agent's name, for its next new conversation; an agent
   * not here runs its own default. A change carries only the agents it changes, "" for back to 默认.
   */
  agentModels: Partial<Record<AgentId, string>>;
  /** 附件位置: a library-relative folder, the same in every library (attachments.ts). */
  attachmentFolder: string;
  /** 附件命名. */
  attachmentNaming: AttachmentNaming;
}

/** The settings that are one of a few choices. */
type ChoiceKey = Exclude<keyof Preferences, "typography" | "agentModels" | "attachmentFolder">;

export const choices: { readonly [K in ChoiceKey]: readonly Preferences[K][] } = {
  colorScheme: ["system", "light", "dark"],
  accent: ["system", "blue", "purple", "pink", "orange", "green"],
  listDetail: ["compact", "standard", "detailed"],
  motion: ["light", "standard", "strong"],
  navigation: ["double", "single"],
  assistantReview: ["review", "keep"],
  assistantPermissions: ["ask", "full"],
  attachmentNaming: attachmentNamings,
};

export const defaultPreferences: Preferences = {
  colorScheme: "system",
  accent: "system",
  listDetail: "compact",
  motion: "strong",
  navigation: "double",
  assistantReview: "review",
  assistantPermissions: "ask",
  typography: defaultTypography,
  agentModels: {},
  attachmentFolder: defaultAttachmentSettings.folder,
  attachmentNaming: defaultAttachmentSettings.naming,
};

/** Whatever was stored (or sent), as preferences: known keys with known values, the rest from `base`. */
export function readPreferences(stored: unknown, base: Preferences = defaultPreferences): Preferences {
  const raw = (stored && typeof stored === "object" ? stored : {}) as Record<string, unknown>;
  const pick = <K extends ChoiceKey>(key: K): Preferences[K] =>
    (choices[key] as readonly unknown[]).includes(raw[key]) ? (raw[key] as Preferences[K]) : base[key];
  const picked = Object.fromEntries((Object.keys(choices) as ChoiceKey[]).map((key) => [key, pick(key)])) as Omit<Preferences, "typography" | "agentModels" | "attachmentFolder">;
  return {
    ...picked,
    typography: readTypography(raw.typography, base.typography),
    agentModels: readAgentModels(raw.agentModels, base.agentModels),
    attachmentFolder: attachmentFolderOf(raw.attachmentFolder) ?? base.attachmentFolder,
  };
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
