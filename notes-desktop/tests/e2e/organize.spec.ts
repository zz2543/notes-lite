import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

const tree = (page: Page) => page.getByRole("tree", { name: "文件夹" });
const contents = (page: Page) => page.getByRole("list", { name: "当前目录内容" });

test("⌘N and a folder row's new-note icon create a note there, ready to type", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步" });
  const { app, page } = await launchWith(scratch, root);

  await tree(page).getByRole("treeitem", { name: "日记" }).click();
  await page.keyboard.press("ControlOrMeta+KeyN");
  await expect(contents(page).getByRole("button", { name: "未命名笔记" })).toHaveAttribute("aria-current", "true");
  await expect(page.getByLabel("笔记正文")).toBeFocused();
  await page.keyboard.type("雨后");
  await expect.poll(() => readFile(join(root, "日记/未命名笔记.md"), "utf8")).toBe("# 未命名笔记\n\n雨后");

  const rootRow = tree(page).getByRole("treeitem", { name: "笔记库" });
  await rootRow.hover();
  await rootRow.getByRole("button", { name: "在“笔记库”中新建笔记" }).click();
  await expect(rootRow).toHaveAttribute("aria-selected", "true");
  await expect(contents(page).getByRole("button")).toHaveText(["日记", "未命名笔记"]);
  await expect(page.getByLabel("笔记正文")).toBeFocused();
  expect(await readFile(join(root, "未命名笔记.md"), "utf8")).toBe("# 未命名笔记\n\n");

  // File > 新建笔记, chosen from the menu: the name taken, it is numbered.
  await app.evaluate(({ Menu }) => Menu.getApplicationMenu()?.getMenuItemById("new-note")?.click());
  await expect(contents(page).getByRole("button", { name: "未命名笔记 2" })).toHaveAttribute("aria-current", "true");

  await app.close();
});

test("renaming and moving notes and folders keeps links working; a taken name is refused", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "日记/散步.md": "# 散步\n",
    "日记/读书.md": "# 读书\n",
    "入口.md": "见 [[日记/散步]]\n\n`[[日记/散步]]`\n",
    "归档/旧.md": "# 旧\n",
  });
  const note = (path: string) => readFile(join(root, path), "utf8");
  const { app, page } = await launchWith(scratch, root);
  await tree(page).getByRole("treeitem", { name: "日记" }).click();
  await contents(page).getByRole("button", { name: "散步" }).click();

  // A taken name: said in the dialog, which stays open, and nothing is overwritten.
  await contents(page).getByRole("button", { name: "散步" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "重命名…" }).click();
  const rename = page.getByRole("dialog", { name: "重命名笔记" });
  await expect(rename.getByLabel("名称")).toHaveValue("散步");
  await rename.getByLabel("名称").fill("读书");
  await rename.getByRole("button", { name: "重命名" }).click();
  await expect(rename.getByRole("alert")).toHaveText("已经存在“读书”，请换一个名称。");
  expect(await note("日记/读书.md")).toBe("# 读书\n");

  await rename.getByLabel("名称").fill("雨后散步");
  await page.keyboard.press("Enter");
  await expect(rename).toBeHidden();
  await expect(contents(page).getByRole("button", { name: "雨后散步" })).toHaveAttribute("aria-current", "true");
  await expect(contents(page).getByRole("button")).toHaveCount(2);
  expect(await note("入口.md")).toBe("见 [[日记/雨后散步]]\n\n`[[日记/散步]]`\n");

  // The open note moves to 归档, and the view goes with it.
  await contents(page).getByRole("button", { name: "雨后散步" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "移动到…" }).click();
  const move = page.getByRole("dialog", { name: "移动“雨后散步”" });
  await expect(move.getByRole("option", { name: "日记", exact: true })).toBeDisabled();
  await move.getByRole("option", { name: "归档", exact: true }).click();
  await move.getByRole("button", { name: "移动" }).click();
  await expect(move).toBeHidden();
  await expect(tree(page).getByRole("treeitem", { name: "归档" })).toHaveAttribute("aria-selected", "true");
  await expect(contents(page).getByRole("button", { name: "雨后散步" })).toHaveAttribute("aria-current", "true");
  expect(await note("归档/雨后散步.md")).toBe("# 散步\n");
  expect(await note("入口.md")).toBe("见 [[归档/雨后散步]]\n\n`[[日记/散步]]`\n");

  // Renaming the folder: the tree, the open note and the links follow.
  await tree(page).getByRole("treeitem", { name: "归档" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "重命名…" }).click();
  await page.getByRole("dialog", { name: "重命名文件夹" }).getByLabel("名称").fill("存档");
  await page.keyboard.press("Enter");
  await expect(tree(page).getByRole("treeitem", { name: "存档" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByRole("article")).toContainText("存档 / 雨后散步");
  expect(await note("入口.md")).toBe("见 [[存档/雨后散步]]\n\n`[[日记/散步]]`\n");

  // The open note is linked from one being renamed: it shows what is now on disk, and edits save.
  await tree(page).getByRole("treeitem", { name: "笔记库" }).click();
  await contents(page).getByRole("button", { name: "入口" }).click();
  await contents(page).getByRole("button", { name: "存档" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "重命名…" }).click();
  await page.getByRole("dialog", { name: "重命名文件夹" }).getByLabel("名称").fill("归档");
  await page.keyboard.press("Enter");
  await expect(page.getByLabel("笔记正文")).toContainText("见 [[归档/雨后散步]]");
  await page.getByLabel("笔记正文").click();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("完");
  await expect(page.getByRole("status", { name: "保存状态" })).toHaveText("已保存");
  expect(await note("入口.md")).toBe("见 [[归档/雨后散步]]\n\n`[[日记/散步]]`\n完");

  await app.close();
});
