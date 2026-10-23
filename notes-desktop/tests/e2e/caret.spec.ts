import type { Page } from "@playwright/test";
import { closeSettings, expect, launchWith, library, openSettings, test } from "./fixtures";

// 光标动画 (ticket 11, 2026-10-23 用户确认): the insertion caret slides like Word's smooth caret, typing in
// English or Chinese and while pinyin is composed; 设置 › 动画 turns it off, back to the browser's caret.

const caret = (page: Page) => page.locator(".cm-smooth-caret");

/** Where the drawn caret is headed, and where the browser's own caret is, both in the window. */
async function places(page: Page) {
  return page.evaluate(() => {
    const drawn = document.querySelector<HTMLElement>(".cm-smooth-caret")!;
    const scroller = drawn.parentElement!;
    const target = new DOMMatrixReadOnly(drawn.style.transform);
    const frame = scroller.getBoundingClientRect();
    const range = getSelection()!.getRangeAt(0).cloneRange();
    range.collapse(false);
    const native = range.getClientRects()[0]!;
    return {
      x: target.m41 + frame.left - scroller.scrollLeft,
      y: target.m42 + frame.top - scroller.scrollTop,
      nativeX: native.left,
      nativeY: native.top,
      sliding: drawn.getAnimations().some((a) => a.playState === "running" && (a.effect as KeyframeEffect).getKeyframes().some((k) => "transform" in k)),
    };
  });
}

async function compose(page: Page, pinyin: string) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Input.imeSetComposition", { text: pinyin, selectionStart: pinyin.length, selectionEnd: pinyin.length });
  await cdp.detach();
}

async function commit(page: Page, text: string) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Input.insertText", { text });
  await cdp.detach();
}

test("the caret slides as English, pinyin and committed Chinese are typed, and 设置 turns it off", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n\n雨后\n" });
  const { app, page } = await launchWith(scratch, root);
  await page.getByRole("treeitem", { name: "日记" }).click();
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: "散步" }).click();
  const editor = page.getByLabel("笔记正文");
  await editor.click();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("End");
  await expect(caret(page)).toBeVisible();
  // The browser's caret is unseen; the drawn one stands where it is.
  expect(await editor.evaluate((el) => getComputedStyle(el).caretColor)).toBe("rgba(0, 0, 0, 0)");
  const start = await places(page);
  expect(Math.abs(start.x - start.nativeX)).toBeLessThan(2);

  // Typing: it slides to the new place, then rests there, by the browser's caret.
  await page.keyboard.type("a");
  const typed = await places(page);
  expect(typed.x).toBeGreaterThan(start.x);
  expect(typed.sliding).toBe(true);
  await expect.poll(async () => (await places(page)).sliding).toBe(false);
  const rested = await places(page);
  expect(Math.abs(rested.x - rested.nativeX)).toBeLessThan(2);

  // Pinyin: the caret follows the composed letters, then the committed characters.
  await compose(page, "qing");
  await expect.poll(async () => (await places(page)).x).toBeGreaterThan(rested.x + 10);
  await commit(page, "青");
  await expect(editor).toContainText("雨后a青");
  await expect.poll(async () => (await places(page)).sliding).toBe(false);
  const committed = await places(page);
  expect(Math.abs(committed.x - committed.nativeX)).toBeLessThan(2);
  expect(Math.abs(committed.y - committed.nativeY)).toBeLessThan(6);

  // Off in 设置 › 动画: the browser's caret again.
  const settings = await openSettings(app, page, "动画");
  const toggle = settings.getByRole("switch", { name: "光标动画" });
  await expect(toggle).toHaveAttribute("aria-checked", "true");
  await toggle.click();
  await closeSettings(app, settings);
  await expect(caret(page)).toHaveCount(0);
  expect(await editor.evaluate((el) => getComputedStyle(el).caretColor)).not.toBe("rgba(0, 0, 0, 0)");
  await app.close();
});
