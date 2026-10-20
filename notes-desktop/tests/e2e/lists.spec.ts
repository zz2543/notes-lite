// 列表延续与退出列表 (list-exit-caret-spec.md), ported from the old ListEditingTests: Return in a list, the
// 分隔空行 put in when text starts below a list and its display, all through the running app.
import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

const editor = (page: Page) => page.getByLabel("笔记正文");

/** A library of notes named 1, 2, 3… holding `sources`, opened in the app. */
async function openLibrary(scratch: string, sources: string[]) {
  const files = Object.fromEntries(sources.map((source, i) => [`${i + 1}.md`, source]));
  const root = await library(scratch, "笔记库", files);
  const { app, page } = await launchWith(scratch, root);
  return {
    app,
    page,
    /** Opens note `n` with the caret at its end. */
    async open(n: number) {
      await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: String(n), exact: true }).click();
      await expect(editor(page)).toBeFocused();
      await page.keyboard.press("ControlOrMeta+End");
    },
    /** Note `n` as saved on disk. */
    saved: (n: number) => () => readFile(join(root, `${n}.md`), "utf8"),
  };
}

test("Return after a list item continues the list with the same kind of marker", async ({ scratch }) => {
  const cases = [
    ["- 苔藓", "蕨", "- 苔藓\n- 蕨"],
    ["  * 子", "孙", "  * 子\n  * 孙"],
    ["1. 第一站", "第二站", "1. 第一站\n2. 第二站"],
    ["9) 九", "十", "9) 九\n10) 十"],
    ["- [x] 买伞", "带相机", "- [x] 买伞\n- [ ] 带相机"],
  ] as const;
  const { app, page, open, saved } = await openLibrary(scratch, cases.map((c) => c[0]));
  for (const [i, [, typed, expected]] of cases.entries()) {
    await open(i + 1);
    await page.keyboard.press("Enter");
    await page.keyboard.type(typed);
    await expect.poll(saved(i + 1)).toBe(expected);
  }
  await app.close();
});
