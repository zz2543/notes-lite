import type { Page } from "@playwright/test";
import { expect, launchWith, library, test } from "./fixtures";

// 专注模式 (spec.md, ui-motion-spec.md): only the note's title and body, the card filling the window.

async function openNote(page: Page, title: string) {
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(page.getByLabel("笔记正文")).toBeFocused();
}

const focusShortcut = "ControlOrMeta+Shift+KeyF";

test("⌘⇧F leaves only the note's title and body; Esc brings everything back", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "# 随记\n\n雨后" });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "随记");
  const side = page.getByRole("tree", { name: "文件夹" });
  const list = page.getByRole("list", { name: "当前目录内容" });
  const sourceTool = page.getByRole("button", { name: "Markdown 源码" });
  const saveState = page.getByRole("status", { name: "保存状态" });

  await page.keyboard.press(focusShortcut);
  await expect(side).toBeHidden();
  await expect(list).toBeHidden();
  await expect(sourceTool).toBeHidden();
  await expect(saveState).toBeHidden();
  await expect(page.getByLabel("笔记正文")).toContainText("雨后");
  await expect(page.getByRole("button", { name: "退出专注" })).toBeVisible();

  await page.keyboard.press("Escape");
  await expect(side).toBeVisible();
  await expect(list).toBeVisible();
  await expect(sourceTool).toBeVisible();
  await expect(saveState).toBeVisible();
  await expect(page.getByRole("button", { name: "退出专注" })).toHaveCount(0);
  await app.close();
});

const selected = (page: Page) => page.evaluate(() => getSelection()?.toString());
/** How far the note is scrolled: the reading position. */
const scrolled = (page: Page) => page.getByLabel("笔记正文").evaluate((el) => el.parentElement!.scrollTop);

test("the card's button goes in and out, keeping the text, the selection and where the note was read", async ({ scratch }) => {
  const lines = Array.from({ length: 120 }, (_, i) => `第${i + 1}行，雨后的石阶。`);
  const root = await library(scratch, "笔记库", { "长文.md": `# 长文\n\n${lines.join("\n\n")}` });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "长文");
  const editor = page.getByLabel("笔记正文");
  // Down to the 60th paragraph, the note scrolling along with the caret.
  await page.keyboard.press("ControlOrMeta+Home");
  for (let i = 0; i < 2 * 59 - 2; i++) await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Home");
  for (let i = 0; i < 5; i++) await page.keyboard.press("Shift+ArrowRight");
  expect(await selected(page)).toBe("第60行，");
  const top = await scrolled(page);
  expect(top).toBeGreaterThan(0);
  const card = page.locator(".card");
  const before = (await card.boundingBox())!;

  await page.getByRole("button", { name: "进入专注模式" }).click();
  // The card takes the room the navigation and the list gave up.
  await expect.poll(async () => (await card.boundingBox())!.x).toBeLessThan(before.x - 400);
  await expect(page.getByRole("tree", { name: "文件夹" })).toBeHidden();
  expect(await selected(page)).toBe("第60行，");

  await page.getByRole("button", { name: "退出专注" }).click();
  await expect.poll(async () => (await card.boundingBox())!.x).toBeCloseTo(before.x, 0);
  expect(await selected(page)).toBe("第60行，");
  expect(Math.abs((await scrolled(page)) - top)).toBeLessThanOrEqual(2);
  // The caret is still in the note: typing replaces the selection.
  await page.keyboard.type("首");
  await expect(editor).toContainText("首雨后的石阶。");
  await app.close();
});

test("in 专注模式 the 助手栏 stays docked right and the card fills the rest of the window", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记" });
  const { app, page } = await launchWith(scratch, root);
  await app.evaluate(({ BrowserWindow }) => {
    const window = BrowserWindow.getAllWindows()[0]!;
    window.setContentSize(1240, window.getContentSize()[1]!);
  });
  await expect.poll(() => page.evaluate(() => window.innerWidth)).toBe(1240);
  await openNote(page, "随记");
  const column = page.getByRole("complementary", { name: "助手栏" });
  const card = page.locator(".card");

  await page.keyboard.press(focusShortcut);
  // ⌘J still opens the column in 专注模式.
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(column).toBeVisible();
  await expect.poll(async () => (await column.boundingBox())!.width).toBe(340);
  const docked = (await column.boundingBox())!;
  expect(docked.x + docked.width).toBe(1240);
  await expect.poll(async () => (await card.boundingBox())!.x).toBeLessThanOrEqual(12);
  const box = (await card.boundingBox())!;
  expect(box.x + box.width).toBeLessThanOrEqual(docked.x);
  expect(box.x + box.width).toBeGreaterThan(docked.x - 24);
  await expect(page.getByLabel("笔记正文")).toBeVisible();

  // Leaving 专注模式 keeps the column open.
  await page.keyboard.press("Escape");
  await expect(page.getByRole("list", { name: "当前目录内容" })).toBeVisible();
  await expect(column).toBeVisible();
  await app.close();
});
