import type { ElectronApplication, Page } from "@playwright/test";
import { chmod, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

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
}

const figures = (page: Page) => page.getByRole("img", { name: /^助手形象/ });

test("⌘J docks the 助手栏 right of the card, which narrows; one 助手形象 at a time", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记" });
  const { app, page } = await launchWith(scratch, root);
  await setWindowWidth(app, page, 1240);
  const column = page.getByRole("complementary", { name: "助手栏" });
  const card = page.locator(".card");
  await expect(card).toBeVisible();
  const wide = (await card.boundingBox())!;

  // Closed: the card's toggle carries the small figure.
  await expect(column).toBeHidden();
  await expect(figures(page)).toHaveCount(1);
  const toggle = page.getByRole("button", { name: "打开助手栏" });
  await expect(toggle.getByRole("img", { name: /^助手形象/ })).toBeVisible();

  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(column).toBeVisible();
  // The width moves on a quick transition without a bounce, not at once.
  const transition = await column.evaluate((el) =>
    el.getAnimations().map((a) => [(a as CSSTransition).transitionProperty, a.effect!.getTiming().duration, a.effect!.getTiming().easing]),
  );
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
  await expect(column.getByRole("radiogroup", { name: "Agent" })).toHaveCount(0);

  await installAgent(scratch, "codex");
  await installAgent(scratch, "claude");
  await guide.getByRole("button", { name: "重新检测" }).click();
  await expect(guide).toBeHidden();
  // The switch offers what is installed, in the usual order, the first chosen.
  const agents = column.getByRole("radiogroup", { name: "Agent" });
  await expect(agents.getByRole("radio")).toHaveText(["Claude Code", "Codex"]);
  await expect(agents.getByRole("radio", { name: "Claude Code" })).toHaveAttribute("aria-checked", "true");
  await agents.getByRole("radio", { name: "Codex" }).click();
  await expect(agents.getByRole("radio", { name: "Codex" })).toHaveAttribute("aria-checked", "true");
  await app.close();
});
