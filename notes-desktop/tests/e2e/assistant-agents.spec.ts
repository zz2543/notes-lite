import type { Page } from "@playwright/test";
import { realpath } from "node:fs/promises";
import { join } from "node:path";
import { installFakeAgent } from "../support/fakeAgent";
import { expect, launch, launchWith, library, test } from "./fixtures";

// Codex, DeepSeek Harness and Pi in the 助手栏, and 对话历史 (ticket 30), with fake agents on the app's
// search path that speak each one's output: none reaches a model.

const column = (page: Page) => page.getByRole("complementary", { name: "助手栏" });
const input = (page: Page) => column(page).getByRole("textbox", { name: "给助手的消息" });
const conversation = (page: Page) => column(page).getByRole("log", { name: "对话" });

async function say(page: Page, text: string) {
  await input(page).fill(text);
  await input(page).press("Enter");
  await expect(conversation(page).getByText(text, { exact: true })).toBeVisible();
}

test("Codex, DeepSeek Harness and Pi can each be chosen, answer a turn with full permissions and continue the conversation", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记\n" });
  const agents = {
    Codex: await installFakeAgent(join(scratch, "agents"), "codex", { session: "x-1", steps: [{ say: "Codex 收到。" }] }),
    "DeepSeek Harness": await installFakeAgent(join(scratch, "agents"), "dsh", { session: "d-1", steps: [{ say: "DSH 收到。" }] }),
    Pi: await installFakeAgent(join(scratch, "agents"), "pi", { session: "p-1", steps: [{ say: "Pi 收到。" }] }),
  };
  const { page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  const choice = column(page).getByRole("radiogroup", { name: "Agent" });
  // Every one installed can be chosen: none is waiting to be supported.
  await expect(choice.getByRole("radio")).toHaveText(["Codex", "DeepSeek Harness", "Pi"]);

  for (const [name, agent] of Object.entries(agents)) {
    await choice.getByRole("radio", { name }).click();
    await say(page, `你好，${name}`);
    const reply = name === "DeepSeek Harness" ? "DSH" : name;
    await expect(conversation(page)).toContainText(`${reply} 收到。`);
    // Its conversation keeps it: the switch gives way to its name.
    await expect(column(page).locator(".assistant-agent")).toHaveText(name);
    await say(page, "再来");
    await expect(conversation(page).getByText(`${reply} 收到。`)).toHaveCount(2);
    await expect(column(page).getByRole("img", { name: /助手形象：(完成|待命)/ })).toBeVisible();

    const [first, second] = await agent.runs();
    expect(first!.argv).toEqual(
      expect.arrayContaining({ Codex: ["--dangerously-bypass-approvals-and-sandbox"], "DeepSeek Harness": ["--profile", "headless"], Pi: ["--mode", "json"] }[name]!),
    );
    if (name === "DeepSeek Harness") expect(first!.permissionMode).toBe("danger-full-access");
    expect(second!.argv).toContain({ Codex: "x-1", "DeepSeek Harness": "d-1", Pi: "p-1" }[name]);
    await column(page).getByRole("button", { name: "新对话" }).click();
  }
});

test("对话历史 lists the library's conversations; one opened again is continued with its agent and working directory, after a restart too", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/周一.md": "# 周一\n", "读书/书单.md": "# 书单\n" });
  const codex = await installFakeAgent(join(scratch, "agents"), "codex", { session: "x-1", steps: [{ say: "整理好了。" }] });
  const claude = await installFakeAgent(join(scratch, "agents"), "claude", { session: "c-1", steps: [{ say: "写好了。" }] });
  const first = await launchWith(scratch, root);
  let page = first.page;
  await page.getByRole("treeitem", { name: "日记" }).click();
  await page.getByRole("button", { name: "打开助手栏" }).click();
  const history = () => column(page).getByRole("button", { name: "对话历史" });
  const list = () => column(page).getByRole("navigation", { name: "对话历史" });
  await history().click();
  await expect(list()).toHaveText("还没有对话。");
  await history().click();

  await column(page).getByRole("radiogroup", { name: "Agent" }).getByRole("radio", { name: "Codex" }).click();
  await say(page, "整理日记");
  await expect(conversation(page)).toContainText("整理好了。");
  await column(page).getByRole("button", { name: "新对话" }).click();
  await page.getByRole("treeitem", { name: "读书" }).click();
  await column(page).getByRole("radiogroup", { name: "Agent" }).getByRole("radio", { name: "Claude Code" }).click();
  await say(page, "写书单");
  await expect(conversation(page)).toContainText("写好了。");

  await first.app.close();
  const again = await launch(scratch);
  page = again.page;
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await history().click();
  // The latest used first, each by its first message, its agent and its working directory.
  const items = list().getByRole("button");
  await expect(items.locator(".history-title")).toHaveText(["写书单", "整理日记"]);
  await expect(items.nth(0)).toContainText("Claude Code · 读书");
  await expect(items.nth(1)).toContainText("Codex · 日记");

  await items.nth(1).click();
  await expect(list()).toBeHidden();
  await expect(conversation(page)).toContainText("整理日记");
  await expect(conversation(page)).toContainText("整理好了。");
  // Wherever the user is now, it goes on with Codex in 日记.
  await page.getByRole("treeitem", { name: "读书" }).click();
  await expect(column(page).locator(".assistant-agent")).toHaveText("Codex");
  await expect(column(page).getByRole("button", { name: "工作目录：日记" })).toBeVisible();
  await say(page, "再细一点");
  await expect(conversation(page).getByText("整理好了。")).toHaveCount(2);
  const runs = await codex.runs();
  expect(runs).toHaveLength(2);
  expect(runs[1]!.argv).toContain("x-1");
  expect(await realpath(runs[1]!.cwd)).toBe(await realpath(join(root, "日记")));
  expect(await claude.runs()).toHaveLength(1);

  // It is the latest used now, and marked as the one shown.
  await history().click();
  await expect(items.locator(".history-title")).toHaveText(["整理日记", "写书单"]);
  await expect(items.nth(0)).toHaveAttribute("aria-current", "true");
  await again.app.close();
});
