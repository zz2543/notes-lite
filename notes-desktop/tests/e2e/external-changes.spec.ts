import { mkdir, rename, rm, utimes, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

// Changes made by other programs — a sync tool, another editor, an agent — while the app is open.

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
