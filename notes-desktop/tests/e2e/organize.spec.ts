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
  await expect(page.getByLabel("笔记标题")).toHaveAttribute("title", "存档 / 雨后散步.md");
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

test("the title above a note's text is its file name; editing it renames the note, and a taken or empty name is refused", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "雨后", "日记/读书.md": "书单", "入口.md": "[[日记/散步]]" });
  const { app, page } = await launchWith(scratch, root);
  await tree(page).getByRole("treeitem", { name: "日记" }).click();
  await contents(page).getByRole("button", { name: "散步" }).click();
  const title = page.getByLabel("笔记标题");
  await expect(title).toHaveValue("散步");
  // The card's head no longer shows the path; the title's tooltip says where the note lives.
  await expect(title).toHaveAttribute("title", "日记 / 散步.md");

  await title.fill("雨后散步");
  await title.press("Enter");
  await expect(contents(page).getByRole("button", { name: "雨后散步" })).toHaveAttribute("aria-current", "true");
  await expect(page.getByLabel("笔记标题")).toHaveValue("雨后散步");
  expect(await readFile(join(root, "日记/雨后散步.md"), "utf8")).toBe("雨后");
  // Links follow, as with 重命名….
  await expect.poll(() => readFile(join(root, "入口.md"), "utf8")).toBe("[[日记/雨后散步]]");

  // A taken name says why and the old one comes back; so does an empty one, on leaving the field.
  await page.getByLabel("笔记标题").fill("读书");
  await page.getByLabel("笔记标题").press("Enter");
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(page.getByLabel("笔记标题")).toHaveValue("雨后散步");
  await page.getByLabel("笔记标题").fill("");
  await page.getByLabel("笔记正文").click();
  await expect(page.getByRole("alert")).toHaveText("标题不能为空。");
  await expect(page.getByLabel("笔记标题")).toHaveValue("雨后散步");
  await expect(contents(page).getByRole("button")).toHaveText(["读书", "雨后散步"]);

  // Esc puts the name back and goes into the text.
  await page.getByLabel("笔记标题").fill("别的");
  await page.getByLabel("笔记标题").press("Escape");
  await expect(page.getByLabel("笔记标题")).toHaveValue("雨后散步");
  await expect(page.getByLabel("笔记正文")).toBeFocused();
  await app.close();
});

test("deleting moves a note or folder to the trash, and the last deletion can be restored", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n雨后\n", "日记/读书.md": "# 读书\n" });
  const exists = (path: string) => readFile(join(root, path), "utf8").then(() => true, () => false);
  const { app, page } = await launchWith(scratch, root);
  // On CI the real system trash is used; locally, a folder stands in so test notes stay out of yours.
  if (!process.env.CI) {
    await app.evaluate(({ shell }, folder) => {
      const fs = process.getBuiltinModule("node:fs");
      const path = process.getBuiltinModule("node:path");
      fs.mkdirSync(folder, { recursive: true });
      shell.trashItem = async (item) => fs.renameSync(item, path.join(folder, path.basename(item)));
    }, join(scratch, "废纸篓"));
  }

  await tree(page).getByRole("treeitem", { name: "日记" }).click();
  await contents(page).getByRole("button", { name: "散步" }).click();
  await contents(page).getByRole("button", { name: "散步" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "移到废纸篓" }).click();
  await expect(contents(page).getByRole("button")).toHaveText(["读书"]);
  await expect(page.getByRole("article")).toContainText("选择一篇笔记");
  expect(await exists("日记/散步.md")).toBe(false);

  await page.getByRole("button", { name: "恢复上次删除" }).click();
  await expect(contents(page).getByRole("button", { name: "散步" })).toHaveAttribute("aria-current", "true");
  await expect(page.getByLabel("笔记正文")).toHaveText("# 散步\n雨后\n", { useInnerText: true });
  expect(await readFile(join(root, "日记/散步.md"), "utf8")).toBe("# 散步\n雨后\n");
  await expect(page.getByRole("button", { name: "恢复上次删除" })).toBeHidden();

  // A whole folder, while it is selected and one of its notes is open.
  await tree(page).getByRole("treeitem", { name: "日记" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "移到废纸篓" }).click();
  await expect(tree(page).getByRole("treeitem")).toHaveText(["笔记库"]);
  await expect(tree(page).getByRole("treeitem", { name: "笔记库" })).toHaveAttribute("aria-selected", "true");
  expect(await exists("日记/读书.md")).toBe(false);
  await page.getByRole("button", { name: "恢复上次删除" }).click();
  await expect(tree(page).getByRole("treeitem", { name: "日记" })).toHaveAttribute("aria-selected", "true");
  await expect(contents(page).getByRole("button")).toHaveCount(2);
  expect(await exists("日记/读书.md")).toBe(true);

  await app.close();
});
