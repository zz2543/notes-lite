import type { ElectronApplication, Page } from "@playwright/test";
import { readdir } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

// 快照 (assistant-spec): the library is snapshotted in the background once the 助手栏 opens, so the
// first turn starts from it; 设置 › 助手 shows the disk they take and clears them on request.

const files = async (folder: string) =>
  (await readdir(folder, { recursive: true, withFileTypes: true }).catch(() => [])).filter((entry) => entry.isFile()).length;

async function openAssistantSettings(page: Page) {
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(page.getByRole("complementary", { name: "助手栏" })).toBeVisible();
  await page.keyboard.press("ControlOrMeta+Comma");
  const panel = page.getByRole("dialog", { name: "设置" });
  await panel.getByRole("tab", { name: "助手" }).click();
  return panel.getByRole("group", { name: "快照" });
}

const agreeToNextQuestion = (app: ElectronApplication) =>
  app.evaluate(({ dialog }) => {
    dialog.showMessageBox = (async () => ({ response: 1, checkboxChecked: false })) as typeof dialog.showMessageBox;
  });

test("opening the 助手栏 snapshots the library; 设置 shows the disk it takes and clears it", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "长文.md": "长".repeat(60_000), "日记/今天.md": "# 今天\n" });
  const { app, page } = await launchWith(scratch, root);
  await expect(page.getByRole("treeitem", { name: "日记" })).toBeVisible();
  const store = join(scratch, "profile", "snapshots");
  expect(await files(store), "nothing is snapshotted before the 助手栏 opens").toBe(0);

  const group = await openAssistantSettings(page);
  await expect(group).toContainText("笔记库以外的文件不在快照范围内，无法撤销");
  await expect(group).toContainText("30 天");
  const usage = group.getByLabel("快照占用");
  await expect(usage).toHaveText(/^\d+(\.\d)? KB$/);
  expect(await files(store)).toBeGreaterThan(0);
  await expect(group, "attachments are kept").not.toContainText("只记录");

  await agreeToNextQuestion(app);
  await group.getByRole("button", { name: "立即清理" }).click();
  await expect(usage).toHaveText("没有快照");
  expect(await files(store)).toBe(0);
});

test("past the copy limit, 设置 says attachments are only noted", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记", "图.png": "x".repeat(4000) });
  const { page } = await launchWith(scratch, root, { NOTES_DESKTOP_SNAPSHOT_COPY_LIMIT: "1000" });
  await expect(page.getByRole("treeitem", { name: "笔记库" })).toBeVisible();
  const group = await openAssistantSettings(page);
  await expect(group).toContainText("附件只记录大小和修改时间，助手改动的附件无法撤回");
});
