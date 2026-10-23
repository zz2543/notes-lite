import type { Page } from "@playwright/test";
import { mkdir, realpath, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { installFakeAgent } from "../support/fakeAgent";
import { expect, launch, launchWith, library, showSide, test } from "./fixtures";

// Codex, DeepSeek Harness and Pi in the 助手栏, and 对话历史 (ticket 30), with fake agents on the app's
// search path that speak each one's output: none reaches a model.

const column = (page: Page) => page.getByRole("complementary", { name: "助手栏" });
const input = (page: Page) => column(page).getByRole("textbox", { name: "给助手的消息" });
const conversation = (page: Page) => column(page).getByRole("log", { name: "对话" });

/** The agent for a new conversation: its name's caret opens the installed agents. */
async function chooseAgent(page: Page, name: string) {
  await column(page).getByRole("button", { name: /^Agent：/ }).click();
  await page.getByRole("menuitemradio", { name }).click();
  await expect(column(page).getByRole("button", { name: `Agent：${name}` })).toBeVisible();
}

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
  // 完全权限 chosen in 设置 › 助手.
  await mkdir(join(scratch, "profile"), { recursive: true });
  await writeFile(join(scratch, "profile", "settings.json"), JSON.stringify({ preferences: { assistantPermissions: "full" } }));
  const { page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  const choice = column(page).getByRole("button", { name: /^Agent：/ });
  // Every one installed can be chosen: none is waiting to be supported.
  await choice.click();
  await expect(page.getByRole("menuitemradio")).toHaveText(["Codex", "DeepSeek Harness", "Pi"]);
  await page.keyboard.press("Escape");
  // Side by side: the figure on the left; the choice above the working folder on its right. Measured in one
  // go, as the column may still be sliding open.
  const [figure, chosen, folder] = await column(page).evaluate((el) => {
    const box = (selector: string) => el.querySelector(selector)!.getBoundingClientRect().toJSON() as DOMRect;
    return [box('[role="img"]'), box(".assistant-agent-picker"), box(".assistant-folder")] as const;
  });
  expect(chosen.x).toBeGreaterThanOrEqual(figure.x + figure.width);
  expect(folder.y).toBeGreaterThanOrEqual(chosen.y + chosen.height);
  expect(chosen.y).toBeLessThan(figure.y + figure.height);
  // 新对话 sits at the top, left of 对话历史; the composer holds only the message and send.
  const [fresh, history] = await column(page).evaluate((el) =>
    ["新对话", "对话历史"].map((name) => el.querySelector(`[aria-label="${name}"]`)!.getBoundingClientRect().toJSON() as DOMRect),
  );
  expect(fresh!.x + fresh!.width).toBeLessThanOrEqual(history!.x);
  expect(Math.abs(fresh!.y - history!.y)).toBeLessThan(1);
  await expect(column(page).getByRole("button", { name: "新对话" })).toBeDisabled();

  for (const [name, agent] of Object.entries(agents)) {
    await chooseAgent(page, name);
    await say(page, `你好，${name}`);
    const reply = name === "DeepSeek Harness" ? "DSH" : name;
    await expect(conversation(page)).toContainText(`${reply} 收到。`);
    // Its conversation keeps it: the switch gives way to its name.
    await expect(column(page).getByText(name, { exact: true })).toBeVisible();
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

test("对话历史 lists the library's conversations; one opened again is continued with its agent and working directory, after a restart too, and only read once its agent is gone", async ({ scratch }) => {
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

  await chooseAgent(page, "Codex");
  await say(page, "整理日记");
  await expect(conversation(page)).toContainText("整理好了。");
  await column(page).getByRole("button", { name: "新对话" }).click();
  await page.getByRole("treeitem", { name: "读书" }).click();
  await chooseAgent(page, "Claude Code");
  await say(page, "写书单");
  await expect(conversation(page)).toContainText("写好了。");

  await first.app.close();
  const again = await launch(scratch);
  page = again.page;
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await history().click();
  // The latest used first, each by its first message, its agent and its working directory.
  const items = list().getByRole("button");
  await expect(items).toHaveText([/^写书单/, /^整理日记/]);
  await expect(items.nth(0)).toContainText("Claude Code · 读书");
  await expect(items.nth(1)).toContainText("Codex · 日记");

  await items.nth(1).click();
  await expect(list()).toBeHidden();
  await expect(conversation(page)).toContainText("整理日记");
  await expect(conversation(page)).toContainText("整理好了。");
  // Wherever the user is now, it goes on with Codex in 日记.
  await page.getByRole("treeitem", { name: "读书" }).click();
  await expect(column(page).getByText("Codex", { exact: true })).toBeVisible();
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
  await expect(items).toHaveText([/^整理日记/, /^写书单/]);
  await expect(items.nth(0)).toHaveAttribute("aria-current", "true");
  await again.app.close();

  // With Codex gone, its conversation can still be read, but not continued.
  await rm(codex.path);
  const last = await launch(scratch);
  page = last.page;
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await history().click();
  await list().getByRole("button").nth(0).click();
  await expect(conversation(page)).toContainText("再细一点");
  await expect(column(page).getByRole("alert")).toHaveText("这个对话用的 Codex 没有安装，不能继续。");
  await input(page).fill("还在吗");
  await expect(column(page).getByRole("button", { name: "发送" })).toBeDisabled();
  await last.app.close();
});

test("with a space open, the agent is told the spaces' authoring guide and which space it is", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "健身/训练.md": "# 训练\n",
    ".notes/空间/健身.html": '<meta name="space-scope" content="健身">\n<p>健身主页</p>',
  });
  const agent = await installFakeAgent(join(scratch, "agents"), "claude", { steps: [{ say: "好的。" }] });
  const { page, app } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await page.getByRole("list", { name: "空间", exact: true }).getByRole("button", { name: "健身" }).click();
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await say(page, "把主页改成按周统计");
  await expect(conversation(page)).toContainText("好的。");
  const [run] = await agent.runs();
  expect(run!.stdin).toContain("请先完整阅读并遵守编写说明：.notes/空间/编写说明.md");
  expect(run!.stdin).toContain("- 健身：.notes/空间/健身.html（当前打开）");
  await app.close();
});
