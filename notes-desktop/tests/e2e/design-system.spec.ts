import type { Locator, Page } from "@playwright/test";
import { expect, launch, launchWith, library, test } from "./fixtures";

const windowColor = (page: Page) => page.evaluate(() => getComputedStyle(document.body).backgroundColor);

/** What the page computes for `property: value`, so a variable and a literal compare as the browser sees them. */
const computed = (page: Page, property: string, value: string) =>
  page.evaluate(
    ({ property, value }) => {
      const probe = document.body.appendChild(document.createElement("div"));
      probe.style.setProperty(property, value);
      const result = getComputedStyle(probe).getPropertyValue(property);
      probe.remove();
      return result;
    },
    { property, value },
  );

interface Frame {
  top: number;
  scale: string;
  filter: string;
}

/** Films the element matching `selector` once per frame while `act` runs and `ms` after it. */
async function film(page: Page, selector: string, act: () => Promise<void>, ms = 900): Promise<Frame[]> {
  await page.evaluate((selector) => {
    const w = window as unknown as { film: Frame[]; filming: boolean };
    w.film = [];
    w.filming = true;
    const frame = () => {
      if (!w.filming) return;
      const element = document.querySelector(selector);
      if (element) {
        const style = getComputedStyle(element);
        w.film.push({ top: element.getBoundingClientRect().top, scale: style.scale, filter: style.filter });
      }
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }, selector);
  await act();
  await page.waitForTimeout(ms);
  return page.evaluate(() => {
    const w = window as unknown as { film: Frame[]; filming: boolean };
    w.filming = false;
    return w.film;
  });
}

const sidePill = '[role="tree"] [data-testid="selection-pill"]';

async function top(locator: Locator): Promise<number> {
  const box = await locator.boundingBox();
  if (!box) throw new Error("not on screen");
  return box.y;
}

test("the selection pill slides to the chosen folder", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "甲/一.md": "一", "乙/二.md": "二", "丙/三.md": "三" });
  const { app, page } = await launchWith(scratch, root);
  const tree = page.getByRole("tree", { name: "文件夹" });
  const from = await top(tree.getByRole("treeitem", { name: "笔记库" }));
  const target = tree.getByRole("treeitem", { name: "丙" });
  const to = await top(target);

  const frames = await film(page, sidePill, () => target.click());
  // It passes through the rows in between instead of jumping, and comes to rest on the chosen row.
  expect(frames.some((f) => f.top > from + 2 && f.top < to - 2)).toBe(true);
  expect(frames.at(-1)?.top).toBeCloseTo(to, 0);
  await app.close();
});

const scaleOf = (frame: Frame | undefined) => (!frame || frame.scale === "none" ? 1 : Number(frame.scale));

test("hover only tints a row; pressing shrinks it with a spring and it springs back", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "散步.md": "# 散步", "读书.md": "# 读书" });
  const { app, page } = await launchWith(scratch, root);
  const item = page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: "读书" });
  const selector = '[aria-label="当前目录内容"] button:hover';

  await item.hover();
  await expect(item).toHaveCSS("background-color", await computed(page, "color", "var(--hover)"));
  await expect(item).toHaveCSS("scale", "none");

  const pressed = await film(page, selector, () => page.mouse.down(), 700);
  // It eases through in-between sizes, not a jump, and holds at 0.97 while pressed.
  expect(pressed.some((f) => scaleOf(f) < 0.995 && scaleOf(f) > 0.975)).toBe(true);
  expect(scaleOf(pressed.at(-1))).toBeCloseTo(0.97, 3);
  const released = await film(page, selector, () => page.mouse.up(), 700);
  expect(released.some((f) => scaleOf(f) > 0.975 && scaleOf(f) < 0.995)).toBe(true);
  expect(scaleOf(released.at(-1))).toBe(1);
  await app.close();
});

