import type { ElectronApplication, Page } from "@playwright/test";
import { expect, launchWith, library, openSettings, showSide, test } from "./fixtures";

// 空间风格: chosen in 设置 · 空间 (an example, or 自定义), every homepage takes it at once — its
// variables, its page colour, the details of its bars — and the space card's title row with it.

async function spacePage(app: ElectronApplication, name: string): Promise<Page> {
  const find = async () => {
    for (const w of app.windows()) if (w.url().startsWith("notes-space:") && (await w.title().catch(() => "")) === name) return w;
    return null;
  };
  await expect.poll(find).not.toBeNull();
  return (await find())!;
}
const variable = (home: Page, name: string) => home.evaluate((n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), name);

test("a 空间风格 chosen in 设置 restyles the open homepage at once, and 自定义 takes the user's colours", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/今天.md": "今天" });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await page.getByRole("button", { name: "新建示例空间" }).click();
  const home = await spacePage(app, "组件示例");
  await expect(home.locator("space-chart svg").first()).toBeVisible();
  expect(await variable(home, "--space-decor")).toBe("plain");

  const panel = await openSettings(app, page, "空间");
  const choices = panel.getByRole("radiogroup", { name: "空间风格" });
  await expect(choices.getByRole("radio")).toHaveText(["默认", "晴空", "暗夜", "玻璃", "便当", "大地", "活力", "自定义"]);
  await expect(choices.getByRole("radio", { name: "默认" })).toHaveAttribute("aria-checked", "true");

  await choices.getByRole("radio", { name: "暗夜" }).click();
  await expect.poll(() => variable(home, "--space-theme")).toBe("night");
  expect(await variable(home, "--space-decor")).toBe("led");
  expect(await home.evaluate(() => getComputedStyle(document.documentElement).backgroundColor)).toBe("rgb(15, 15, 17)");
  // The title row over it takes the page's colour.
  await expect.poll(() => page.locator('.card[data-kind="space"]').evaluate((e) => getComputedStyle(e).backgroundColor)).toBe("rgb(15, 15, 17)");
  // 分段: the bars are drawn again, in segments.
  await expect(home.locator('space-chart[type="bar"]').first().locator("g[mask]")).toHaveCount(1);

  await choices.getByRole("radio", { name: "大地" }).click();
  await expect.poll(() => variable(home, "--space-decor")).toBe("pebble");
  expect(await variable(home, "--space-button-radius")).toBe("999px");

  await choices.getByRole("radio", { name: "自定义" }).click();
  await expect(panel.getByRole("group", { name: "自定义" })).toBeVisible();
  await panel.getByRole("radiogroup", { name: "起点" }).getByRole("radio", { name: "便当" }).click();
  await expect.poll(() => variable(home, "--space-theme")).toBe("custom");
  expect(await variable(home, "--space-decor")).toBe("bento");
  await panel.getByLabel("背景", { exact: true }).fill("#123456");
  await expect.poll(() => home.evaluate(() => getComputedStyle(document.documentElement).backgroundColor)).toBe("rgb(18, 52, 86)");
  await panel.getByRole("radiogroup", { name: "细节" }).getByRole("radio", { name: "胶囊" }).click();
  await expect.poll(() => variable(home, "--space-decor")).toBe("capsule");
  await expect(home.locator('space-chart[type="bar"]').first().locator("rect.bar").first()).toHaveAttribute("rx", /^(?!0$)/);

  await choices.getByRole("radio", { name: "默认" }).click();
  await expect.poll(() => variable(home, "--space-decor")).toBe("plain");
  await app.close();
});
