import type { Locator, Page } from "@playwright/test";
import { expect, film, launch, launchWith, library, test, transitionOf } from "./fixtures";

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
  // It passes through the rows in between instead of jumping, and comes to rest on the chosen row. Hosted
  // macOS runners draw frames too unevenly to film a slide reliably, so there a missing in-between is noted
  // in the report rather than failing; on a real screen it must show.
  const slid = frames.some((f) => f.top > from + 2 && f.top < to - 2);
  if (process.env.CI && !slid) test.info().annotations.push({ type: "slide not filmed", description: `${frames.length} frames` });
  else expect(slid).toBe(true);
  await expect.poll(() => top(page.locator(sidePill))).toBeCloseTo(to, 0);
  await app.close();
});

test("switching notes: a near pill slides, a far one fades out there and in here; the text fades in, rising", async ({ scratch }) => {
  const notes = Object.fromEntries(Array.from({ length: 12 }, (_, i) => [`${String(i + 1).padStart(2, "0")}.md`, `第 ${i + 1} 篇`]));
  const { app, page } = await launchWith(scratch, await library(scratch, "笔记库", notes));
  const list = page.getByRole("list", { name: "当前目录内容" });
  const listPill = 'section.list [data-testid="selection-pill"]';
  // By place in the list, whatever order it sorts them in.
  const row = (n: number) => list.getByRole("button").nth(n);
  await row(0).click();
  const first = await top(row(0));
  const near = row(2);
  const nearTop = await top(near);
  const slid = await film(page, listPill, () => near.click(), 600);
  const between = slid.some((f) => f.top > Math.min(first, nearTop) + 2 && f.top < Math.max(first, nearTop) - 2);
  // It starts where it was, never drawn a frame early on the new row.
  expect(Math.abs(slid[0]!.top - first)).toBeLessThan(2);
  if (process.env.CI && !between) test.info().annotations.push({ type: "slide not filmed", description: `${slid.length} frames` });
  else expect(between).toBe(true);

  // Nine rows on: it never sweeps across the rows between; it appears on the new row, faint and a little small.
  const far = row(11);
  const farTop = await top(far);
  const jumped = await film(page, listPill, () => far.click(), 600);
  expect(jumped.every((f) => Math.abs(f.top - nearTop) < 2 || Math.abs(f.top - farTop) < 2)).toBe(true);
  const arrived = jumped.filter((f) => Math.abs(f.top - farTop) < 2);
  if (!(process.env.CI && arrived.length < 2)) {
    expect(Math.min(...arrived.map((f) => f.opacity))).toBeLessThan(1);
    expect(Math.min(...arrived.map((f) => f.scale))).toBeLessThan(1);
  }
  await expect.poll(() => page.locator(listPill).evaluate((pill) => getComputedStyle(pill).opacity)).toBe("1");
  // The old one is gone from its row once it has faded.
  await expect(page.locator("section.list .pill")).toHaveCount(1);

  // The note's text comes in over a moment rather than at once.
  const text = await film(page, ".editor", () => row(5).click(), 400);
  if (!(process.env.CI && text.length < 2)) expect(Math.min(...text.map((f) => f.opacity))).toBeLessThan(1);
  await expect(page.locator(".editor")).toHaveCSS("opacity", "1");
  await app.close();
});

test("a chosen row's icon cross-fades from outline to fill instead of swapping at once", async ({ scratch }) => {
  const { app, page } = await launchWith(scratch, await library(scratch, "笔记库", { "日记/散步.md": "散步" }));
  const row = page.getByRole("tree", { name: "文件夹" }).getByRole("treeitem", { name: "日记" });
  const icons = row.locator(".selected-icon > svg");
  await expect(icons).toHaveCount(2);
  expect(await transitionOf(page, '[aria-label="日记"] .selected-icon > svg', "opacity")).toMatchObject({ duration: expect.any(Number) });
  expect((await transitionOf(page, '[aria-label="日记"] .selected-icon > svg', "opacity"))!.duration).toBeGreaterThan(0);
  await row.click();
  await expect(row.locator(".selected-icon > .on")).toHaveCSS("opacity", "1");
  await expect(row.locator(".selected-icon > .off")).toHaveCSS("opacity", "0");
  await app.close();
});

