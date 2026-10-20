import type { Page } from "@playwright/test";
import { expect, launchWith, library, test } from "./fixtures";

// 专注模式 (spec.md, ui-motion-spec.md): only the note's title and body, the card filling the window.

async function openNote(page: Page, title: string) {
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(page.getByLabel("笔记正文")).toBeFocused();
}

const focusShortcut = "ControlOrMeta+Shift+KeyF";

test("⌘⇧F leaves only the note's title and body; Esc brings everything back", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "# 随记\n\n雨后" });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "随记");
  const side = page.getByRole("tree", { name: "文件夹" });
  const list = page.getByRole("list", { name: "当前目录内容" });
  const sourceTool = page.getByRole("button", { name: "Markdown 源码" });
  const saveState = page.getByRole("status", { name: "保存状态" });

  await page.keyboard.press(focusShortcut);
  await expect(side).toBeHidden();
  await expect(list).toBeHidden();
  await expect(sourceTool).toBeHidden();
  await expect(saveState).toBeHidden();
  await expect(page.getByLabel("笔记正文")).toContainText("雨后");
  await expect(page.getByRole("button", { name: "退出专注" })).toBeVisible();

  await page.keyboard.press("Escape");
  await expect(side).toBeVisible();
  await expect(list).toBeVisible();
  await expect(sourceTool).toBeVisible();
  await expect(saveState).toBeVisible();
  await expect(page.getByRole("button", { name: "退出专注" })).toHaveCount(0);
  await app.close();
});
