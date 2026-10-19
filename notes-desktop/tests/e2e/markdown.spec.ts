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
