import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { refuseWrites } from "../support/disk";
import { expect, launch, launchWith, library, test } from "./fixtures";

const saveState = (page: Page) => page.getByRole("status", { name: "保存状态" });

async function openNote(page: Page, folder: string, title: string) {
  await page.getByRole("treeitem", { name: folder }).click();
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(page.getByLabel("笔记正文")).toBeFocused();
}

/** Types through the input method path: a pinyin composition, then the committed characters. */
async function compose(page: Page, pinyin: string, text: string) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Input.imeSetComposition", { text: pinyin, selectionStart: pinyin.length, selectionEnd: pinyin.length });
  await cdp.send("Input.insertText", { text });
  await cdp.detach();
}

test("edits reach the disk exactly as typed, with pinyin input and undo", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\r\n\r\n雨后\r\n" });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "日记", "散步");
  const editor = page.getByLabel("笔记正文");

  await editor.click();
  await page.keyboard.press("ControlOrMeta+End");
  await compose(page, "qingtai", "青苔");
  await expect(saveState(page)).toHaveText("已保存");
  await page.keyboard.type(" walk");
  await page.keyboard.press("ControlOrMeta+z");
  await expect(editor.locator(".cm-line").last()).toHaveText("青苔");
  await page.keyboard.press("ControlOrMeta+Shift+z");
  await expect(editor.locator(".cm-line").last()).toHaveText("青苔 walk");

  await expect(saveState(page)).toHaveText("已保存");
  expect(await readFile(join(root, "日记/散步.md"), "utf8")).toBe("# 散步\r\n\r\n雨后\r\n青苔 walk");
  await expect(page.getByText("7 字")).toBeVisible();
  await app.close();
});

test("switching notes, closing the window and quitting keep what was just typed", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/一.md": "一", "日记/二.md": "二", "日记/三.md": "三" });
  const note = (name: string) => readFile(join(root, `日记/${name}.md`), "utf8");
  let { app, page } = await launchWith(scratch, root);

  // Each step acts right after typing, well before the autosave delay runs out.
  await openNote(page, "日记", "一");
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("号");
  await page.getByRole("button", { name: "二" }).click();
  await expect(page.getByLabel("笔记正文")).toBeFocused();
  expect(await note("一")).toBe("一号");

  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("号");
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.close());
  await expect.poll(() => note("二")).toBe("二号");
  await app.close();

  ({ app, page } = await launch(scratch));
  await openNote(page, "日记", "三");
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("号");
  await Promise.all([app.waitForEvent("close"), app.evaluate(({ app: electronApp }) => electronApp.quit())]);
  expect(await note("三")).toBe("三号");
});

test("a refused save says so, keeps the input and the note open, and saves on retry", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n", "日记/读书.md": "# 读书\n" });
  const walk = join(root, "日记/散步.md");
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "日记", "散步");
  await page.keyboard.press("ControlOrMeta+End");

  await refuseWrites(walk, true);
  try {
    await page.keyboard.type("雨后");
    await expect(saveState(page)).toContainText("未保存：无法保存“散步”：没有写入权限。");

    await page.getByRole("button", { name: "读书" }).click();
    await expect(page.getByRole("alert")).toContainText("你的输入仍保留在编辑器中");
    await expect(page.getByLabel("笔记正文")).toContainText("雨后");
  } finally {
    await refuseWrites(walk, false);
  }
  await page.getByRole("button", { name: "重试" }).click();
  await expect(saveState(page)).toHaveText("已保存");
  expect(await readFile(walk, "utf8")).toBe("# 散步\n雨后");
  await app.close();
});