// The design system's tables (docs/design-system.md), copied as written: [variable, light, dark].
const colours: [string, string, string][] = [
  ["--side-fg", "#1d1d1f", "#f2f2f4"],
  ["--side-muted", "rgba(29,29,31,.48)", "rgba(242,242,244,.45)"],
  ["--list-bg", "rgba(255,255,255,.52)", "rgba(16,16,20,.38)"],
  ["--list-fg", "#1d1d1f", "#f2f2f4"],
  ["--list-muted", "rgba(29,29,31,.5)", "rgba(242,242,244,.48)"],
  ["--card-bg", "#ffffff", "#1e1e21"],
  ["--card-fg", "#1d1d1f", "#ececef"],
  ["--card-muted", "rgba(29,29,31,.42)", "rgba(236,236,239,.4)"],
  ["--card-path", "color-mix(in srgb, #1d1d1f 62%, transparent)", "color-mix(in srgb, #ececef 62%, transparent)"],
  ["--side-pill", "rgba(255,255,255,.72)", "rgba(255,255,255,.14)"],
  ["--list-pill", "rgba(255,255,255,.85)", "rgba(255,255,255,.16)"],
  ["--hover", "rgba(0,0,0,.045)", "rgba(255,255,255,.06)"],
  ["--line", "rgba(0,0,0,.08)", "rgba(255,255,255,.08)"],
  ["--glass", "rgba(250,250,252,.72)", "rgba(40,40,46,.72)"],
  ["--glass-border", "rgba(255,255,255,.7)", "rgba(255,255,255,.1)"],
  ["--scrim", "rgba(30,30,40,.14)", "rgba(0,0,0,.3)"],
  ["--focus-dim", "rgba(20,20,30,.22)", "rgba(0,0,0,.4)"],
  // The real window is opaque wherever there is no system material, so the fallback is the opaque value.
  ["--win-fallback", "#f2f1f5", "#1e1e22"],
  ["--accent-blue", "#0a84ff", "#0a84ff"],
  ["--accent-purple", "#8e5cf7", "#8e5cf7"],
  ["--accent-pink", "#ff375f", "#ff375f"],
  ["--accent-orange", "#ff9f0a", "#ff9f0a"],
  ["--accent-green", "#30d158", "#30d158"],
];
const shadows: [string, string, string][] = [
  ["--pill-shadow", "0 0 0 .5px rgba(0,0,0,.1), 0 1px 4px rgba(0,0,0,.12)", "0 0 0 .5px rgba(255,255,255,.12), 0 1px 4px rgba(0,0,0,.3)"],
  ["--card-shadow", "0 1px 2px rgba(0,0,0,.06), 0 8px 28px rgba(0,0,0,.08)", "0 0 0 1px rgba(255,255,255,.05), 0 10px 30px rgba(0,0,0,.35)"],
  ["--overlay-shadow", "0 30px 90px rgba(0,0,0,.28), 0 0 0 .5px rgba(0,0,0,.08)", "0 30px 90px rgba(0,0,0,.28), 0 0 0 .5px rgba(0,0,0,.08)"],
];
const sizes: [string, string][] = [
  ["--window-radius", "14px"],
  ["--side-width", "216px"],
  ["--list-width", "276px"],
  ["--single-nav-width", "256px"],
  ["--rail-width", "52px"],
  ["--rail-button", "34px"],
  ["--rail-button-radius", "10px"],
  ["--assistant-width", "340px"],
  ["--assistant-width-narrow", "300px"],
  ["--card-gap", "10px"],
  ["--card-radius", "12px"],
  ["--row-height", "32px"],
  ["--row-padding", "10px"],
  ["--row-radius", "9px"],
  ["--row-indent", "16px"],
  ["--item-radius", "10px"],
  ["--list-head-height", "52px"],
  ["--card-head-height", "46px"],
  ["--card-foot-height", "34px"],
  ["--icon-button", "28px"],
  ["--icon-button-small", "24px"],
  ["--icon-button-radius", "8px"],
  ["--icon-button-small-radius", "7px"],
  ["--segmented-padding", "3px"],
  ["--segmented-radius", "10px"],
  ["--segmented-height", "26px"],
  ["--search-height", "30px"],
  ["--search-radius", "9px"],
  ["--menu-padding", "5px"],
  ["--menu-radius", "12px"],
  ["--menu-item-height", "30px"],
  ["--settings-width", "920px"],
  ["--settings-height", "600px"],
  ["--settings-radius", "20px"],
  ["--settings-nav-width", "190px"],
];

test("the accent follows the system accent colour", async ({ scratch }) => {
  const { app, page } = await launch(scratch);
  const choose = page.getByRole("button", { name: "选择笔记库…" });
  await expect(choose).toBeVisible();
  // RGBA hex, as the system reports it.
  const system = await app.evaluate(({ systemPreferences }) => systemPreferences.getAccentColor());
  const accent = await computed(page, "color", `#${system.slice(0, 6)}`);
  expect(await computed(page, "color", "var(--accent)")).toBe(accent);
  await expect(choose).toHaveCSS("background-color", accent);
  await app.close();
});

test("design-system values resolve as variables, with a separate set for dark", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "散步.md": "# 散步" });
  const { app, page } = await launchWith(scratch, root);
  const card = page.getByRole("article");

  for (const scheme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: scheme });
    const at = scheme === "light" ? 1 : 2;
    for (const row of colours) expect(await computed(page, "color", `var(${row[0]})`), `${row[0]} ${scheme}`).toBe(await computed(page, "color", row[at]!));
    for (const row of shadows) expect(await computed(page, "box-shadow", `var(${row[0]})`), `${row[0]} ${scheme}`).toBe(await computed(page, "box-shadow", row[at]!));
    // Components take the values from the variables.
    await expect(card).toHaveCSS("background-color", await computed(page, "color", `var(--card-bg)`));
    await expect(card).toHaveCSS("box-shadow", await computed(page, "box-shadow", `var(--card-shadow)`));
  }
  for (const [name, value] of sizes) expect(await computed(page, "width", `var(${name})`), name).toBe(value);
  expect(await computed(page, "padding", "var(--item-padding)")).toBe("9px 12px");
  expect(await computed(page, "backdrop-filter", "var(--overlay-blur)")).toBe("blur(40px) saturate(1.7)");
  expect(await computed(page, "backdrop-filter", "var(--menu-blur)")).toBe("blur(24px) saturate(1.6)");
  await expect(card).toHaveCSS("border-radius", "12px");
  await app.close();
});

test("the window shows the system material, or the opaque fallback colour without one", async ({ scratch }) => {
  const { app, page } = await launch(scratch);
  await expect(page.getByRole("button", { name: "选择笔记库…" })).toBeVisible();

  if (process.platform === "darwin") {
    // Vibrancy shows through the whole page; only the card and the list paint over it.
    expect(await windowColor(page)).toBe("rgba(0, 0, 0, 0)");
  } else {
    // Windows keeps its framed window (and so the fallback) until it gets its own title bar.
    await page.emulateMedia({ colorScheme: "light" });
    expect(await windowColor(page)).toBe("rgb(242, 241, 245)");
    await page.emulateMedia({ colorScheme: "dark" });
    expect(await windowColor(page)).toBe("rgb(30, 30, 34)");
  }
  await app.close();
});
