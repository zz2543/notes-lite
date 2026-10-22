// 模型选择 (2026-10-21, 方案 A): the models offered beside the agent's name, read from each agent's own
// configuration on this computer. The first choice is always 默认, which passes no model and leaves it
// to the agent's own settings; any other is passed on the command line, for a new conversation only.
// A model can also be typed when the one wanted is not listed. DeepSeek Harness takes its model only
// from its settings (agent-default-model), never per run, so it offers 默认 alone and says which it is.
//
// 2026-10-22 用户反馈 (Codex offered only the model in config.toml): an agent that can say which models it
// has is asked — `codex debug models` (the catalog Codex itself picks from), `pi --list-models` — and what
// it caches or is pointed to is read too (Codex's models_cache.json and model_catalog_json).
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { modelName, type AgentId } from "../shared/agentKinds";

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
  /** Runs the agent's command with these arguments and answers with what it printed; undefined when it failed. */
  list?(args: readonly string[]): Promise<string | undefined>;
}

/** What each agent is asked to list its models with; the others are not asked. */
export const modelListing: Partial<Record<AgentId, readonly string[]>> = { codex: ["debug", "models"], pi: ["--list-models"] };

/**
 * Runs `path` with `args`, nothing on its input, and answers with its output once it exits well; undefined
 * when it fails, prints too much or takes longer than `timeout` ms (then it is stopped).
 */
export function commandOutput(path: string, args: readonly string[], { env, timeout = 15_000 }: { env?: NodeJS.ProcessEnv; timeout?: number } = {}): Promise<string | undefined> {
  return new Promise((done) => {
    const shim = process.platform === "win32" && /\.(cmd|bat)$/i.test(path);
    let child: ReturnType<typeof spawn>;
    try {
      const options = { env, windowsHide: true, stdio: ["ignore", "pipe", "ignore"] as ["ignore", "pipe", "ignore"] };
      child = shim ? spawn(`"${path}"`, [...args], { ...options, shell: true }) : spawn(path, [...args], options);
    } catch {
      return done(undefined);
    }
    const chunks: Buffer[] = [];
    let size = 0;
    const timer = setTimeout(() => child.kill(), timeout);
    child.stdout!.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > 8 * 1024 * 1024) child.kill();
      else chunks.push(chunk);
    });
    child.on("error", () => (clearTimeout(timer), done(undefined)));
    child.on("close", (code) => {
      clearTimeout(timer);
      done(code === 0 ? Buffer.concat(chunks).toString("utf8") : undefined);
    });
  });
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
// Only names that can go on the command line as they are: one chosen is the one used.
const unique = (models: (string | undefined)[]) => [...new Set(models.map(modelName).filter((m): m is string => Boolean(m)))];

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

/** `model = "…"` lines of a TOML file: the top level's first, then its profiles'; and its model_catalog_json. */
function tomlModels(source: string): { top?: string; all: string[]; catalog?: string } {
  let section = "";
  let top: string | undefined;
  let catalog: string | undefined;
  const all: string[] = [];
  for (const line of source.split(/\r?\n/)) {
    const header = /^\s*\[([^\]]+)\]/.exec(line);
    if (header) {
      section = header[1]!.trim();
      continue;
    }
    const file = section === "" ? /^\s*model_catalog_json\s*=\s*["']([^"']+)["']/.exec(line) : null;
    if (file) catalog = file[1];
    const model = /^\s*model\s*=\s*["']([^"']+)["']/.exec(line);
    if (!model) continue;
    if (section === "") top = model[1];
    // Only where a model is chosen: the top level and profiles, not a provider's settings.
    if (section === "" || section.startsWith("profiles.")) all.push(model[1]!);
  }
  return { top, all, catalog };
}

/**
 * The models of a Codex catalog (`codex debug models`, models_cache.json, a model_catalog_json): those it
 * lists in its picker, by its priority. Anything else reads as none.
 */
