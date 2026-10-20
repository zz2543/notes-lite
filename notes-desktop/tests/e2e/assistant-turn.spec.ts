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
