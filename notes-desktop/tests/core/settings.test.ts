import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { settingsStore } from "../../src/main/settings";
import { defaultPreferences, readPreferences } from "../../src/shared/preferences";

let dir: string;
afterEach(() => rm(dir, { recursive: true, force: true }));

describe("settings store", () => {
  it("keeps every change made in quick succession", async () => {
    dir = await mkdtemp(join(tmpdir(), "notes-settings-"));
    const store = settingsStore(dir);
    await Promise.all([
      store.update({ libraryPath: "/笔记库" }),
      store.update({ preferences: { colorScheme: "dark" } }),
      store.update({ preferences: { colorScheme: "dark", motion: "light" } }),
    ]);
    expect(await settingsStore(dir).read()).toEqual({ libraryPath: "/笔记库", preferences: { colorScheme: "dark", motion: "light" } });
  });
});

describe("preferences", () => {
  it("keep the model chosen per agent (模型选择): a change carries only the agents it changes, \"\" back to 默认", () => {
    expect(defaultPreferences.agentModels).toEqual({});
    const chosen = readPreferences({ agentModels: { claude: " opus ", codex: "gpt-5.2", nobody: "x", pi: 3 } });
    expect(chosen.agentModels).toEqual({ claude: "opus", codex: "gpt-5.2" });
    expect(readPreferences({ agentModels: { codex: "", pi: "a b" } }, chosen).agentModels).toEqual({ claude: "opus" });
    expect(readPreferences({ agentModels: "opus" }, chosen).agentModels).toEqual({ claude: "opus", codex: "gpt-5.2" });
  });

  it("keep the agent last chosen in 助手栏, for new conversations after a restart too", () => {
    expect(defaultPreferences.assistantAgent).toBeNull();
    const chosen = readPreferences({ assistantAgent: "dsh" });
    expect(chosen.assistantAgent).toBe("dsh");
    expect(readPreferences({ assistantAgent: "codex" }, chosen).assistantAgent).toBe("codex");
    expect(readPreferences({ assistantAgent: "nobody" }, chosen).assistantAgent).toBe("dsh");
    expect(readPreferences({ colorScheme: "dark" }, chosen).assistantAgent).toBe("dsh");
  });

  it("read missing or unknown values as the defaults: 跟随系统, 简洁, 强, 双栏", () => {
    expect(readPreferences(undefined)).toMatchObject({ colorScheme: "system", accent: "system", listDetail: "compact", motion: "strong", navigation: "double" });
    expect(readPreferences({ colorScheme: "sepia", accent: "purple", motion: 3, navigation: "triple", extra: true })).toEqual({
      ...defaultPreferences,
      accent: "purple",
    });
  });
});