test("the list's selection pill covers exactly its row, all four corners round", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "短.md": "一", [`${"很长的标题".repeat(12)}.md`]: "二" });
  const { app, page } = await launchWith(scratch, root);
  const list = page.getByRole("list", { name: "当前目录内容" });
  for (const name of ["短", "很长的标题"]) {
    const row = list.getByRole("button", { name: new RegExp(`^${name}`) });
    await row.click();
    const pill = row.getByTestId("selection-pill");
    await expect.poll(async () => JSON.stringify(await pill.boundingBox())).toBe(JSON.stringify(await row.boundingBox()));
    // Nothing spills sideways out of the list to be clipped at its edge.
    expect(await page.locator("section.list .items").evaluate((items) => items.scrollWidth <= items.clientWidth)).toBe(true);
    expect(await pill.evaluate((element) => getComputedStyle(element).borderLeftWidth)).toBe("0px");
  }
  await app.close();
});

/** Whether a change of `scale` on this element eases on a spring curve rather than jumping. */
const springOf = (locator: Locator) =>
  locator.evaluate((element) => {
    const style = getComputedStyle(element);
    const properties = style.transitionProperty.split(", ");
    const index = properties.findIndex((property) => property === "scale" || property === "all");
    if (index < 0) return false;
    const pick = (list: string) => list.split(/,(?![^(]*\))/).map((item) => item.trim());
    const durations = pick(style.transitionDuration);
    const curves = pick(style.transitionTimingFunction);
    const duration = parseFloat(durations[index % durations.length] ?? "0");
    const curve = curves[index % curves.length] ?? "linear";
    return duration > 0 && curve !== "linear" && curve !== "step-end";
  });

test("hover only tints a row; pressing shrinks it with a spring and it springs back", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步", "读书.md": "# 读书" });
  const { app, page } = await launchWith(scratch, root);
  const item = page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: "读书" });

  await item.hover();
  await expect(item).toHaveCSS("background-color", await computed(page, "color", "var(--hover)"));
  await expect(item).toHaveCSS("scale", "none");

  // It eases into the new size, not a jump, and holds at 0.97 while pressed. Asked of the transition the
  // row carries rather than of filmed frames or a running animation, which a busy runner may finish or skip
  // before the test can look.
  await item.hover();
  await page.mouse.down();
  expect(await springOf(item)).toBe(true);
  await expect(item).toHaveCSS("scale", "0.97");
  await page.mouse.up();
  expect(await springOf(item)).toBe(true);
  await expect(item).toHaveCSS("scale", /^(none|1)$/);
  await app.close();
});

test("with reduced motion nothing slides, scales, blurs or turns; menus and dialogs only fade", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "甲/一.md": "一", "乙/二.md": "二", "丙/三.md": "三", "散步.md": "# 散步" });
  const { app, page } = await launchWith(scratch, root);
  // Turned on while the app runs, as the system setting would be.
  await page.emulateMedia({ reducedMotion: "reduce" });
  const tree = page.getByRole("tree", { name: "文件夹" });
  const from = await top(tree.getByRole("treeitem", { name: "笔记库" }));
  const target = tree.getByRole("treeitem", { name: "甲" });
  const to = await top(target);

  const slid = await film(page, sidePill, () => target.click());
  expect(slid.every((f) => Math.abs(f.top - from) < 0.5 || Math.abs(f.top - to) < 0.5)).toBe(true);
  expect(slid.every((f) => f.filter === "none")).toBe(true);

  const row = tree.getByRole("treeitem", { name: "乙" });
  await row.evaluate((element) => element.setAttribute("data-filmed", ""));
  const pressed = await film(page, "[data-filmed]", () => row.hover().then(() => page.mouse.down()), 500);
  expect(pressed.every((f) => f.scale === 1)).toBe(true);
  await page.mouse.up();

  // Carets jump, and menus and dialogs only fade (ticket 23).
  await tree.getByRole("treeitem", { name: "笔记库" }).click();
  expect(await transitionOf(page, '[aria-label="甲"] > .caret svg', "rotate")).toMatchObject({ duration: 0 });
  const item = page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: "散步" });
  const menu = await film(page, ".menu", () => item.click({ button: "right" }), 600);
  expect(menu.length).toBeGreaterThan(0);
  expect(menu.every((f) => f.scale === 1)).toBe(true);
  expect(Math.min(...menu.map((f) => f.opacity))).toBeLessThan(1);
  const dialog = await film(page, ".dialog", () => page.getByRole("menuitem", { name: "重命名…" }).click(), 600);
  await expect(page.getByRole("dialog", { name: "重命名笔记" })).toBeVisible();
  expect(dialog.length).toBeGreaterThan(0);
  expect(dialog.every((f) => f.scale === 1 && f.blur === 0)).toBe(true);
  await app.close();
});

// 动效专项审查 (ticket 23): carets, menus and dialogs on the design system's presets.

