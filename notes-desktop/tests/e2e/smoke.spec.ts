import { rm } from "node:fs/promises";
import { answerFolderPicker, expect, launch, library, test } from "./fixtures";

test("first launch opens a chosen library and browses it", async ({ scratch }) => {
  const source = "# 雨后的散步\n\n- 小路  \n- 青苔\n";
  const root = await library(scratch, "我的笔记库", {
    "日记/雨后的散步.md": source,
    "日记/2026/十月.md": "# 十月",
    "读书.md": "# 读书",
    ".notes/order.json": "{}",
  });
  const { app, page } = await launch(scratch);

  await answerFolderPicker(app, root);
  await page.getByRole("button", { name: "选择笔记库…" }).click();

  const tree = page.getByRole("tree", { name: "文件夹" });
  await expect(tree.getByRole("treeitem", { name: "我的笔记库" })).toHaveAttribute("aria-selected", "true");
  await expect(tree.getByRole("treeitem")).toHaveText(["我的笔记库", "日记"]);
  const contents = page.getByRole("list", { name: "当前目录内容" });
  await expect(contents.getByRole("button")).toHaveText(["日记", "读书"]);

  const diary = tree.getByRole("treeitem", { name: "日记" });
  await diary.click();
  await expect(contents.getByRole("button")).toHaveText(["2026", "雨后的散步"]);
  await expect(tree.getByRole("treeitem")).toHaveText(["我的笔记库", "日记", "2026"]);
  // Clicking the selected, open folder folds it; once more unfolds it.
  await diary.click();
  await expect(tree.getByRole("treeitem")).toHaveText(["我的笔记库", "日记"]);
  await expect(diary).toHaveAttribute("aria-selected", "true");
  await diary.click();
  await expect(tree.getByRole("treeitem")).toHaveText(["我的笔记库", "日记", "2026"]);

  await contents.getByRole("button", { name: "雨后的散步" }).click();
  await expect(page.getByLabel("笔记正文").locator(".cm-line")).toHaveText(source.split("\n"));

  await app.close();
});

test("remembers the library across launches, switches, and explains when it is gone", async ({ scratch }) => {
  const first = await library(scratch, "工作", { "周报.md": "# 周报" });
  const second = await library(scratch, "生活", { "菜谱.md": "# 菜谱" });

  let { app, page } = await launch(scratch);
  await answerFolderPicker(app, first);
  await page.getByRole("button", { name: "选择笔记库…" }).click();
  await expect(page.getByRole("treeitem", { name: "工作" })).toBeVisible();
  await app.close();

  ({ app, page } = await launch(scratch));
  await expect(page.getByRole("treeitem", { name: "工作" })).toBeVisible();
  await expect(page.getByRole("button", { name: "周报" })).toBeVisible();

  await answerFolderPicker(app, second);
  await page.getByRole("button", { name: "切换笔记库" }).click();
  await expect(page.getByRole("treeitem", { name: "生活" })).toBeVisible();
  await expect(page.getByRole("button", { name: "菜谱" })).toBeVisible();
  await app.close();

  ({ app, page } = await launch(scratch));
  await expect(page.getByRole("treeitem", { name: "生活" })).toBeVisible();
  await app.close();

  await rm(second, { recursive: true });
  ({ app, page } = await launch(scratch));
  await expect(page.getByRole("status")).toContainText(`找不到上次的笔记库“${second}”`);
  await expect(page.getByRole("button", { name: "选择笔记库…" })).toBeVisible();
  await app.close();
});
