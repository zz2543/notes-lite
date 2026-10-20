import type { Page } from "@playwright/test";
import { expect, launchWith, library, test } from "./fixtures";

// 单栏导航 and 双栏导航, chosen in 设置 › 通用.

async function chooseNavigation(page: Page, mode: "单栏" | "双栏") {
  await page.keyboard.press("ControlOrMeta+Comma");
  const panel = page.getByRole("dialog", { name: "设置" });
  await panel.getByRole("radiogroup", { name: "导航模式" }).getByRole("radio", { name: mode }).click();
  await page.keyboard.press("Escape");
  await expect(panel).toBeHidden();
}

const sidePill = '[role="tree"] [data-testid="selection-pill"]';

test("单栏导航 shows folders and notes in one tree: subfolders first, the open note on the selection pill", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "日记/周一.md": "# 周一",
    "日记/旧的/去年.md": "# 去年",
    "随记.md": "随记",
  });
  const { app, page } = await launchWith(scratch, root);
  const list = page.getByRole("list", { name: "当前目录内容" });
  await expect(list).toBeVisible();

  await chooseNavigation(page, "单栏");
  // The list column goes; the tree alone browses the library.
  await expect(list).toHaveCount(0);
  const tree = page.getByRole("tree", { name: "文件夹与笔记" });
  await expect(tree.getByRole("treeitem")).toHaveText(["笔记库", "日记", "随记"]);

  await tree.getByRole("treeitem", { name: "日记" }).click();
  await expect(tree.getByRole("treeitem")).toHaveText(["笔记库", "日记", "旧的", "周一", "随记"]);
  await expect(tree.getByRole("treeitem", { name: "周一" })).toHaveAttribute("aria-level", "3");

  await tree.getByRole("treeitem", { name: "周一" }).click();
  await expect(page.getByLabel("笔记正文")).toContainText("周一");
  const open = tree.getByRole("treeitem", { name: "周一" });
  await expect(open).toHaveAttribute("aria-selected", "true");
  await expect(page.locator(sidePill)).toHaveCount(1);
  await expect(open.getByTestId("selection-pill")).toHaveCount(1);
  await app.close();
});
