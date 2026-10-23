import type { Page } from "@playwright/test";
import { readdir, utimes } from "node:fs/promises";
import { join } from "node:path";
import { closeSettings, expect, launch, launchWith, library, openSettings, test } from "./fixtures";

test("⌘, / Ctrl+, opens the settings window and Esc closes it", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const { app, page } = await launchWith(scratch, root);

  const panel = await openSettings(app, page);
  // 左侧分类，右侧分组：each group has a title and a short description.
  await expect(panel.getByRole("tablist", { name: "设置分类" }).getByRole("tab")).toHaveText(["通用", "排版", "笔记列表", "动画", "助手"]);
  await expect(panel.getByRole("tab", { name: "通用" })).toHaveAttribute("aria-selected", "true");
  await expect(panel.getByRole("group", { name: "外观" })).toBeVisible();

  await closeSettings(app, panel);
  // The main window stays as it was.
  await expect(page.getByRole("list", { name: "当前目录内容" })).toBeVisible();
  await app.close();
});

test("设置 opens as its own window, movable and closable; asked again it comes to the front, still one", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const { app, page } = await launchWith(scratch, root);
  await openSettings(app, page);
  const windows = () =>
    app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows().map((w) => ({ title: w.getTitle(), movable: w.isMovable(), closable: w.isClosable(), modal: w.isModal() })),
    );
  await expect.poll(async () => (await windows()).length).toBe(2);
  const settings = (await windows()).find((w) => w.title === "设置");
  expect(settings).toEqual({ title: "设置", movable: true, closable: true, modal: false });
  // Not attached to the main window: it moves on its own.
  const moved = await app.evaluate(({ BrowserWindow }) => {
    const win = BrowserWindow.getAllWindows().find((w) => w.getTitle() === "设置")!;
    win.setPosition(40, 60);
    return { parent: win.getParentWindow(), at: win.getPosition() };
  });
  expect(moved).toEqual({ parent: null, at: [40, 60] });

  // Asked again from the main window, the one 设置 window is focused rather than a second opened.
  await page.bringToFront();
  await page.keyboard.press("ControlOrMeta+Comma");
  await expect.poll(() => app.evaluate(({ BrowserWindow }) => BrowserWindow.getFocusedWindow()?.getTitle())).toBe("设置");
  expect((await windows()).length).toBe(2);

  // Closed like any window, it leaves the main one alone.
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().find((w) => w.getTitle() === "设置")!.close());
  await expect.poll(async () => (await windows()).length).toBe(1);
  await expect(page.getByRole("list", { name: "当前目录内容" })).toBeVisible();
  await app.close();
});

// Playwright pins pages to light; with that lifted the page sees what the app tells the system to show.
async function dark(page: Page) {
  await page.emulateMedia({ colorScheme: null });
  return page.evaluate(() => matchMedia("(prefers-color-scheme: dark)").matches);
}

test("appearance can be fixed to light or dark; it is kept with the app, not in the library", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const before = await readdir(root, { recursive: true });
  const first = await launchWith(scratch, root);

  const appearance = (await openSettings(first.app, first.page)).getByRole("radiogroup", { name: "外观" });
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
  const reopened = (await openSettings(again.app, again.page)).getByRole("radiogroup", { name: "外观" });
  await expect(reopened.getByRole("radio", { name: "深色" })).toHaveAttribute("aria-checked", "true");
  await again.app.close();
  expect(await readdir(root, { recursive: true })).toEqual(before);
});

test("the list shows 简洁, 标准 or 详细 rows, chosen in settings or the list's “…” menu alike", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "雨后.md": "# 雨后\n\n小路上**青苔**很滑。" });
  await utimes(join(root, "雨后.md"), new Date(2024, 2, 1, 9, 30), new Date(2024, 2, 1, 9, 30));
  const { app, page } = await launchWith(scratch, root);
  const row = page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: /雨后/ });
  // 简洁 by default: the title alone.
  await expect(row).toHaveText("雨后");

  await page.getByRole("button", { name: "列表选项" }).click();
  const menu = page.getByRole("menu");
  await expect(menu.getByRole("menuitemradio")).toHaveText(["简洁", "标准", "详细"]);
  await expect(menu.getByRole("menuitemradio", { name: "简洁" })).toHaveAttribute("aria-checked", "true");
  await menu.getByRole("menuitemradio", { name: "详细" }).click();
  await expect(menu).toBeHidden();
  await expect(row).toContainText("小路上青苔很滑。");
  await expect(row).toContainText("2024年3月1日");

  const detail = (await openSettings(app, page, "笔记列表")).getByRole("radiogroup", { name: "详细程度" });
  await expect(detail.getByRole("radio", { name: "详细" })).toHaveAttribute("aria-checked", "true");
  await detail.getByRole("radio", { name: "标准" }).click();
  await closeSettings(app, detail);
  await expect(row).toContainText("2024年3月1日");
  await expect(row).not.toContainText("青苔");

  await page.getByRole("button", { name: "列表选项" }).click();
  await expect(page.getByRole("menu").getByRole("menuitemradio", { name: "标准" })).toHaveAttribute("aria-checked", "true");
  await page.keyboard.press("Escape");

  // Chosen in the main window while 设置 is open, 设置 shows it at once.
  const open = (await openSettings(app, page, "笔记列表")).getByRole("radiogroup", { name: "详细程度" });
  await page.getByRole("button", { name: "列表选项" }).click();
  await page.getByRole("menu").getByRole("menuitemradio", { name: "简洁" }).click();
  await expect(open.getByRole("radio", { name: "简洁" })).toHaveAttribute("aria-checked", "true");
  await expect(row).toHaveText("雨后");
  await app.close();
});

/** The spring CSS transitions use for 浮现, as `<duration> linear(…)`. */
const emergeSpring = (page: Page) => page.evaluate(() => document.documentElement.style.getPropertyValue("--spring-emerge"));

test("motion intensity is 强 by default and 轻 or 标准 calm every spring at once", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const first = await launchWith(scratch, root);
  const strong = await emergeSpring(first.page);
  const intensity = (await openSettings(first.app, first.page, "动画")).getByRole("radiogroup", { name: "动效强度" });
  await expect(intensity.getByRole("radio")).toHaveText(["轻", "标准", "强"]);
  await expect(intensity.getByRole("radio", { name: "强" })).toHaveAttribute("aria-checked", "true");

  await intensity.getByRole("radio", { name: "轻" }).click();
  await expect.poll(() => emergeSpring(first.page)).not.toBe(strong);
  const light = await emergeSpring(first.page);
  // 浮现 at 轻 settles sooner: 0.36s against 0.55s.
  expect(parseFloat(light)).toBeLessThan(parseFloat(strong));
  await first.app.close();

  const again = await launch(scratch);
  await expect.poll(() => emergeSpring(again.page)).toBe(light);
  await again.app.close();
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
  const accents = (await openSettings(app, page)).getByRole("radiogroup", { name: "强调色" });
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
