import type { Locator, Page } from "@playwright/test";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launch, launchWith, library, test } from "./fixtures";

const note = "# 雨后\n\n小路上的青苔很滑，我们走了3公里才到Lakeside。\n\n第二段。\n";

async function openNote(page: Page, title: string) {
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(page.getByRole("textbox", { name: "笔记正文" })).toContainText(title);
}

async function openTypography(page: Page) {
  await page.keyboard.press("ControlOrMeta+Comma");
  const panel = page.getByRole("dialog", { name: "设置" });
  await panel.getByRole("tab", { name: "排版" }).click();
  return panel;
}

/** A computed style of the first element inside `scope` that matches `selector`. */
const style = (scope: Locator, selector: string, property: string) =>
  scope.evaluate((element, [selector, property]) => getComputedStyle(element.querySelector(selector)!).getPropertyValue(property), [selector, property] as const);

/** Loads `family` for `text` and answers whether a face of it came from the app (not a system fallback). */
const bundled = (page: Page, family: string, weight: number, text: string) =>
  page.evaluate(
    async ([family, weight, text]) => (await document.fonts.load(`${weight} 16px "${family}"`, text)).some((face) => face.family.replace(/"/g, "") === family),
    [family, weight, text] as const,
  );

test("body and heading fonts come from presets, the bundled serifs, or the fonts installed here", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "雨后.md": note });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "雨后");

  // 思源宋体 (常规, 半粗) and Source Serif 4 ship with the app.
  expect(await bundled(page, "Noto Serif SC", 400, "永")).toBe(true);
  expect(await bundled(page, "Noto Serif SC", 600, "永")).toBe(true);
  expect(await bundled(page, "Source Serif 4 Variable", 400, "A")).toBe(true);

  const panel = await openTypography(page);
  const body = panel.getByRole("radiogroup", { name: "正文字体" });
  expect(await body.getByRole("radio").evaluateAll((radios) => radios.map((r) => r.getAttribute("aria-label")))).toEqual(["系统", "思源宋体", "Source Serif", "等宽"]);
  await expect(body.getByRole("radio", { name: "系统" })).toHaveAttribute("aria-checked", "true");
  const preview = panel.getByRole("figure", { name: "排版预览" });

  await body.getByRole("radio", { name: "Source Serif" }).click();
  await expect.poll(() => style(preview, ".cm-content", "font-family")).toMatch(/^"Source Serif 4 Variable", "Noto Serif SC"/);
  await panel.getByRole("radiogroup", { name: "标题字体" }).getByRole("radio", { name: "思源宋体" }).click();
  await expect.poll(() => style(preview, ".cm-md-h1", "font-family")).toMatch(/^"Noto Serif SC"/);

  // Any installed font: the menu lists this computer's fonts.
  const installed = panel.getByRole("combobox", { name: "正文字体：系统已安装字体" });
  await installed.focus();
  await expect.poll(() => installed.locator("option:not([disabled])").count()).toBeGreaterThan(0);
  const family = (await installed.locator("option:not([disabled])").first().getAttribute("value"))!;
  await installed.selectOption(family);
  await expect.poll(() => style(preview, ".cm-content", "font-family")).toContain(family);
  await expect(body.getByRole("radio", { checked: true })).toHaveCount(0);
  await app.close();
});

test("中英文自动间距 widens the gap between Chinese and Latin on screen only", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "雨后.md": note });
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "雨后");
  // The width of "了3" as drawn: wider when a gap is added between the Chinese and the digit.
  const gap = () =>
    page.getByRole("textbox", { name: "笔记正文" }).evaluate((content) => {
      const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const at = node.textContent!.indexOf("了3");
        if (at < 0) continue;
        const range = document.createRange();
        range.setStart(node, at);
        range.setEnd(node, at + 2);
        return range.getBoundingClientRect().width;
      }
      return -1;
    });
  const spaced = await gap();
  const panel = await openTypography(page);
  const autospace = panel.getByRole("switch", { name: "中英文自动间距" });
  await expect(autospace).toHaveAttribute("aria-checked", "true");
  await autospace.click();
  await expect(autospace).toHaveAttribute("aria-checked", "false");
  await expect.poll(gap).toBeLessThan(spaced);
  await app.close();
  expect(await readFile(join(root, "雨后.md"), "utf8")).toBe(note);
});

