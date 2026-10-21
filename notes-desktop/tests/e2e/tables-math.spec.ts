import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

// 任务 12: tables and formulas drawn in place while the caret is elsewhere, their Markdown back while it is
// in them; the file stays exactly as written.

const editor = (page: Page) => page.getByLabel("笔记正文");

async function openNote(page: Page, title: string) {
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(editor(page)).toBeFocused();
}

test("a table is a grid until the caret goes into it; a click on a cell edits that cell", async ({ scratch }) => {
  const source = "# 书单\n\n| 书名 | 页数 |\n| :--- | ---: |\n| **雪国** ❄️ | 180 |\n| 古都 | 220 |\n\n读完了。";
  const root = await library(scratch, "笔记库", { "书单.md": source });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "书单");
  await page.keyboard.press("ControlOrMeta+End");

  const grid = editor(page).getByRole("table");
  await expect(grid.getByRole("columnheader")).toHaveText(["书名", "页数"]);
  // An emoji in a cell (two UTF-16 units) is drawn like any other text.
  await expect(grid.getByRole("row")).toHaveText(["书名页数", "雪国 ❄️180", "古都220"]);
  await expect(grid.getByRole("cell", { name: "180" })).toHaveCSS("text-align", "right");
  // Cells are typeset: bold without its asterisks.
  await expect(grid.getByRole("cell", { name: "雪国" }).locator("span")).toHaveCSS("font-weight", "600");
  await expect(editor(page)).not.toContainText("| :---");

  // A click on a cell: the source comes back, the caret at the end of that cell's text.
  await grid.getByRole("cell", { name: "220" }).click();
  await expect(editor(page).getByRole("table")).toHaveCount(0);
  await expect(editor(page)).toContainText("| :--- | ---: |");
  await page.keyboard.type("0");
  await expect(editor(page)).toContainText("| 古都 | 2200 |");

  // Off the table, it is a grid again, with what was typed.
  await page.keyboard.press("ControlOrMeta+End");
  await expect(grid.getByRole("cell", { name: "2200" })).toBeVisible();
  await expect(editor(page)).not.toContainText("| :---");

  // Arrowing into it opens it too, from below and from above.
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("ArrowUp");
  await expect(editor(page).getByRole("table")).toHaveCount(0);
  await page.keyboard.press("ControlOrMeta+Home");
  await expect(grid).toBeVisible();
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("ArrowDown");
  await expect(editor(page).getByRole("table")).toHaveCount(0);
  await expect(editor(page)).toContainText("| 书名 | 页数 |");

  await expect.poll(() => readFile(join(root, "书单.md"), "utf8")).toBe(source.replace("| 220 |", "| 2200 |"));
  await app.close();
});

test("formulas are drawn by KaTeX, inline and on their own lines; with the caret in one its TeX is back", async ({ scratch }) => {
  const source = "# 公式\n\n传输延时 $d = L/R$，很短；$\\nope x$ 写错了。\n\n$$\n\\frac{a}{b}\n$$\n\n$$e = mc^2$$\n\n结尾。";
  const root = await library(scratch, "笔记库", { "公式.md": source });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "公式");
  await page.keyboard.press("ControlOrMeta+End");

  const inline = editor(page).locator(".cm-md-math .katex");
  const blocks = editor(page).locator(".cm-md-math-block .katex-display");
  await expect(inline).toHaveCount(2);
  await expect(blocks).toHaveCount(2);
  await expect(editor(page)).not.toContainText("$");
  // A command KaTeX doesn't know is shown as written, in its error colour.
  await expect(inline.nth(1).getByText("\\nope")).toHaveCSS("color", "rgb(204, 0, 0)");
  await expect(editor(page)).not.toContainText("\\frac");
  await expect(blocks.first().locator(".mfrac")).toHaveCount(1);

  // The line with the inline formula, being edited: its TeX as written.
  await editor(page).getByText("传输延时").click();
  await expect(editor(page)).toContainText("$d = L/R$");
  await expect(inline).toHaveCount(0);

  // A click on a formula block goes into its TeX, and the picture stays below as a preview.
  await blocks.first().click();
  await expect(editor(page)).toContainText("\\frac{a}{b}");
  await expect(editor(page).locator(".cm-md-math-preview .katex-display")).toHaveCount(1);
  await page.keyboard.press("End");
  await page.keyboard.type("+c");
  await expect(editor(page).locator(".cm-md-math-preview")).toContainText("+c");

  // The one-line formula opens the same way.
  await blocks.last().click();
  await expect(editor(page)).toContainText("$$e = mc^2$$");

  // Away from them, everything is drawn again; ↑ from below goes into a formula as into a table.
  await page.keyboard.press("ControlOrMeta+End");
  await expect(blocks).toHaveCount(2);
  await expect(inline).toHaveCount(2);
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("ArrowUp");
  await expect(editor(page)).toContainText("$$e = mc^2$$");
  await expect.poll(() => readFile(join(root, "公式.md"), "utf8")).toBe(source.replace("\\frac{a}{b}", "\\frac{a}{b}+c"));
  await app.close();
});

