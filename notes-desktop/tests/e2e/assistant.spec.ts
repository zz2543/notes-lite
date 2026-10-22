import type { ElectronApplication, Page } from "@playwright/test";
import { chmod, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { closeSettings, expect, launchWith, library, openSettings, test } from "./fixtures";

// 助手栏 (assistant-spec): docked to the right of the card, opened and closed with ⌘J / Ctrl+J.

/** A command-line agent on the app's search path (the fixture points it at `scratch/agents`). */
async function installAgent(scratch: string, command: string) {
  const dir = join(scratch, "agents");
  await mkdir(dir, { recursive: true });
  const windows = process.platform === "win32";
  const file = join(dir, windows ? `${command}.cmd` : command);
  await writeFile(file, windows ? "@echo off\r\n" : "#!/bin/sh\n");
  if (!windows) await chmod(file, 0o755);
}

async function setWindowWidth(app: ElectronApplication, page: Page, width: number) {
  await app.evaluate(({ BrowserWindow }, w) => {
    const window = BrowserWindow.getAllWindows()[0]!;
    window.setContentSize(w, window.getContentSize()[1]!);
  }, width);
  await expect.poll(() => page.evaluate(() => window.innerWidth)).toBe(width);
  // Resizing settles the navigation again, so let the window's last resize event pass before going on.
  await page.evaluate(
    () =>
      new Promise<void>((done) => {
        let timer = setTimeout(finish, 200);
        function finish() {
          window.removeEventListener("resize", again);
          done();
        }
        function again() {
          clearTimeout(timer);
          timer = setTimeout(finish, 200);
        }
        window.addEventListener("resize", again);
      }),
  );
}

const figures = (page: Page) => page.getByRole("img", { name: /^助手形象/ });

test("⌘J docks the 助手栏 right of the card, which narrows; one 助手形象 at a time", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记" });
  const { app, page } = await launchWith(scratch, root);
  await setWindowWidth(app, page, 1240);
  const column = page.getByRole("complementary", { name: "助手栏" });
  const card = page.getByRole("article", { name: "卡片" });
  await expect(card).toBeVisible();
  const wide = (await card.boundingBox())!;

  // Closed: the card's toggle carries the small figure.
  await expect(column).toBeHidden();
  await expect(figures(page)).toHaveCount(1);
  const toggle = page.getByRole("button", { name: "打开助手栏" });
  await expect(toggle.getByRole("img", { name: /^助手形象/ })).toBeVisible();

  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(column).toBeVisible();
  // The width moves on a quick transition without a bounce, not at once. Read from what the column declares,
  // since a slow runner may finish the running transition before the test looks.
  const transition = await column.evaluate((el) => {
    const style = getComputedStyle(el);
    const split = (list: string) => list.split(/,(?![^(]*\))/).map((item) => item.trim());
    const durations = split(style.transitionDuration);
    const curves = split(style.transitionTimingFunction);
    return split(style.transitionProperty).map((property, i) => [
      property,
      parseFloat(durations[i % durations.length]!) * 1000,
      curves[i % curves.length],
    ]);
  });
  expect(transition).toContainEqual(["width", 260, expect.stringMatching(/^cubic-bezier/)]);
  // Docked, not floating: once settled the column is 340px at the window's right edge and the card ends where it starts.
  await expect.poll(async () => (await column.boundingBox())!.width).toBe(340);
  const box = (await column.boundingBox())!;
  expect(box.x + box.width).toBe(1240);
  const narrow = (await card.boundingBox())!;
  expect(narrow.x + narrow.width).toBeLessThanOrEqual(box.x);
  expect(narrow.width).toBeCloseTo(wide.width - 340, 0);
  // Its figure is at the top of the column; the card's toggle is gone.
  await expect(figures(page)).toHaveCount(1);
  await expect(column.getByRole("img", { name: /^助手形象/ })).toBeVisible();
  await expect(toggle).toHaveCount(0);

  await column.getByRole("button", { name: "关闭助手栏" }).click();
  await expect(column).toBeHidden();
  await expect(page.getByRole("button", { name: "打开助手栏" })).toBeVisible();
  await expect.poll(async () => (await card.boundingBox())!.width).toBeCloseTo(wide.width, 0);

  await page.getByRole("button", { name: "打开助手栏" }).click();
  await expect(column).toBeVisible();
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(column).toBeHidden();
  await app.close();
});

