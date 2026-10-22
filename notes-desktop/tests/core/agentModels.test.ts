import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";
import { agentModels, codexCatalog, commandOutput, modelName, piListing } from "../../src/core";
import { scratchFolder } from "../support/library";

// 模型选择 (assistant-spec, 方案 A): the models offered beside each agent's name, read from its own
// configuration under the user's home; 默认 names the one its settings pick.

async function home(files: Record<string, string>) {
  const at = await scratchFolder("notes-desktop-home-");
  for (const [path, text] of Object.entries(files)) {
    await mkdir(dirname(join(at, path)), { recursive: true });
    await writeFile(join(at, path), text);
  }
  return at;
}

describe("模型选择", () => {
  it("offers Claude Code's aliases, and its settings' model, family models and allowed models first", async () => {
    expect(await agentModels("claude", { home: await home({}), env: {} })).toEqual({ models: ["opus", "sonnet", "haiku"], choosable: true });
    const at = await home({
      ".claude/settings.json": JSON.stringify({
        model: "claude-sonnet-4-5",
        env: { ANTHROPIC_DEFAULT_OPUS_MODEL: "claude-opus-4-1" },
        availableModels: ["sonnet", "claude-haiku-4-5"],
      }),
    });
    expect(await agentModels("claude", { home: at, env: {} })).toEqual({
      current: "claude-sonnet-4-5",
      models: ["claude-sonnet-4-5", "opus", "sonnet", "haiku", "claude-opus-4-1", "claude-haiku-4-5"],
      choosable: true,
    });
    // CLAUDE_CONFIG_DIR moves the settings; ANTHROPIC_MODEL in the environment counts when they say none.
    const moved = await home({ "elsewhere/settings.json": "{}" });
    expect(await agentModels("claude", { home: moved, env: { CLAUDE_CONFIG_DIR: join(moved, "elsewhere"), ANTHROPIC_MODEL: "opus" } })).toMatchObject({ current: "opus" });
  });

  it("reads Codex's model and its profiles' from config.toml, not a provider's", async () => {
    const at = await home({
      ".codex/config.toml": 'model = "gpt-5.2"\n\n[model_providers.local]\nmodel = "nope"\n\n[profiles.fast]\nmodel = "gpt-5.2-mini"\n',
    });
    expect(await agentModels("codex", { home: at, env: {} })).toEqual({ current: "gpt-5.2", models: ["gpt-5.2", "gpt-5.2-mini"], choosable: true });
    expect(await agentModels("codex", { home: await home({}), env: {} })).toEqual({ models: [], choosable: true });
  });

  it("offers every model Codex lists (`codex debug models`), by its priority, hidden ones left out", async () => {
    // 2026-10-22 用户反馈: only the model in config.toml was offered.
    const at = await home({ ".codex/config.toml": 'model = "gpt-6-luna"\n\n[profiles.fast]\nmodel = "gpt-5.2-mini"\n' });
    const catalog = JSON.stringify({
      models: [
        { slug: "gpt-6-sol", visibility: "list", priority: 2 },
        { slug: "gpt-6-luna", visibility: "list", priority: 1 },
        { slug: "codex-auto-review", visibility: "hide", priority: 0 },
        { slug: "gpt-5.5", priority: 3 },
      ],
    });
    const asked: (readonly string[])[] = [];
    const list = async (args: readonly string[]) => (asked.push(args), catalog);
    expect(await agentModels("codex", { home: at, env: {}, list })).toEqual({
      current: "gpt-6-luna",
      models: ["gpt-6-luna", "gpt-6-sol", "gpt-5.5", "gpt-5.2-mini"],
      choosable: true,
    });
    expect(asked).toEqual([["debug", "models"]]);
  });

  it("falls back to Codex's model cache and the catalog it is pointed to when it cannot be asked", async () => {
    const at = await home({
      ".codex/config.toml": 'model = "gpt-6-luna"\nmodel_catalog_json = "~/.codex/mine.json"\n',
      ".codex/mine.json": JSON.stringify({ models: [{ slug: "kimi-k3", visibility: "list", priority: 1 }] }),
      ".codex/models_cache.json": JSON.stringify({ fetched_at: "2026-10-22T00:00:00Z", models: [{ slug: "gpt-6-sol", visibility: "list", priority: 1 }] }),
    });
    expect(await agentModels("codex", { home: at, env: {}, list: async () => undefined })).toEqual({
      current: "gpt-6-luna",
      models: ["gpt-6-luna", "kimi-k3", "gpt-6-sol"],
      choosable: true,
    });
    expect(codexCatalog("not json")).toEqual([]);
    expect(codexCatalog(JSON.stringify([{ slug: "a" }, { slug: 3 }, null]))).toEqual(["a"]);
  });

  it("offers what `pi --list-models` lists, as provider/model", async () => {
    const at = await home({ ".pi/agent/settings.json": JSON.stringify({ defaultModel: "anthropic/claude-sonnet-4-5" }) });
    const table = [
      "provider  model              context max-out thinking images",
      "anthropic claude-sonnet-4-5  200K    64K     yes      yes",
      "openai    gpt-6-sol          400K    128K    yes      yes",
      "",
    ].join("\n");
    expect(await agentModels("pi", { home: at, env: {}, list: async () => table })).toEqual({
      current: "anthropic/claude-sonnet-4-5",
      models: ["anthropic/claude-sonnet-4-5", "openai/gpt-6-sol"],
      choosable: true,
    });
    expect(piListing("No models available. Use /login.")).toEqual([]);
  });

  it("runs a command for its output, answering undefined when it fails", async () => {
    expect(await commandOutput(process.execPath, ["-e", "process.stdout.write('ok')"])).toBe("ok");
    expect(await commandOutput(process.execPath, ["-e", "process.exit(2)"])).toBeUndefined();
    expect(await commandOutput(join(await home({}), "missing"), [])).toBeUndefined();
    expect(await commandOutput(process.execPath, ["-e", "setTimeout(() => {}, 5000)"], { timeout: 100 })).toBeUndefined();
  });

  it("reads Pi's default and enabled models, leaving out patterns, and the models it was told of", async () => {
    const at = await home({
      ".pi/agent/settings.json": JSON.stringify({ defaultModel: "claude-sonnet-4-5", enabledModels: ["claude-*", "gpt-5.2"] }),
      ".pi/agent/models.json": JSON.stringify({ providers: { local: { models: [{ id: "qwen3-coder" }, { name: "no id" }] } } }),
    });
    expect(await agentModels("pi", { home: at, env: {} })).toEqual({
      current: "claude-sonnet-4-5",
      models: ["claude-sonnet-4-5", "gpt-5.2", "qwen3-coder"],
      choosable: true,
    });
  });

  it("names DeepSeek Harness's model from its settings, without a choice: it takes none per run", async () => {
    const at = await home({ ".dsh/settings.yaml": "theme: dark\nagent-default-model:\n  provider: deepseek\n  model: deepseek-v4-flash\n" });
    expect(await agentModels("dsh", { home: at, env: {} })).toEqual({ current: "deepseek-v4-flash", models: [], choosable: false });
    const inline = await home({ ".dsh/settings.yaml": "agent-default-model: { provider: deepseek, model: deepseek-v4-pro }\n" });
    expect(await agentModels("dsh", { home: inline, env: {} })).toMatchObject({ current: "deepseek-v4-pro" });
  });

  it("offers only models that can go on the command line as they are", async () => {
    const at = await home({ ".pi/agent/settings.json": JSON.stringify({ defaultModel: "qwen3", enabledModels: ["has space", "--flag", "gpt-5.2"] }) });
    expect(await agentModels("pi", { home: at, env: {} })).toMatchObject({ models: ["qwen3", "gpt-5.2"] });
  });

  it("reads broken settings as none", async () => {
    const at = await home({ ".claude/settings.json": "{ not json", ".pi/agent/settings.json": "[]" });
    expect(await agentModels("claude", { home: at, env: {} })).toEqual({ models: ["opus", "sonnet", "haiku"], choosable: true });
    expect(await agentModels("pi", { home: at, env: {} })).toEqual({ models: [], choosable: true });
  });

  it("takes a typed model only as one word for the command line", () => {
    expect(modelName("  gpt-5.2 ")).toBe("gpt-5.2");
    expect(modelName("anthropic/claude-sonnet-4-5@20250929")).toBe("anthropic/claude-sonnet-4-5@20250929");
    expect(modelName("")).toBeUndefined();
    expect(modelName("two words")).toBeUndefined();
    expect(modelName("x;rm")).toBeUndefined();
    // Never read as an option, nor anything but text.
    expect(modelName("--resume")).toBeUndefined();
    expect(modelName("-x")).toBeUndefined();
    expect(modelName(42)).toBeUndefined();
  });
});
