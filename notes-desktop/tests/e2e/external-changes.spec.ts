import type { Page } from "@playwright/test";
import { mkdir, readFile, rename, rm, utimes, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

// Changes made by other programs — a sync tool, another editor, an agent — while the app is open.

const saveState = (page: Page) => page.getByRole("status", { name: "保存状态" });

async function openNote(page: Page, folder: string, title: string) {
  await page.getByRole("treeitem", { name: folder }).click();
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(page.getByLabel("笔记正文")).toBeFocused();
}

test("notes and folders added, edited, moved or deleted elsewhere show up in the tree and list", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n", "日记/读书.md": "# 读书\n" });
  const lastWeek = new Date(Date.now() - 7 * 24 * 3600 * 1000);
  await utimes(join(root, "日记/散步.md"), lastWeek, lastWeek);
  const { app, page } = await launchWith(scratch, root);
  const list = page.getByRole("list", { name: "当前目录内容" }).getByRole("button");
  await page.getByRole("treeitem", { name: "日记" }).click();
  await expect(list).toHaveText(["读书", "散步"]);

  await writeFile(join(root, "日记/早餐.md"), "# 早餐\n");
  await expect(list).toHaveText(["早餐", "读书", "散步"]);

  // Edited elsewhere: newest first.
  await writeFile(join(root, "日记/散步.md"), "# 散步\n\n雨后\n");
  await expect(list).toHaveText(["散步", "早餐", "读书"]);

  await rm(join(root, "日记/早餐.md"));
  await expect(list).toHaveText(["散步", "读书"]);

  await mkdir(join(root, "学习"));
  await rename(join(root, "日记/读书.md"), join(root, "学习/读书.md"));
  await expect(page.getByRole("treeitem", { name: "学习" })).toBeVisible();
  await expect(list).toHaveText(["散步"]);
  await page.getByRole("treeitem", { name: "学习" }).click();
  await expect(list).toHaveText(["读书"]);

  // The open folder deleted elsewhere: the list falls back to the nearest folder still there.
  await rm(join(root, "学习"), { recursive: true });
  await expect(page.getByRole("treeitem", { name: "学习" })).toHaveCount(0);
  await expect(page.getByRole("treeitem", { name: "笔记库" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByRole("heading", { name: "笔记库" })).toBeVisible();
  await app.close();
});

test("an open note with nothing unsaved follows the disk, and is let go when deleted elsewhere", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n", "日记/读书.md": "# 读书\n" });
  const walk = join(root, "日记/散步.md");
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "日记", "散步");
  const editor = page.getByLabel("笔记正文");

  await writeFile(walk, "# 散步\n\n同步来的一段\n");
  await expect(editor).toContainText("同步来的一段");
  await expect(editor).toBeFocused();

  // Typing goes on from the version now on disk, with nothing to resolve.
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("雨后");
  await expect(saveState(page)).toHaveText("已保存");
  expect(await readFile(walk, "utf8")).toBe("# 散步\n\n同步来的一段\n雨后");

  await rm(walk);
  await expect(page.getByRole("alert")).toContainText("找不到“散步”，它可能已在别处移动或删除。");
  await expect(page.getByText("选择一篇笔记")).toBeVisible();
  await expect(page.getByRole("list", { name: "当前目录内容" }).getByRole("button")).toHaveText(["读书"]);
  await app.close();
});
