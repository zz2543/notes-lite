import { expect, launch, launchWith, library, test } from "./fixtures";

test("⌘, / Ctrl+, opens the settings panel and Esc closes it", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const { app, page } = await launchWith(scratch, root);

  await page.keyboard.press("ControlOrMeta+Comma");
  const panel = page.getByRole("dialog", { name: "设置" });
  await expect(panel).toBeVisible();
  // 左侧分类，右侧分组：each group has a title and a short description.
  await expect(panel.getByRole("tablist", { name: "设置分类" }).getByRole("tab")).toHaveText(["通用", "笔记列表", "动画"]);
  await expect(panel.getByRole("tab", { name: "通用" })).toHaveAttribute("aria-selected", "true");
  await expect(panel.getByRole("group", { name: "外观" })).toBeVisible();

  await page.keyboard.press("Escape");
  await expect(panel).toBeHidden();
  await app.close();
});