const rotation = (page: Page, name: string) =>
  page.getByRole("treeitem", { name, exact: true }).locator(".caret svg").evaluate((svg) => getComputedStyle(svg).rotate);

test("a folder's caret turns on 展开, and turns back from where it is when clicked again", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/周一/一.md": "一" });
  const { app, page } = await launchWith(scratch, root);
  const caret = page.getByRole("button", { name: "展开日记" });
  await expect(caret).toBeVisible();
  expect(await transitionOf(page, '[aria-label="日记"] > .caret svg', "rotate")).toMatchObject({ curve: expect.stringMatching(/^linear\(/) });
  expect(await rotation(page, "日记")).toBe("none");

  await caret.click();
  await expect.poll(() => rotation(page, "日记")).toBe("90deg");
  // Clicked twice in a row: it ends shut, not after a queue of turns.
  await page.getByRole("button", { name: "收起日记" }).click();
  await page.getByRole("button", { name: "展开日记" }).click();
  await page.getByRole("button", { name: "收起日记" }).click();
  await expect(page.getByRole("treeitem", { name: "周一" })).toHaveCount(0);
  await expect.poll(() => rotation(page, "日记")).toBe("none");
  await app.close();
});

test("a folder row's new-note icon fades in with the hover, without a bounce", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/一.md": "一" });
  const { app, page } = await launchWith(scratch, root);
  const row = page.getByRole("treeitem", { name: "日记" });
  await expect(row).toBeVisible();
  expect(await transitionOf(page, ".row-new", "opacity")).toMatchObject({ duration: expect.any(Number), curve: "ease-out" });
  expect((await transitionOf(page, ".row-new", "opacity"))!.duration).toBeGreaterThan(0);
  await app.close();
});

test("a menu grows from the pointer's corner on 展开; a dialog emerges out of a blur on 浮现 and shrinks away", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "散步.md": "# 散步" });
  const { app, page } = await launchWith(scratch, root);
  const item = page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: "散步" });

  const menuFrames = await film(page, ".menu", () => item.click({ button: "right" }));
  const menu = page.getByRole("menu");
  await expect(menu).toBeVisible();
  // Below and right of the pointer, so it grows from its top-left corner.
  expect(await menu.evaluate((el) => getComputedStyle(el).transformOrigin)).toBe("0px 0px");
  expect(menuFrames.length).toBeGreaterThan(0);
  expect(Math.min(...menuFrames.map((f) => f.scale))).toBeLessThan(1);
  expect(Math.min(...menuFrames.map((f) => f.opacity))).toBeLessThan(1);
  // It settles at full size (the spring's tail is longer than its visual duration).
  await expect(menu).toHaveCSS("scale", /^(none|1)$/);
  await expect(menu).toHaveCSS("opacity", "1");

  // Typed into as soon as it shows: typing doesn't wait for it.
  const dialog = page.getByRole("dialog", { name: "重命名笔记" });
  const dialogFrames = await film(page, ".dialog", async () => {
    await page.getByRole("menuitem", { name: "重命名…" }).click();
    await page.keyboard.type("x");
  });
  await expect(dialog.getByRole("textbox")).toHaveValue(/x$/);
  expect(dialogFrames.length).toBeGreaterThan(0);
  // Its opacity eases in: it never bounces past 1 and back.
  expect(dialogFrames.every((f, i) => i === 0 || f.opacity >= dialogFrames[i - 1]!.opacity - 0.001)).toBe(true);
  expect(Math.min(...dialogFrames.map((f) => f.scale))).toBeLessThan(0.95);
  expect(Math.max(...dialogFrames.map((f) => f.blur))).toBeGreaterThan(0);
  await expect.poll(() => dialog.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).a)).toBe(1);
  await expect(dialog).toHaveCSS("filter", /^(none|blur\(0px\))$/);

  // Esc: it shrinks away, and is gone.
  const closing = await film(page, ".dialog", () => page.keyboard.press("Escape"), 500);
  expect(closing.some((f) => f.scale < 1)).toBe(true);
  await expect(dialog).toHaveCount(0);
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
  ["--side-pill", "rgba(255,255,255,.9)", "rgba(255,255,255,.11)"],
  ["--list-pill", "#ffffff", "rgba(255,255,255,.13)"],
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
  [
    "--pill-shadow",
    "0 0 0 .5px rgba(0,0,0,.06), 0 .5px 1px rgba(0,0,0,.07), 0 2px 6px -1px rgba(0,0,0,.08)",
    "inset 0 .5px 0 rgba(255,255,255,.09), 0 0 0 .5px rgba(255,255,255,.06), 0 1px 3px rgba(0,0,0,.28)",
  ],
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
