import type { ElectronApplication, Page } from "@playwright/test";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

// Ticket 13: ⌘ / Ctrl-click follows links; images and attachments imported (pasted, dropped, chosen from the
// menu) into 附件 and linked relative to the note; images shown in place and opened with a double click;
// links that lead nowhere say so. The note's file holds exactly the Markdown.

const editor = (page: Page) => page.getByLabel("笔记正文");
// A 2 × 2 PNG.
const png = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==",
  "base64",
);

async function openNote(page: Page, title: string) {
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
  await expect(editor(page)).toBeFocused();
}

/** What the app hands the system to open, instead of opening it. */
async function catchOpened(app: ElectronApplication) {
  await app.evaluate(({ shell }) => {
    const opened: string[] = [];
    (globalThis as { opened?: string[] }).opened = opened;
    shell.openPath = async (path) => (opened.push(path), "");
    shell.openExternal = async (url) => void opened.push(url);
  });
  return () => app.evaluate(() => (globalThis as { opened?: string[] }).opened ?? []);
}

test("⌘ / Ctrl-click follows a link to a note or a web page; a plain click edits; a missing note says so", async ({ scratch }) => {
  const source = "# 入口\n\n见 [[阅读/摘记|读书摘记]] 和 [[不存在]]。\n\n[网页](https://example.com/页)";
  const root = await library(scratch, "笔记库", { "入口.md": source, "阅读/摘记.md": "# 摘记\n\n内容" });
  const { app, page } = await launchWith(scratch, root);
  const opened = await catchOpened(app);
  await openNote(page, "入口");
  await page.keyboard.press("ControlOrMeta+End");

  // Typeset as links: the alias alone, in the accent colour.
  const link = editor(page).locator(".cm-md-link", { hasText: "读书摘记" });
  await expect(link).toHaveText("读书摘记");
  await expect(editor(page)).not.toContainText("阅读/摘记|");

  // A plain click only places the caret: the link's Markdown shows on that line, nothing opens.
  await link.click();
  await expect(editor(page)).toContainText("[[阅读/摘记|读书摘记]]");
  await expect(page.locator(".card-path")).toHaveText("入口.md");

  await page.keyboard.press("ControlOrMeta+End");
  await link.click({ modifiers: ["ControlOrMeta"] });
  await expect(page.locator(".card-path")).toHaveText("阅读 / 摘记.md");
  await expect(editor(page)).toContainText("内容");

  await page.getByRole("tree").getByRole("treeitem", { name: "笔记库" }).click();
  await openNote(page, "入口");
  await page.keyboard.press("ControlOrMeta+End");
  await editor(page).locator(".cm-md-link", { hasText: "不存在" }).click({ modifiers: ["ControlOrMeta"] });
  await expect(page.getByRole("alert")).toHaveText("找不到笔记“不存在”。");
  await expect(page.locator(".card-path")).toHaveText("入口.md");

  await editor(page).locator(".cm-md-link", { hasText: "网页" }).click({ modifiers: ["ControlOrMeta"] });
  await expect.poll(opened).toEqual(["https://example.com/页"]);
  expect(await readFile(join(root, "入口.md"), "utf8")).toBe(source);
  await app.close();
});

