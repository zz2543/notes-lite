import type { Page } from "@playwright/test";
import { readdir, readFile, realpath, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { installFakeAgent } from "../support/fakeAgent";
import { expect, launchWith, library, test } from "./fixtures";

// 一轮 (assistant-spec) with a fake Claude Code on the app's search path: it never reaches a model.

const column = (page: Page) => page.getByRole("complementary", { name: "助手栏" });
const input = (page: Page) => column(page).getByRole("textbox", { name: "给助手的消息" });

async function openNote(page: Page, folder: string, title: string) {
  await page.getByRole("treeitem", { name: folder }).click();
  await page.getByRole("list", { name: "当前目录内容" }).getByText(title, { exact: true }).click();
  await expect(page.getByLabel("笔记正文")).toContainText(title);
}

test("a turn with the open note: its folder is the working directory, the reply streams, tool calls fold into a timeline and the figure follows", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/周一.md": "# 周一\n", "随记.md": "随记\n" });
  const hold = join(scratch, "go-on");
  const agent = await installFakeAgent(join(scratch, "agents"), "claude", {
    session: "s-1",
    steps: [
      { say: "我来看看这篇笔记，然后补充计划。" },
      { tool: "Read", input: { file_path: join(root, "日记", "周一.md") } },
      { tool: "Edit", input: { file_path: join(root, "日记", "周一.md") }, write: { path: "周一.md", text: "# 周一\n\n- 跑步\n" }, waitFor: hold },
      { say: "已经加上了跑步。" },
    ],
  });
  const { page } = await launchWith(scratch, root);
  await openNote(page, "日记", "周一");
  await page.keyboard.press("ControlOrMeta+KeyJ");

  // The open note is attached and its folder is where the agent will work.
  await expect(column(page).getByRole("button", { name: "工作目录：日记" })).toBeVisible();
  const attached = column(page).getByRole("list", { name: "附带的笔记" });
  await expect(attached.getByRole("listitem")).toHaveText(["周一"]);

  await input(page).fill("帮我补充计划");
  await input(page).press("Enter");

  const conversation = column(page).getByRole("log", { name: "对话" });
  await expect(conversation.getByText("帮我补充计划")).toBeVisible();
  await expect(conversation).toContainText("我来看看这篇笔记，然后补充计划。");
  // Held while writing: the figure says so, and the timeline is folded to one line.
  await expect(column(page).getByRole("img", { name: "助手形象：写入" })).toBeVisible();
  const timeline = conversation.getByRole("button", { name: /2 个步骤/ });
  await expect(timeline).toHaveAttribute("aria-expanded", "false");
  await timeline.click();
  await expect(conversation.getByRole("list", { name: "时间线" }).getByRole("listitem")).toHaveText(["读取 周一.md", "写入 周一.md"]);

  await writeFile(hold, "");
  await expect(conversation).toContainText("已经加上了跑步。");
  await expect(column(page).getByRole("img", { name: /助手形象：(完成|待命)/ })).toBeVisible();
  await expect(column(page).getByRole("img", { name: "助手形象：待命" })).toBeVisible({ timeout: 5000 });
  // The note shows what the agent wrote.
  await expect(page.getByLabel("笔记正文")).toContainText("跑步");

  const [run] = await agent.runs();
  expect(run!.argv).toContain("--dangerously-skip-permissions");
  expect(await realpath(run!.cwd)).toBe(await realpath(join(root, "日记")));
  expect(run!.stdin).toContain("帮我补充计划");
  expect(run!.stdin).toContain("- 周一.md");

  // The conversation is kept with the app, never in the library.
  const kept = join(scratch, "profile", "conversations");
  const [file] = await readdir(kept);
  expect(JSON.parse(await readFile(join(kept, file!), "utf8"))).toMatchObject({ agent: "claude", folder: "日记", session: "s-1" });
  expect(await readdir(join(root, "日记"))).toEqual(["周一.md"]);
});

