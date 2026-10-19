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
