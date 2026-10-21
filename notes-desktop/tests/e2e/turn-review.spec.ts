import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { installFakeAgent } from "../support/fakeAgent";
import { expect, launchWith, library, test } from "./fixtures";

// 写入审查 (assistant-spec, ticket 29) with a fake Claude Code: after a turn that changed anything, one
// card lists it; 全部保留 is the default, a note can be opened and taken back alone, or the whole turn.

const column = (page: Page) => page.getByRole("complementary", { name: "助手栏" });
const conversation = (page: Page) => column(page).getByRole("log", { name: "对话" });
const card = (page: Page) => conversation(page).getByRole("region", { name: "本轮改动" });
const read = (root: string, path: string) => readFile(join(root, path), "utf8").catch(() => null);

async function ask(page: Page, text: string) {
  const input = column(page).getByRole("textbox", { name: "给助手的消息" });
  await input.fill(text);
  await input.press("Enter");
}

/** A turn that adds a line to 随记 and writes a new note. */
async function twoNotes(scratch: string) {
  const root = await library(scratch, "笔记库", { "随记.md": "随记\n" });
  await installFakeAgent(join(scratch, "agents"), "claude", {
    steps: [
      { tool: "Edit", input: { file_path: join(root, "随记.md") }, write: { path: "随记.md", text: "随记\n补一行\n" } },
      { tool: "Write", input: { file_path: join(root, "新.md") }, write: { path: "新.md", text: "# 新\n\n正文\n" } },
      { say: "改好了。" },
    ],
  });
  return root;
}

test("the card lists each note the turn changed with its lines, and 全部保留 keeps them all", async ({ scratch }) => {
  const root = await twoNotes(scratch);
  const { page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await ask(page, "改一改");

  await expect(card(page)).toContainText("本轮改动了 2 个文件");
  const rows = card(page).getByRole("listitem");
  await expect(rows).toHaveCount(2);
  await expect(rows.nth(0)).toContainText("新建新.md+3 −0");
  await expect(rows.nth(1)).toContainText("改写随记.md+1 −0");
  await expect(card(page).getByRole("button", { name: "全部保留" })).toHaveClass(/primary/);

  await card(page).getByRole("button", { name: "全部保留" }).click();
  await expect(card(page)).toBeHidden();
  await expect(conversation(page)).toContainText("已保留本轮改动（2 个文件）。");
  expect(await read(root, "随记.md")).toBe("随记\n补一行\n");
  expect(await read(root, "新.md")).toBe("# 新\n\n正文\n");
});

test("a note opens to its changed lines and is taken back alone; 撤回本轮 takes back the rest", async ({ scratch }) => {
  const root = await twoNotes(scratch);
  const { app, page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await ask(page, "改一改");

  const open = card(page).getByRole("button", { name: "查看 随记.md 的改动" });
  await expect(open).toHaveAttribute("aria-expanded", "false");
  await open.click();
  await expect(open).toHaveAttribute("aria-expanded", "true");
  await expect(card(page).getByLabel("随记.md 的改动", { exact: true })).toHaveText("+ 补一行");

  await card(page).getByRole("button", { name: "撤回 随记.md" }).click();
  await expect(card(page).getByRole("listitem").nth(1)).toContainText("已撤回");
  await expect.poll(() => read(root, "随记.md")).toBe("随记\n");
  expect(await read(root, "新.md")).toBe("# 新\n\n正文\n");

  await card(page).getByRole("button", { name: "撤回本轮" }).click();
  await expect(card(page)).toBeHidden();
  await expect(conversation(page)).toContainText("已撤回本轮改动。");
  await expect.poll(() => read(root, "新.md")).toBeNull();
  // The same as undoing it in 操作记录, which says so.
  await app.evaluate(({ Menu }) => Menu.getApplicationMenu()!.getMenuItemById("operation-log")!.click());
  await expect(page.getByRole("dialog", { name: "操作记录" }).getByRole("listitem")).toContainText("已撤销");
});

test("in 直接保留 mode no card shows, and the turn is still undone from 操作记录", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记\n" });
  await installFakeAgent(join(scratch, "agents"), "claude", {
    steps: [{ tool: "Write", input: { file_path: join(root, "随记.md") }, write: { path: "随记.md", text: "随记\n助手写的\n" } }, { say: "写好了。" }],
  });
  const { page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await page.keyboard.press("ControlOrMeta+Comma");
  const panel = page.getByRole("dialog", { name: "设置" });
  await panel.getByRole("tab", { name: "助手" }).click();
  const review = panel.getByRole("group", { name: "写入审查" }).getByRole("radiogroup", { name: "审查方式" });
  await expect(review.getByRole("radio", { name: "每轮结束后审查" })).toBeChecked();
  await review.getByRole("radio", { name: "直接保留" }).click();
  await expect(review.getByRole("radio", { name: "直接保留" })).toBeChecked();
  await page.keyboard.press("Escape");
  await expect(panel).toBeHidden();

  await ask(page, "写点东西");
  await expect(conversation(page)).toContainText("已保留本轮改动（1 个文件）。");
  await expect(card(page)).toHaveCount(0);
  await expect.poll(() => read(root, "随记.md")).toBe("随记\n助手写的\n");

  await conversation(page).getByRole("button", { name: "在操作记录中撤销" }).click();
  const log = page.getByRole("dialog", { name: "操作记录" });
  await log.getByRole("listitem").getByRole("button", { name: "撤销" }).click();
  await expect(log.getByRole("listitem")).toContainText("已撤销");
  await expect.poll(() => read(root, "随记.md")).toBe("随记\n");
});

test("what the turn wrote outside the library is in the card, marked as not undoable", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记\n" });
  const outside = join(scratch, "库外.md");
  await installFakeAgent(join(scratch, "agents"), "claude", {
    steps: [
      { tool: "Write", input: { file_path: outside }, write: { path: outside, text: "库外\n" } },
      { tool: "Write", input: { file_path: join(root, "随记.md") }, write: { path: "随记.md", text: "随记\n又一行\n" } },
    ],
  });
  const { page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await ask(page, "写到外面");

  const rows = card(page).getByRole("listitem");
  await expect(rows).toHaveCount(2);
  await expect(rows.nth(0)).toContainText("改写随记.md");
  await expect(rows.nth(1)).toContainText("笔记库以外");
  await expect(rows.nth(1)).toContainText("库外.md");
  await expect(rows.nth(1)).toContainText("不可撤销");
  await expect(rows.nth(1).getByRole("button")).toHaveCount(0);

  // Taking back the turn leaves it be.
  await card(page).getByRole("button", { name: "撤回本轮" }).click();
  await expect(conversation(page)).toContainText("已撤回本轮改动。");
  await expect.poll(() => read(root, "随记.md")).toBe("随记\n");
  expect(await readFile(outside, "utf8")).toBe("库外\n");
});