test("a chosen folder is the working directory; the open note can be taken off, others @-mentioned; the directory stays until a new conversation", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/周一.md": "# 周一\n", "读书/书单.md": "# 书单\n", "随记.md": "随记\n" });
  const agent = await installFakeAgent(join(scratch, "agents"), "claude", { session: "s-2", steps: [{ say: "好的。" }] });
  const { page } = await launchWith(scratch, root);
  await openNote(page, "日记", "周一");
  // Choosing a folder afterwards makes it the working directory; the open note is still attached.
  await page.getByRole("treeitem", { name: "读书" }).click();
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(column(page).getByRole("button", { name: "工作目录：读书" })).toBeVisible();
  const attached = column(page).getByRole("list", { name: "附带的笔记" });
  await expect(attached.getByRole("listitem")).toHaveText(["周一"]);
  await attached.getByRole("button", { name: "不附上 周一" }).click();
  await expect(attached).toHaveCount(0);

  // @ mentions another note.
  await input(page).fill("比较一下 @随");
  const mentions = column(page).getByRole("listbox", { name: "提及笔记" });
  await expect(mentions.getByRole("option")).toHaveText(["随记"]);
  await input(page).press("Enter");
  await expect(mentions).toHaveCount(0);
  await expect(attached.getByRole("listitem")).toHaveText(["随记"]);
  await expect(input(page)).toHaveValue("比较一下 ");
  await input(page).press("Enter");
  const conversation = column(page).getByRole("log", { name: "对话" });
  await expect(conversation).toContainText("好的。");

  // Browsing elsewhere does not move the conversation; the next turn continues it.
  await page.getByRole("treeitem", { name: "日记" }).click();
  await expect(column(page).getByRole("button", { name: "工作目录：读书" })).toBeVisible();
  await input(page).fill("继续");
  await input(page).press("Enter");
  await expect(conversation.getByText("好的。")).toHaveCount(2);

  // A new conversation starts where the user is now.
  await column(page).getByRole("button", { name: "新对话" }).click();
  await expect(conversation).toHaveCount(0);
  await expect(column(page).getByRole("button", { name: "工作目录：日记" })).toBeVisible();

  const [first, second] = await agent.runs();
  expect(await realpath(first!.cwd)).toBe(await realpath(join(root, "读书")));
  expect(first!.stdin).toContain("../随记.md");
  expect(first!.stdin).not.toContain("周一");
  expect(await realpath(second!.cwd)).toBe(await realpath(join(root, "读书")));
  expect(second!.argv).toEqual(expect.arrayContaining(["--resume", "s-2"]));
});

test("a turn is undone from 操作记录 in a library with no spaces, reached from the reply or the menu", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记\n" });
  await installFakeAgent(join(scratch, "agents"), "claude", {
    steps: [{ tool: "Write", input: { file_path: join(root, "随记.md") }, write: { path: "随记.md", text: "随记\n\n助手写的\n" } }, { say: "写好了。" }],
  });
  const { app, page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await input(page).fill("写点东西");
  await input(page).press("Enter");
  const conversation = column(page).getByRole("log", { name: "对话" });
  await expect(conversation).toContainText("改动了 1 个文件");
  await expect.poll(() => readFile(join(root, "随记.md"), "utf8")).toBe("随记\n\n助手写的\n");

  // From the menu: the log lists the turn.
  await app.evaluate(({ Menu }) => Menu.getApplicationMenu()!.getMenuItemById("operation-log")!.click());
  const log = page.getByRole("dialog", { name: "操作记录" });
  await expect(log.getByRole("listitem")).toHaveCount(1);
  await expect(log.getByRole("listitem")).toContainText("助手一轮：改动 1 个文件");
  await log.getByRole("button", { name: "关闭" }).click();
  await expect(log).toBeHidden();

  // From the reply, once kept (ticket 29's card): undone there.
  await conversation.getByRole("button", { name: "全部保留" }).click();
  await conversation.getByRole("button", { name: "在操作记录中撤销" }).click();
  await log.getByRole("listitem").getByRole("button", { name: "撤销" }).click();
  await expect(log.getByRole("listitem")).toContainText("已撤销");
  await expect.poll(() => readFile(join(root, "随记.md"), "utf8")).toBe("随记\n");
});

test("an agent that fails shows why and the figure turns to 出错", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记\n" });
  await installFakeAgent(join(scratch, "agents"), "claude", { steps: [{ say: "开始" }, { fail: "额度已用完" }] });
  const { page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await input(page).fill("写点东西");
  await input(page).press("Enter");
  await expect(column(page).getByRole("log", { name: "对话" }).getByRole("alert")).toHaveText("额度已用完");
  await expect(column(page).getByRole("img", { name: "助手形象：出错" })).toBeVisible();
  // The card's toggle shows it too, once the column is shut.
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(page.getByRole("button", { name: "打开助手栏" }).getByRole("img", { name: "助手形象：出错" })).toBeVisible();
});
