import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

const editor = (page: Page) => page.getByLabel("笔记正文");

async function openNote(page: Page, title: string) {
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(editor(page)).toBeFocused();
  // Colours below are the light appearance's.
  await page.emulateMedia({ colorScheme: "light" });
}

/** Where some text of the note is drawn, and the computed style of the element drawing it. */
function look(page: Page, text: string) {
  return editor(page).evaluate((root, wanted) => {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const at = node.textContent!.indexOf(wanted);
      if (at < 0) continue;
      const range = document.createRange();
      range.setStart(node, at);
      range.setEnd(node, at + wanted.length);
      const box = range.getBoundingClientRect();
      const style = getComputedStyle(node.parentElement!);
      return {
        x: box.x,
        y: box.y,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
        fontFamily: style.fontFamily,
        color: style.color,
      };
    }
    throw new Error(`“${wanted}” is not in the note`);
  }, text);
}

test("a heading is typeset in place, its marker showing only while its line is edited", async ({ scratch }) => {
  const source = "# 雨后的散步\n\n走过青石板。";
  const root = await library(scratch, "笔记库", { "散步.md": source });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "散步");

  await page.keyboard.press("ControlOrMeta+End");
  await expect(editor(page)).not.toContainText("#");
  const heading = await look(page, "雨后的散步");
  // 设计规范: 一级标题 = 字号 × 标题大小比例 × 1.25, in the prototype's title weight.
  expect(heading).toMatchObject({ fontSize: "34px", fontWeight: "650" });

  // On its own line the marker comes back, hanging left of the text so the text stays put.
  await page.keyboard.press("ControlOrMeta+Home");
  await expect(editor(page)).toContainText("# 雨后的散步");
  expect((await look(page, "雨后的散步")).x).toBeCloseTo(heading.x, 0);
  expect((await look(page, "#")).x).toBeLessThan(heading.x);

  expect(await readFile(join(root, "散步.md"), "utf8")).toBe(source);
  await app.close();
});

test("bold, italic and inline code are typeset, their marks dimmed only on the edited line", async ({ scratch }) => {
  const source = "走过 **青石板** 和 *小巷*，带着 `相机`。\n";
  const root = await library(scratch, "笔记库", { "散步.md": source });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "散步");

  await page.keyboard.press("ControlOrMeta+End");
  await expect(editor(page)).toHaveText("走过 青石板 和 小巷，带着 相机。");
  expect(Number((await look(page, "青石板")).fontWeight)).toBeGreaterThanOrEqual(600);
  expect((await look(page, "小巷")).fontStyle).toBe("italic");
  expect((await look(page, "相机")).fontFamily).toContain("monospace");

  await page.keyboard.press("ControlOrMeta+Home");
  await expect(editor(page)).toHaveText(source.trimEnd());
  expect((await look(page, "**")).color).toBe("rgba(29, 29, 31, 0.42)");
  expect(await readFile(join(root, "散步.md"), "utf8")).toBe(source);
  await app.close();
});

test("a quote is typeset muted beside its bar, nested quotes further in", async ({ scratch }) => {
  const source = "雨后。\n\n> 雨停了\n> > 风也停了\n";
  const root = await library(scratch, "笔记库", { "散步.md": source });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "散步");

  await page.keyboard.press("ControlOrMeta+End");
  await expect(editor(page)).not.toContainText(">");
  const paragraph = await look(page, "雨后");
  const quote = await look(page, "雨停了");
  const nested = await look(page, "风也停了");
  expect(quote.color).toBe("rgba(29, 29, 31, 0.42)");
  expect(quote.x).toBeGreaterThan(paragraph.x);
  expect(nested.x).toBeGreaterThan(quote.x);

  await page.keyboard.press("ArrowUp");
  await expect(editor(page)).toContainText("> > 风也停了");
  expect((await look(page, "风也停了")).x).toBeCloseTo(nested.x, 0);
  await app.close();
});

test("lists show bullets and numbers in place of their markers, nesting by indentation", async ({ scratch }) => {
  const source = "雨后。\n\n- 苔藓\n  - 蕨\n1. 第一站\n2) 第二站\n";
  const root = await library(scratch, "笔记库", { "散步.md": source });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "散步");

  await page.keyboard.press("ControlOrMeta+End");
  await expect(editor(page)).toHaveText(["雨后。", "", "•苔藓", "◦蕨", "1.第一站", "2.第二站", ""].join(""));
  const paragraph = await look(page, "雨后");
  const item = await look(page, "苔藓");
  const nested = await look(page, "蕨");
  expect(item.x).toBeGreaterThan(paragraph.x);
  expect(nested.x).toBeGreaterThan(item.x);
  expect((await look(page, "第一站")).x).toBeCloseTo(item.x, 0);
  expect((await look(page, "•")).color).toBe("rgba(29, 29, 31, 0.42)");

  // With the caret at the start of the item's text, its marker shows as written, the text staying put.
  await page.getByText("蕨").click();
  await page.keyboard.press("Home");
  await expect(editor(page)).toContainText("•苔藓- 蕨");
  expect((await look(page, "蕨")).x).toBeCloseTo(nested.x, 0);
  await page.keyboard.press("End");
  await expect(editor(page)).toContainText("•苔藓◦蕨");
  await app.close();
});

test("a fenced code block is set in the code font and coloured by its language", async ({ scratch }) => {
  const source = '路线：\n\n```js\nconst 路 = "长"; // 注释\nlet **不是粗体** = 1;\n```\n\n```\nconst 无语言\n```\n';
  const root = await library(scratch, "笔记库", { "散步.md": source });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "散步");

  await page.keyboard.press("ControlOrMeta+End");
  // Fences and everything inside them stay as written: no Markdown applies in code.
  await expect(editor(page)).toContainText('```jsconst 路 = "长"; // 注释let **不是粗体** = 1;```');
  const keyword = await look(page, "const");
  expect(keyword.fontFamily).toContain("monospace");
  expect(keyword.color).toBe("rgb(155, 35, 147)");
  expect((await look(page, '"长"')).color).toBe("rgb(196, 26, 22)");
  expect((await look(page, "// 注释")).color).toBe("rgb(112, 127, 140)");
  expect((await look(page, "**不是粗体**")).fontWeight).toBe("400");
  // Without a language the code is set plainly.
  expect((await look(page, "const 无语言")).color).toBe("rgb(29, 29, 31)");
  expect((await look(page, "路线")).fontFamily).not.toContain("monospace");
  await app.close();
});
