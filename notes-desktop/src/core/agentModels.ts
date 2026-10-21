// 模型选择 (2026-10-21, 方案 A): the models offered beside the agent's name, read from each agent's own
// configuration on this computer. The first choice is always 默认, which passes no model and leaves it
// to the agent's own settings; any other is passed on the command line, for a new conversation only.
// A model can also be typed when the one wanted is not listed. DeepSeek Harness takes its model only
// from its settings (agent-default-model), never per run, so it offers 默认 alone and says which it is.
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { AgentId } from "../shared/agentKinds";

export interface AgentModels {
  /** The model the agent's own settings pick, when they say; what 默认 runs. */
  current?: string;
  /** The models to offer after 默认, without repeats. */
  models: string[];
  /** Whether a model can be chosen at all; false when the agent takes it only from its settings. */
  choosable: boolean;
}

export interface ModelHomes {
  /** The user's home folder. */
  home?: string;
  env?: NodeJS.ProcessEnv;
}

/** Claude Code's aliases, which follow the newest model of each family. */
export const claudeAliases = ["opus", "sonnet", "haiku"] as const;

const text = (path: string) => readFile(path, "utf8").catch(() => undefined);
const json = async (path: string): Promise<Record<string, unknown>> => {
  try {
    const value: unknown = JSON.parse((await text(path)) ?? "");
    return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
  } catch {
    return {};
  }
};
const named = (value: unknown): string | undefined => (typeof value === "string" && value.trim() ? value.trim() : undefined);
const unique = (models: (string | undefined)[]) => [...new Set(models.filter((m): m is string => Boolean(m)))];

async function claude(home: string, env: NodeJS.ProcessEnv): Promise<AgentModels> {
  const folder = env.CLAUDE_CONFIG_DIR || join(home, ".claude");
  const settings = await json(join(folder, "settings.json"));
  const settingsEnv = (settings.env && typeof settings.env === "object" ? settings.env : {}) as Record<string, unknown>;
  const fromEnv = (key: string) => named(settingsEnv[key]) ?? named(env[key]);
  const current = named(settings.model) ?? fromEnv("ANTHROPIC_MODEL");
  const families = ["OPUS", "SONNET", "HAIKU"].map((family) => fromEnv(`ANTHROPIC_DEFAULT_${family}_MODEL`));
  const available = Array.isArray(settings.availableModels) ? settings.availableModels.map(named) : [];
  return { current, models: unique([current, ...claudeAliases, ...families, ...available]), choosable: true };
}

/** `model = "…"` lines of a TOML file: the top level's first, then its profiles'. */
function tomlModels(source: string): { top?: string; all: string[] } {
  let section = "";
  let top: string | undefined;
  const all: string[] = [];
  for (const line of source.split(/\r?\n/)) {
    const header = /^\s*\[([^\]]+)\]/.exec(line);
    if (header) {
      section = header[1]!.trim();
      continue;
    }
    const model = /^\s*model\s*=\s*["']([^"']+)["']/.exec(line);
    if (!model) continue;
    if (section === "") top = model[1];
    // Only where a model is chosen: the top level and profiles, not a provider's settings.
    if (section === "" || section.startsWith("profiles.")) all.push(model[1]!);
  }
  return { top, all };
}

async function codex(home: string, env: NodeJS.ProcessEnv): Promise<AgentModels> {
  const { top, all } = tomlModels((await text(join(env.CODEX_HOME || join(home, ".codex"), "config.toml"))) ?? "");
  return { current: top, models: unique([top, ...all]), choosable: true };
}

async function pi(home: string, env: NodeJS.ProcessEnv): Promise<AgentModels> {
  const folder = env.PI_CODING_AGENT_DIR || join(home, ".pi", "agent");
  const settings = await json(join(folder, "settings.json"));
  const custom = await json(join(folder, "models.json"));
  const current = named(settings.defaultModel);
  // Patterns (claude-*) choose among models rather than naming one.
  const enabled = Array.isArray(settings.enabledModels) ? settings.enabledModels.map(named).filter((m) => m && !/[*?]/.test(m)) : [];
  const providers = (custom.providers && typeof custom.providers === "object" ? Object.values(custom.providers) : []) as { models?: unknown }[];
  const declared = providers.flatMap((p) => (Array.isArray(p?.models) ? p.models.map((m) => named((m as { id?: unknown })?.id)) : []));
  return { current, models: unique([current, ...enabled, ...declared]), choosable: true };
}

async function dsh(home: string, env: NodeJS.ProcessEnv): Promise<AgentModels> {
  const source = (await text(join(env.DSH_HOME || join(home, ".dsh"), "settings.yaml"))) ?? "";
  // agent-default-model: { provider, model }, as a block or on one line.
  const block = /^agent-default-model:[^\n]*(?:\n[ \t]+[^\n]*)*/m.exec(source)?.[0] ?? "";
  const current = /\bmodel:\s*["']?([^"'\s,}]+)/.exec(block.replace(/^agent-default-model:/, ""))?.[1];
  return { current, models: [], choosable: false };
}

const readers: Record<AgentId, (home: string, env: NodeJS.ProcessEnv) => Promise<AgentModels>> = { claude, codex, dsh, pi };

/** The models to offer for `agent`, from its configuration under the user's home. */
export function agentModels(agent: AgentId, { home = homedir(), env = process.env }: ModelHomes = {}): Promise<AgentModels> {
  return readers[agent](home, env);
}

export { modelName } from "../shared/agentKinds";