test("a pasted image goes into 附件, takes the selection's place and shows in the note; a double click opens it", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/今天.md": "# 今天\n\n拍了一张：待补" });
  const { app, page } = await launchWith(scratch, root);
  const opened = await catchOpened(app);
  await page.getByRole("button", { name: "日记", exact: true }).click();
  await openNote(page, "今天");
  await page.keyboard.press("ControlOrMeta+End");
  // The selection the image replaces.
  await page.keyboard.press("Shift+ArrowLeft");
  await page.keyboard.press("Shift+ArrowLeft");

  await editor(page).evaluate((content, bytes) => {
    const data = new DataTransfer();
    data.items.add(new File([new Uint8Array(bytes)], "image.png", { type: "image/png" }));
    content.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
  }, [...png]);

  // Named as the old app named pasted pictures, on a line of its own, linked from the note's folder.
  await expect.poll(() => readdir(join(root, "附件"))).toEqual([expect.stringMatching(/^图片-[0-9a-f]{8}\.png$/)]);
  const [name] = await readdir(join(root, "附件"));
  expect(await readFile(join(root, "附件", name!))).toEqual(png);
  await expect.poll(() => readFile(join(root, "日记/今天.md"), "utf8")).toBe(`# 今天\n\n拍了一张：\n![${name}](../附件/${name})`);

  // The caret is on its line: the Markdown shows, the picture below it.
  const image = editor(page).locator(".cm-md-image img");
  await expect(image).toBeVisible();
  await expect(editor(page)).toContainText(`![${name}](../附件/${name})`);
  expect(await image.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(2);

  // Elsewhere, only the picture.
  await page.keyboard.press("ArrowUp");
  await expect(editor(page)).not.toContainText("../附件/");
  await expect(image).toBeVisible();

  await image.dblclick();
  await expect.poll(opened).toEqual([join(root, "附件", name!)]);
  await app.close();
});

test("a dropped file is linked where it lands and opens with ⌘ / Ctrl-click; a missing image says so", async ({ scratch }) => {
  const source = "# 资料\n\n![丢了](../附件/丢了.png)\n\n结尾";
  const root = await library(scratch, "笔记库", { "项目/资料.md": source });
  const { app, page } = await launchWith(scratch, root);
  const opened = await catchOpened(app);
  await page.getByRole("button", { name: "项目", exact: true }).click();
  await openNote(page, "资料");
  await page.keyboard.press("ControlOrMeta+End");

  await expect(editor(page).locator(".cm-md-image")).toHaveText("找不到附件“../附件/丢了.png”。");

  const end = await editor(page).getByText("结尾").boundingBox();
  await editor(page).evaluate((content, { x, y }) => {
    const data = new DataTransfer();
    data.items.add(new File(["%PDF"], "报告 终稿.pdf", { type: "application/pdf" }));
    for (const type of ["dragenter", "dragover", "drop"]) {
      content.dispatchEvent(new DragEvent(type, { dataTransfer: data, clientX: x, clientY: y, bubbles: true, cancelable: true }));
    }
  }, { x: end!.x + end!.width + 2, y: end!.y + end!.height / 2 });

  const linked = "[报告 终稿.pdf](../附件/报告%20终稿.pdf)";
  await expect.poll(() => readFile(join(root, "项目/资料.md"), "utf8")).toBe(`${source}\n${linked}`);
  expect(await readFile(join(root, "附件/报告 终稿.pdf"), "utf8")).toBe("%PDF");

  await page.keyboard.press("ArrowUp");
  await editor(page).locator(".cm-md-link", { hasText: "报告 终稿.pdf" }).click({ modifiers: ["ControlOrMeta"] });
  await expect.poll(opened).toEqual([join(root, "附件/报告 终稿.pdf")]);
  await app.close();
});

test("笔记 › 导入图片或附件… copies the chosen files in and links them at the caret", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "清单.md": "第一行\n第二行" });
  const outside = join(scratch, "外面");
  await library(scratch, "外面", { "说明.txt": "说明" });
  await writeFile(join(outside, "图.png"), png);
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "清单");
  await page.keyboard.press("ControlOrMeta+Home");
  await page.keyboard.press("End");

  await app.evaluate(({ dialog }, paths) => {
    dialog.showOpenDialog = (async () => ({ canceled: false, filePaths: paths })) as typeof dialog.showOpenDialog;
  }, [join(outside, "图.png"), join(outside, "说明.txt")]);
  await app.evaluate(({ Menu }) => Menu.getApplicationMenu()!.getMenuItemById("import-attachments")!.click());

  await expect.poll(() => readFile(join(root, "清单.md"), "utf8")).toBe("第一行\n![图.png](附件/图.png)\n[说明.txt](附件/说明.txt)\n第二行");
  expect(await readFile(join(root, "附件/图.png"))).toEqual(png);
  await expect(editor(page).locator(".cm-md-image img")).toBeVisible();
  await app.close();
});