test("with no command-line agent installed, the 助手栏 shows how to install one, and finds it once installed", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记" });
  const { app, page } = await launchWith(scratch, root);
  await expect(page.getByRole("button", { name: "打开助手栏" })).toBeVisible();
  await page.keyboard.press("ControlOrMeta+KeyJ");
  const column = page.getByRole("complementary", { name: "助手栏" });
  const guide = column.getByRole("region", { name: "安装 Agent" });
  await expect(guide).toBeVisible();
  for (const [name, command] of [
    ["Claude Code", "claude"],
    ["Codex", "codex"],
    ["DeepSeek Harness", "dsh"],
    ["Pi", "pi"],
  ] as const) {
    await expect(guide.getByRole("listitem").filter({ hasText: new RegExp(`^${name}`) })).toContainText(command);
  }
  await expect(column.getByRole("button", { name: /^Agent：/ })).toHaveCount(0);

  await installAgent(scratch, "codex");
  await installAgent(scratch, "claude");
  await guide.getByRole("button", { name: "重新检测" }).click();
  await expect(guide).toBeHidden();
  // One name, the first installed; its caret opens what is installed, in the usual order, the current one checked.
  const picker = column.getByRole("button", { name: /^Agent：/ });
  await expect(picker).toHaveAccessibleName("Agent：Claude Code");
  await expect(picker).toHaveAttribute("aria-haspopup", "menu");
  await picker.click();
  await expect(page.getByRole("menuitemradio")).toHaveText(["Claude Code", "Codex"]);
  await expect(page.getByRole("menuitemradio", { name: "Claude Code" })).toHaveAttribute("aria-checked", "true");
  await page.getByRole("menuitemradio", { name: "Codex" }).click();
  await expect(page.getByRole("menu")).toHaveCount(0);
  await expect(picker).toHaveAccessibleName("Agent：Codex");
  await picker.click();
  await expect(page.getByRole("menuitemradio", { name: "Codex" })).toHaveAttribute("aria-checked", "true");
  await page.keyboard.press("Escape");
  await app.close();
});

test("with the 助手栏 open the navigation narrows with the window: 双栏, 单栏, then the 图标栏; closing the column leaves it", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/周一.md": "# 周一", "随记.md": "随记" });
  const { app, page } = await launchWith(scratch, root);
  const column = page.getByRole("complementary", { name: "助手栏" });
  const list = page.getByRole("list", { name: "当前目录内容" });
  const singleTree = page.getByRole("tree", { name: "文件夹与笔记" });
  const rail = page.getByRole("navigation", { name: "导航" });
  await setWindowWidth(app, page, 1200);
  await expect(list).toBeVisible();

  // Wide enough: 双栏 stays, the column is 340px.
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(list).toBeVisible();
  await expect.poll(async () => (await column.boundingBox())!.width).toBe(340);

  // Narrower than 1180px: 单栏, and a 300px column.
  await setWindowWidth(app, page, 1100);
  await expect(list).toHaveCount(0);
  await expect(singleTree).toBeVisible();
  await expect.poll(async () => (await column.boundingBox())!.width).toBe(300);

  // Narrower than 960px: the 图标栏; “展开导航” brings back 单栏.
  await setWindowWidth(app, page, 900);
  await expect(rail).toBeVisible();
  await expect(singleTree).toHaveCount(0);
  await rail.getByRole("button", { name: "展开导航" }).click();
  await expect(rail).toHaveCount(0);
  await expect(singleTree).toBeVisible();
  await setWindowWidth(app, page, 950);
  await expect(rail).toBeVisible();
  // Its search icon opens 单栏 searching in place.
  await rail.getByRole("button", { name: "搜索" }).click();
  await expect(page.getByRole("searchbox", { name: "搜索笔记" })).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(singleTree).toBeVisible();

  // Closing the column does not rearrange the navigation; resizing the window does.
  await setWindowWidth(app, page, 1100);
  await page.keyboard.press("ControlOrMeta+KeyJ");
  // Once the column has finished shutting, the navigation is still as it was.
  const shut = page.getByRole("complementary", { name: "助手栏", includeHidden: true });
  await expect(shut).toBeHidden();
  await expect(shut).toHaveCSS("visibility", "hidden");
  await expect(singleTree).toBeVisible();
  await expect(list).toHaveCount(0);
  await setWindowWidth(app, page, 1120);
  await expect(list).toBeVisible();

  // Reopened, it settles the navigation again.
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(singleTree).toBeVisible();
  await app.close();
});