test("in the Markdown source view tables and formulas are shown as written", async ({ scratch }) => {
  const source = "| a | b |\n|---|---|\n| 1 | 2 |\n\n$x^2$ 和\n\n$$y$$";
  const root = await library(scratch, "笔记库", { "源码.md": source });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "源码");
  await page.keyboard.press("ControlOrMeta+End");
  await expect(editor(page).getByRole("table")).toBeVisible();

  await page.keyboard.press("ControlOrMeta+Shift+M");
  await expect(editor(page).getByRole("table")).toHaveCount(0);
  await expect(editor(page).locator(".katex")).toHaveCount(0);
  await expect(editor(page)).toContainText("|---|---|");
  await expect(editor(page)).toContainText("$x^2$ 和");
  await expect(editor(page)).toContainText("$$y$$");

  // Back to the typeset view with the caret in the table: it stays open to be edited.
  await editor(page).getByText("| 1 | 2 |").click();
  await page.keyboard.press("ControlOrMeta+Shift+M");
  await expect(editor(page)).toContainText("|---|---|");
  await expect(editor(page).getByRole("table")).toHaveCount(0);
  await page.keyboard.press("ControlOrMeta+End");
  await expect(editor(page).getByRole("table")).toBeVisible();
  await app.close();
});

test("KaTeX's fonts load from the app, the page's CSP refusing none of them", async ({ scratch }) => {
  // Big delimiters, operators and the AMS, calligraphic and Fraktur alphabets: most of KaTeX's fonts.
  const tex = "\\left(\\frac{\\frac{a}{b}}{\\frac{c}{d}}\\right) \\Bigg( x \\Bigg) \\sum_{i=1}^n \\mathbb{R} \\mathcal{L} \\mathfrak{g}";
  const root = await library(scratch, "笔记库", { "公式.md": `$$\n${tex}\n$$\n\n结尾。` });
  const { app, page } = await launchWith(scratch, root);
  const refused: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error" && message.text().includes("Content Security Policy")) refused.push(message.text());
  });
  await openNote(page, "公式");
  await page.keyboard.press("ControlOrMeta+End");
  await expect(editor(page).locator(".cm-md-math-block .katex-display")).toBeVisible();

  const fonts = () =>
    page.evaluate(async () => {
      await document.fonts.ready;
      return [...document.fonts].filter((f) => f.family.startsWith("KaTeX") && f.status !== "unloaded").map((f) => `${f.family} ${f.status}`);
    });
  await expect.poll(fonts).toEqual(expect.arrayContaining(["KaTeX_Size3 loaded", "KaTeX_Size4 loaded", "KaTeX_AMS loaded", "KaTeX_Fraktur loaded"]));
  expect((await fonts()).filter((f) => !f.endsWith("loaded"))).toEqual([]);
  expect(refused).toEqual([]);
  await app.close();
});