test("sliders set the size, leading, gap, measure and heading ratio; the preview follows with motion", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "雨后.md": note });
  const before = await readdir(root, { recursive: true });
  const first = await launchWith(scratch, root);
  await openNote(first.page, "雨后");
  const panel = await openTypography(first.page);

  // The defaults are the design system's 正文排版.
  const slider = (name: string) => panel.getByRole("slider", { name });
  await expect(slider("字号")).toHaveAttribute("aria-valuetext", "17px");
  await expect(slider("行距")).toHaveAttribute("aria-valuetext", "1.8");
  await expect(slider("段距")).toHaveAttribute("aria-valuetext", "0.9em");
  await expect(slider("版心宽度")).toHaveAttribute("aria-valuetext", "680px");
  await expect(slider("标题大小比例")).toHaveAttribute("aria-valuetext", "1.6");

  // The preview is the open note, set as it would be in the editor.
  const preview = panel.getByRole("figure", { name: "排版预览" });
  await expect(preview).toContainText("小路上的青苔很滑");
  await expect.poll(() => style(preview, ".cm-md-h1", "font-size")).toBe("34px");
  // It moves into new values rather than jumping: its text declares transitions for what the sliders change.
  const transitions = await style(preview, ".cm-scroller", "transition-property");
  for (const property of ["font-size", "line-height"]) expect(transitions).toContain(property);
  expect(await style(preview, ".cm-content", "transition-property")).toContain("max-width");

  await slider("字号").focus();
  await first.page.keyboard.press("ArrowRight");
  await first.page.keyboard.press("ArrowRight");
  await expect(slider("字号")).toHaveAttribute("aria-valuetext", "18px");
  await expect.poll(() => style(preview, ".cm-scroller", "font-size")).toBe("18px");
  // H1 = 字号 × 比例 × 1.25.
  await expect.poll(() => style(preview, ".cm-md-h1", "font-size")).toBe("36px");
  await slider("标题大小比例").focus();
  await first.page.keyboard.press("End");
  await expect(slider("标题大小比例")).toHaveAttribute("aria-valuetext", "2");
  await expect.poll(() => style(preview, ".cm-md-h1", "font-size")).toBe("45px");
  await slider("版心宽度").focus();
  await first.page.keyboard.press("Home");
  await expect.poll(() => style(preview, ".cm-content", "max-width")).toBe("480px");
  await slider("行距").focus();
  await first.page.keyboard.press("End");
  await expect.poll(() => style(preview, ".cm-scroller", "line-height")).toBe("39.6px");

  // The editor behind the panel takes the same values at once.
  await first.page.keyboard.press("Escape");
  const editor = first.page.locator(".editor").first();
  expect(await style(editor, ".cm-scroller", "font-size")).toBe("18px");
  expect(await style(editor, ".cm-content", "max-width")).toBe("480px");
  await first.app.close();

  // Kept with the app, not in the library, and the note is untouched.
  const again = await launch(scratch);
  await expect(again.page.getByRole("list", { name: "当前目录内容" })).toBeVisible();
  const reopened = await openTypography(again.page);
  await expect(reopened.getByRole("slider", { name: "字号" })).toHaveAttribute("aria-valuetext", "18px");
  await expect(reopened.getByRole("slider", { name: "版心宽度" })).toHaveAttribute("aria-valuetext", "480px");
  await again.app.close();
  expect(await readdir(root, { recursive: true })).toEqual(before);
  expect(await readFile(join(root, "雨后.md"), "utf8")).toBe(note);
});
