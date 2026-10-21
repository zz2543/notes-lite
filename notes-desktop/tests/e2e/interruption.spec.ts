import { expect, launchWith, library, test } from "./fixtures";

// Interrupted motion (ticket 23): whatever is asked again mid-way ends as last asked, never after a queue.

test("panels opened and shut in quick succession end as last asked, with nothing left queued", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "# 一", "二.md": "# 二", "三.md": "# 三" });
  const { app, page } = await launchWith(scratch, root);
  const list = page.getByRole("list", { name: "当前目录内容" });

  // Notes switched faster than any transition: the last one is open.
  for (const name of ["一", "二", "三", "二"]) await list.getByRole("button", { name }).click();
  await expect(page.getByLabel("笔记标题")).toHaveValue("二");
  await expect(page.getByLabel("笔记正文")).toContainText("二");

  // 助手栏, ⌘J three times: open, its width the design system's.
  const column = page.getByRole("complementary", { name: "助手栏" });
  for (let i = 0; i < 3; i += 1) await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(column).toBeVisible();
  await expect.poll(async () => (await column.boundingBox())?.width).toBeGreaterThanOrEqual(300);
  // And three more: shut.
  for (let i = 0; i < 3; i += 1) await page.keyboard.press("ControlOrMeta+KeyJ");
  await expect(column).toBeHidden();

  // 设置, opened, shut and opened again at once: one panel, fully in place.
  await page.keyboard.press("ControlOrMeta+Comma");
  await page.keyboard.press("Escape");
  await page.keyboard.press("ControlOrMeta+Comma");
  const panel = page.getByRole("dialog", { name: "设置" });
  await expect(panel).toHaveCount(1);
  await expect.poll(() => panel.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).a)).toBe(1);
  await page.keyboard.press("Escape");
  await expect(panel).toHaveCount(0);

  // 专注模式 in and out at once: out, the columns back.
  await page.getByLabel("笔记正文").click();
  await page.keyboard.press("ControlOrMeta+Shift+KeyF");
  await page.keyboard.press("ControlOrMeta+Shift+KeyF");
  await expect(page.getByRole("button", { name: "退出专注" })).toHaveCount(0);
  await expect(list).toBeVisible();
  await expect.poll(() => list.evaluate((el) => getComputedStyle(el.closest("section.list")!).opacity)).toBe("1");
  await app.close();
});
