import type { Page } from "@playwright/test";
import { readdir, utimes } from "node:fs/promises";
import { join } from "node:path";
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

test("the panel emerges: it grows into place out of a blur", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const { app, page } = await launchWith(scratch, root);
  type Frame = { t: number; scale: number; blur: number };
  // Every frame of the panel drawn in its first second, with the time it was drawn.
  await page.evaluate(() => {
    const w = window as unknown as { frames: Frame[] };
    w.frames = [];
    const frame = (t: number) => {
      const panel = document.querySelector<HTMLElement>('[role="dialog"][aria-label="设置"]');
      if (panel) {
        const style = getComputedStyle(panel);
        const blur = /blur\(([\d.]+)px\)/.exec(style.filter);
        w.frames.push({ t, scale: new DOMMatrix(style.transform).a, blur: blur ? Number(blur[1]) : 0 });
      }
      if (!w.frames.length || t - w.frames[0]!.t < 1000) requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  });
  await page.keyboard.press("ControlOrMeta+Comma");
  const panel = page.getByRole("dialog", { name: "设置" });
  await expect(panel).toBeVisible();
  // It comes to rest at full size, sharp.
  const settled = () =>
    panel.evaluate((element) => {
      const style = getComputedStyle(element);
      const blur = /blur\(([\d.]+)px\)/.exec(style.filter);
      return { scale: new DOMMatrix(style.transform).a, blur: blur ? Number(blur[1]) : 0 };
    });
  await expect.poll(settled).toEqual({ scale: 1, blur: 0 });
  const filmed = () => page.evaluate(() => (window as unknown as { frames: Frame[] }).frames);
  await expect.poll(async () => ((f) => f.at(-1)!.t - f[0]!.t)(await filmed())).toBeGreaterThanOrEqual(1000);
  const frames = await filmed();
  // Its first frame is small and blurred: it grows out of a blur rather than appearing.
  expect(frames[0]!.scale).toBeLessThan(0.95);
  expect(frames[0]!.blur).toBeGreaterThan(0);
  // 浮现 at 强 overshoots a little before settling (its spring is checked in tests/core/motion.test.ts). The
  // overshoot lasts a fraction of the spring, so it is only asked of a runner that drew frames enough to
  // show it; a slow one may jump from the first frame straight past it.
  const during = frames.filter((f) => f.t - frames[0]!.t < 550).length;
  if (during >= 15) expect(Math.max(...frames.map((f) => f.scale))).toBeGreaterThan(1);
  else test.info().annotations.push({ type: "few frames", description: `${during} frames drawn in the panel's first 550 ms` });
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

  const detail = (await openSettings(page, "笔记列表")).getByRole("radiogroup", { name: "详细程度" });
  await expect(detail.getByRole("radio", { name: "详细" })).toHaveAttribute("aria-checked", "true");
  await detail.getByRole("radio", { name: "标准" }).click();
  await page.keyboard.press("Escape");
  await expect(row).toContainText("2024年3月1日");
  await expect(row).not.toContainText("青苔");

  await page.getByRole("button", { name: "列表选项" }).click();
  await expect(page.getByRole("menu").getByRole("menuitemradio", { name: "标准" })).toHaveAttribute("aria-checked", "true");
  await app.close();
});

/** The spring CSS transitions use for 浮现, as `<duration> linear(…)`. */
const emergeSpring = (page: Page) => page.evaluate(() => document.documentElement.style.getPropertyValue("--spring-emerge"));

test("motion intensity is 强 by default and 轻 or 标准 calm every spring at once", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const first = await launchWith(scratch, root);
  const strong = await emergeSpring(first.page);
  const intensity = (await openSettings(first.page, "动画")).getByRole("radiogroup", { name: "动效强度" });
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
