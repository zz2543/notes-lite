import type { Page } from "@playwright/test";
import { readdir } from "node:fs/promises";
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

// Playwright pins pages to light; with that lifted the page sees what the app tells the system to show.
async function dark(page: Page) {
  await page.emulateMedia({ colorScheme: null });
  return page.evaluate(() => matchMedia("(prefers-color-scheme: dark)").matches);
}

async function openSettings(page: Page, category?: string) {
  await page.keyboard.press("ControlOrMeta+Comma");
  const panel = page.getByRole("dialog", { name: "设置" });
  if (category) await panel.getByRole("tab", { name: category }).click();
  return panel;
}

test("appearance can be fixed to light or dark; it is kept with the app, not in the library", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const before = await readdir(root, { recursive: true });
  const first = await launchWith(scratch, root);

  const appearance = (await openSettings(first.page)).getByRole("radiogroup", { name: "外观" });
  await expect(appearance.getByRole("radio")).toHaveText(["跟随系统", "浅色", "深色"]);
  await expect(appearance.getByRole("radio", { name: "跟随系统" })).toHaveAttribute("aria-checked", "true");
  await appearance.getByRole("radio", { name: "深色" }).click();
  await expect.poll(() => dark(first.page)).toBe(true);
  await appearance.getByRole("radio", { name: "浅色" }).click();
  await expect.poll(() => dark(first.page)).toBe(false);
  await appearance.getByRole("radio", { name: "深色" }).click();
  await first.app.close();

  const again = await launch(scratch);
  await expect.poll(() => dark(again.page)).toBe(true);
  await expect(again.page.getByRole("list", { name: "当前目录内容" })).toBeVisible();
  const reopened = (await openSettings(again.page)).getByRole("radiogroup", { name: "外观" });
  await expect(reopened.getByRole("radio", { name: "深色" })).toHaveAttribute("aria-checked", "true");
  await again.app.close();
  expect(await readdir(root, { recursive: true })).toEqual(before);
});

/** The colour the page uses as its accent (the caret, switches, primary buttons), as rgb(…). */
const accent = (page: Page) =>
  page.evaluate(() => {
    const probe = document.body.appendChild(document.createElement("div"));
    probe.style.color = "var(--accent)";
    const color = getComputedStyle(probe).color;
    probe.remove();
    return color;
  });

test("the accent follows the system as it changes, or is one of the presets", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const { app, page } = await launchWith(scratch, root);
  const accents = (await openSettings(page)).getByRole("radiogroup", { name: "强调色" });
  await expect(accents.getByRole("radio")).toHaveCount(6);
  expect(await accents.getByRole("radio").evaluateAll((swatches) => swatches.map((s) => s.getAttribute("aria-label")))).toEqual([
    "跟随系统",
    "蓝",
    "紫",
    "粉",
    "橙",
    "绿",
  ]);
  await expect(accents.getByRole("radio", { name: "跟随系统" })).toHaveAttribute("aria-checked", "true");

  await accents.getByRole("radio", { name: "紫" }).click();
  await expect.poll(() => accent(page)).toBe("rgb(142, 92, 247)");

  await accents.getByRole("radio", { name: "跟随系统" }).click();
  // The system's accent changes while the app runs.
  await app.evaluate(({ systemPreferences }) => {
    systemPreferences.getAccentColor = () => "ff9f0aff";
    systemPreferences.emit("accent-color-changed", {}, "ff9f0aff");
  });
  await expect.poll(() => accent(page)).toBe("rgb(255, 159, 10)");
  await app.close();
});
