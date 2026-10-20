import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { refuseWrites } from "../support/disk";
import { answerFolderPicker, expect, launch, launchWith, library, test } from "./fixtures";

const saveState = (page: Page) => page.getByRole("status", { name: "保存状态" });

async function openNote(page: Page, folder: string, title: string) {
  await page.getByRole("treeitem", { name: folder }).click();
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(page.getByLabel("笔记正文")).toBeFocused();
}

/** Pastes plain text the way the system clipboard hands it over. */
async function paste(page: Page, text: string) {
  await page.getByLabel("笔记正文").evaluate((el, value) => {
    const data = new DataTransfer();
    data.setData("text/plain", value);
    el.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
  }, text);
}

/** Types through the input method path: a pinyin composition, then the committed characters. */
async function compose(page: Page, pinyin: string, text: string) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Input.imeSetComposition", { text: pinyin, selectionStart: pinyin.length, selectionEnd: pinyin.length });
  await cdp.send("Input.insertText", { text });
  await cdp.detach();
}

test("edits reach the disk exactly as typed, with pinyin input, undo and paste", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\r\n\r\n雨后\r\n" });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "日记", "散步");
  const editor = page.getByLabel("笔记正文");

  await editor.click();
  await page.keyboard.press("ControlOrMeta+End");
  await compose(page, "qingtai", "青苔");
  await expect(saveState(page)).toHaveText("已保存");
  // Edits less than 500 ms apart join one undo step (CodeMirror's history grouping); a slow runner can save
  // within that, so the pause keeps " walk" its own step, as it is for anyone who stops to look.
  await page.waitForTimeout(600);
  await page.keyboard.type(" walk");
  await page.keyboard.press("ControlOrMeta+z");
  await expect(editor).toHaveText(/青苔$/, { useInnerText: true });
  // KeyZ, as a real keyboard sends it: with Shift held the key reads "Z", not "z".
  await page.keyboard.press("ControlOrMeta+Shift+KeyZ");
  await expect(editor).toHaveText(/青苔 walk$/, { useInnerText: true });
  // Text copied elsewhere breaks lines with "\n"; in a CRLF note it lands as CRLF.
  await paste(page, "，苔藓\n石头");

  await expect(saveState(page)).toHaveText("已保存");
  expect(await readFile(join(root, "日记/散步.md"), "utf8")).toBe("# 散步\r\n\r\n雨后\r\n青苔 walk，苔藓\r\n石头");
  await expect(page.getByText("11 字")).toBeVisible();
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

  // Switching to another library saves first, too.
  const other = await library(scratch, "另一个库", { "空.md": "" });
  ({ app, page } = await launch(scratch));
  // The launch reopens 二, the note last open.
  await expect(page.getByLabel("笔记正文")).toBeFocused();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("！");
  await answerFolderPicker(app, other);
  await page.getByRole("button", { name: "切换笔记库" }).click();
  await expect(page.getByRole("treeitem", { name: "另一个库" })).toBeVisible();
  expect(await note("二")).toBe("二号！");
  await answerFolderPicker(app, root);
  await page.getByRole("button", { name: "切换笔记库" }).click();

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

test("closing with a save that failed asks before dropping the input", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n" });
  const walk = join(root, "日记/散步.md");
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "日记", "散步");
  const answerCloseDialog = (response: number) =>
    app.evaluate(({ dialog }, choice) => {
      const asked = globalThis as { closeDialogs?: number };
      dialog.showMessageBox = (async () => {
        asked.closeDialogs = (asked.closeDialogs ?? 0) + 1;
        return { response: choice, checkboxChecked: false };
      }) as typeof dialog.showMessageBox;
    }, response);
  const closeWindow = () => app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.close());
  const windows = () => app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length);

  await refuseWrites(walk, true);
  try {
    await page.keyboard.type("雨后");
    await expect(saveState(page)).toContainText("没有写入权限");

    await answerCloseDialog(0); // 返回
    await closeWindow();
    await expect.poll(() => app.evaluate(() => (globalThis as { closeDialogs?: number }).closeDialogs)).toBe(1);
    expect(await windows()).toBe(1);
    await expect(page.getByLabel("笔记正文")).toContainText("雨后");

    await answerCloseDialog(1); // 不保存，直接关闭
    await Promise.all([page.waitForEvent("close"), closeWindow()]);
  } finally {
    await refuseWrites(walk, false);
  }
  expect(await readFile(walk, "utf8")).toBe("# 散步\n");
  await app.close();
});