export function codexCatalog(source: string | undefined): string[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(source ?? "");
  } catch {
    return [];
  }
  const entries = Array.isArray(parsed) ? parsed : Array.isArray((parsed as { models?: unknown })?.models) ? (parsed as { models: unknown[] }).models : [];
  const listed = entries
    .map((entry, index) => ({ entry: (entry && typeof entry === "object" ? entry : {}) as Record<string, unknown>, index }))
    .filter(({ entry }) => named(entry.slug) && (entry.visibility === undefined || entry.visibility === "list"));
  const priority = (entry: Record<string, unknown>) => (typeof entry.priority === "number" ? entry.priority : Number.POSITIVE_INFINITY);
  listed.sort((a, b) => priority(a.entry) - priority(b.entry) || a.index - b.index);
  return listed.map(({ entry }) => named(entry.slug)!);
}

async function codex(home: string, env: NodeJS.ProcessEnv, list: ModelHomes["list"]): Promise<AgentModels> {
  const folder = env.CODEX_HOME || join(home, ".codex");
  const { top, all, catalog } = tomlModels((await text(join(folder, "config.toml"))) ?? "");
  // What Codex itself offers, when it says; otherwise what it cached and what it was pointed to.
  const offered = codexCatalog(await list?.(modelListing.codex!));
  const known = offered.length
    ? offered
    : [
        ...codexCatalog(catalog ? await text(catalog.startsWith("~/") ? join(home, catalog.slice(2)) : catalog) : undefined),
        ...codexCatalog(await text(join(folder, "models_cache.json"))),
      ];
  return { current: top, models: unique([top, ...known, ...all]), choosable: true };
}

/** `pi --list-models`: a table of provider, model, context, max-out, thinking, images; as provider/model. */
export function piListing(source: string | undefined): string[] {
  const models: string[] = [];
  for (const line of (source ?? "").split(/\r?\n/)) {
    const cells = line.trim().split(/\s+/);
    if (cells.length < 6 || cells[0] === "provider") continue;
    const [thinking, images] = cells.slice(-2);
    if (!/^(yes|no)$/.test(thinking!) || !/^(yes|no)$/.test(images!)) continue;
    models.push(`${cells[0]}/${cells[1]}`);
  }
  return models;
}

async function pi(home: string, env: NodeJS.ProcessEnv, list: ModelHomes["list"]): Promise<AgentModels> {
  const folder = env.PI_CODING_AGENT_DIR || join(home, ".pi", "agent");
  const settings = await json(join(folder, "settings.json"));
  const custom = await json(join(folder, "models.json"));
  const current = named(settings.defaultModel);
  // Patterns (claude-*) choose among models rather than naming one.
  const enabled = Array.isArray(settings.enabledModels) ? settings.enabledModels.map(named).filter((m) => m && !/[*?]/.test(m)) : [];
  const providers = (custom.providers && typeof custom.providers === "object" ? Object.values(custom.providers) : []) as { models?: unknown }[];
  const declared = providers.flatMap((p) => (Array.isArray(p?.models) ? p.models.map((m) => named((m as { id?: unknown })?.id)) : []));
  const available = piListing(await list?.(modelListing.pi!));
  return { current, models: unique([current, ...enabled, ...declared, ...available]), choosable: true };
}

async function dsh(home: string, env: NodeJS.ProcessEnv): Promise<AgentModels> {
  const source = (await text(join(env.DSH_HOME || join(home, ".dsh"), "settings.yaml"))) ?? "";
  // agent-default-model: { provider, model }, as a block or on one line.
  const block = /^agent-default-model:[^\n]*(?:\n[ \t]+[^\n]*)*/m.exec(source)?.[0] ?? "";
  const current = /(?:^|[\s{,])model:\s*["']?([^"'\s,}]+)/.exec(block.replace(/^agent-default-model:/, ""))?.[1];
  return { current, models: [], choosable: false };
}

type Reader = (home: string, env: NodeJS.ProcessEnv, list: ModelHomes["list"]) => Promise<AgentModels>;
const readers: Record<AgentId, Reader> = { claude, codex, dsh, pi };

/** The models to offer for `agent`, from its configuration under the user's home, and from itself when it can say. */
export function agentModels(agent: AgentId, { home = homedir(), env = process.env, list }: ModelHomes = {}): Promise<AgentModels> {
  return readers[agent](home, env, list);
}

export { modelChoosable, modelName } from "../shared/agentKinds";
