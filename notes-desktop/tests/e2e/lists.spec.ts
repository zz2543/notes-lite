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

test("Return on an empty outermost item removes only its marker, adding no line", async ({ scratch }) => {
  const cases = [
    ["- 项目\n- ", "- 项目\n"],
    ["1. 项目\n2. ", "1. 项目\n"],
    ["- [ ] 项目\n- [ ] ", "- [ ] 项目\n"],
    ["* 项目\n* ", "* 项目\n"],
  ] as const;
  const { app, page, open, saved } = await openLibrary(scratch, cases.map((c) => c[0]));
  for (const [i, [, kept]] of cases.entries()) {
    await open(i + 1);
    await page.keyboard.press("Enter");
    // Nothing typed: no blank line is added.
    await expect.poll(saved(i + 1)).toBe(kept);
  }
  await app.close();
});

test("Return on an empty nested item steps out one level, taking its parent's marker", async ({ scratch }) => {
  const cases = [
    ["- 父\n  - 子\n  - ", "- 父\n  - 子\n- "],
    ["1. 父\n2. 父二\n   1. 子\n   2. ", "1. 父\n2. 父二\n   1. 子\n3. "],
    ["1) 父\n   - 子\n   - ", "1) 父\n   - 子\n2) "],
    ["- [x] 父\n  - [ ] 子\n  - [ ] ", "- [x] 父\n  - [ ] 子\n- [ ] "],
    ["- 父\n  1. 子\n  2. ", "- 父\n  1. 子\n- "],
  ] as const;
  const { app, page, open, saved } = await openLibrary(scratch, [...cases.map((c) => c[0]), "- 一\n  - 二\n    - 三\n    - "]);
  for (const [i, [, stepped]] of cases.entries()) {
    await open(i + 1);
    await page.keyboard.press("Enter");
    // The caret ends after the new marker.
    await page.keyboard.type("新");
    await expect.poll(saved(i + 1)).toBe(`${stepped}新`);
  }

  // One level at a time; at the outermost level the list ends. Undo steps back the same way.
  const deep = cases.length + 1;
  const steps = ["    - ", "  - ", "- ", ""].map((last) => `- 一\n  - 二\n    - 三\n${last}`);
  await open(deep);
  for (const step of steps.slice(1)) {
    await page.keyboard.press("Enter");
    await expect.poll(saved(deep)).toBe(step);
  }
  for (const step of steps.slice(0, -1).reverse()) {
    await page.keyboard.press("ControlOrMeta+KeyZ");
    await expect.poll(saved(deep)).toBe(step);
  }
  await app.close();
});

test("text typed after exiting a list is separated from it by a blank line, undone with it", async ({ scratch }) => {
  const { app, page, open, saved } = await openLibrary(scratch, ["- 项目\n- "]);
  await open(1);
  await page.keyboard.press("Enter");
  await page.keyboard.type("正文");
  // Markdown needs the blank line to end the list.
  await expect.poll(saved(1)).toBe("- 项目\n\n正文");

  // Undo steps back to the exited list without the blank line ever standing alone.
  const states: string[] = [];
  for (let text = await saved(1)(); text !== "- 项目\n- " && states.length < 6; ) {
    await page.keyboard.press("ControlOrMeta+KeyZ");
    const before = text;
    await expect.poll(async () => (text = await saved(1)())).not.toBe(before);
    states.push(text);
  }
  expect(states.at(-1)).toBe("- 项目\n- ");
  expect(states).not.toContain("- 项目\n\n");
  await app.close();
});

test("stepping out of a numbered list leaves later numbers alone, and code is left alone", async ({ scratch }) => {
  const { app, page, open, saved } = await openLibrary(scratch, ["1. 甲\n   1. 乙\n   2. \n2. 丙", "```\n- 项目\n- \n```"]);
  await open(1);
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("End");
  await page.keyboard.press("Enter");
  await expect.poll(saved(1)).toBe("1. 甲\n   1. 乙\n2. \n2. 丙");

  // Inside code Return is just a new line.
  await open(2);
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("End");
  await page.keyboard.press("Enter");
  await expect.poll(saved(2)).toBe("```\n- 项目\n- \n\n```");
  await app.close();
});