/** The figure's pixels, to tell whether it moves; and the colour at a point inside the entity's body. */
const figurePixels = (page: Page) =>
  page.getByRole("img", { name: /^助手形象/ }).evaluate((canvas: HTMLCanvasElement) => {
    const ctx = canvas.getContext("2d")!;
    const all = Array.from(ctx.getImageData(0, 0, canvas.width, canvas.height).data);
    // Below the mouth, inside the circle (radius 36% of the canvas).
    const [r, g, b, a] = ctx.getImageData(Math.round(canvas.width / 2), Math.round(canvas.height * 0.72), 1, 1).data;
    return { all: all.join(","), body: [r, g, b, a] };
  });

test("the 助手形象 stands as a flat ink entity and keeps moving; under 减弱动态效果 it is a still frame and the column does not slide", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记" });
  const { app, page } = await launchWith(scratch, root);
  await page.emulateMedia({ colorScheme: "light" });
  const column = page.getByRole("complementary", { name: "助手栏" });
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await expect(column.getByRole("img", { name: "助手形象：待命" })).toBeVisible();
  // 待命 is the entity: #1d1d1f in light mode, fully opaque once fused.
  await expect.poll(async () => (await figurePixels(page)).body).toEqual([0x1d, 0x1d, 0x1f, 255]);
  const before = (await figurePixels(page)).all;
  await expect.poll(async () => (await figurePixels(page)).all !== before).toBe(true);

  await page.emulateMedia({ colorScheme: "light", reducedMotion: "reduce" });
  await column.getByRole("button", { name: "关闭助手栏" }).click();
  await page.getByRole("button", { name: "打开助手栏" }).click();
  await expect(column).toBeVisible();
  expect(await column.evaluate((el) => el.getAnimations().length)).toBe(0);
  await expect.poll(async () => (await figurePixels(page)).body).toEqual([0x1d, 0x1d, 0x1f, 255]);
  const still = (await figurePixels(page)).all;
  await page.waitForTimeout(400);
  expect((await figurePixels(page)).all).toBe(still);
  await app.close();
});

test("with 单栏导航 chosen in 设置, the open 助手栏 never brings back 双栏", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记" });
  const { app, page } = await launchWith(scratch, root);
  await setWindowWidth(app, page, 1300);
  const panel = await openSettings(app, page);
  await panel.getByRole("radiogroup", { name: "导航模式" }).getByRole("radio", { name: "单栏" }).click();
  await closeSettings(app, panel);
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(page.getByRole("complementary", { name: "助手栏" })).toBeVisible();
  await expect(page.getByRole("tree", { name: "文件夹与笔记" })).toBeVisible();
  await expect(page.getByRole("list", { name: "当前目录内容" })).toHaveCount(0);
  await app.close();
});
