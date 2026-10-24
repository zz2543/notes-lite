import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

/** Visible text measured in the real editor rather than its state. */
async function textBounds(page: Page, text: string) {
  return page.getByLabel("笔记正文").evaluate((editor, text) => {
    const nodes = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT);
    for (let node = nodes.nextNode(); node; node = nodes.nextNode()) {
      const at = node.textContent!.indexOf(text);
      if (at < 0) continue;
      const range = document.createRange();
      range.setStart(node, at);
      range.setEnd(node, at + text.length);
      const { left, right } = range.getBoundingClientRect();
      return { left, right };
    }
    throw new Error(`Text not found: ${text}`);
  }, text);
}

const cases = [
  ["bullet", "- 项目", "- 项目\n- 青"],
  ["numbered", "1. 项目", "1. 项目\n2. 青"],
  ["task", "- [ ] 项目", "- [ ] 项目\n- [ ] 青"],
  ["nested", "- 父\n  - 项目", "- 父\n  - 项目\n  - 青"],
] as const;

for (const [kind, source, saved] of cases) {
  test(`first pinyin in a continued ${kind} list grows right without moving its start left`, async ({ scratch }) => {
    const root = await library(scratch, "笔记库", { "清单.md": source });
    const { app, page } = await launchWith(scratch, root);
    await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: "清单", exact: true }).click();
    await expect(page.locator(".editor")).toHaveCSS("transform", "none");
    await page.keyboard.press("ControlOrMeta+End");
    const { left: start } = await textBounds(page, "项目");
    await page.keyboard.press("Enter");
    const cdp = await page.context().newCDPSession(page);
    let end = start;
    for (const text of ["q", "qi", "qing"]) {
      await cdp.send("Input.imeSetComposition", { text, selectionStart: text.length, selectionEnd: text.length });
      await expect.poll(async () => Math.abs((await textBounds(page, text)).left - start)).toBeLessThan(1);
      const bounds = await textBounds(page, text);
      expect(bounds.right).toBeGreaterThan(end);
      end = bounds.right;
    }
    await cdp.send("Input.insertText", { text: "青" });
    await cdp.detach();
    await expect.poll(() => readFile(join(root, "清单.md"), "utf8")).toBe(saved);
    expect(Math.abs((await textBounds(page, "青")).left - start)).toBeLessThan(1);
    await app.close();
  });
}
