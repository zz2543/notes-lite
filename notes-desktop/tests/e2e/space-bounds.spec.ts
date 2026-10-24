import type { ElectronApplication, Page } from "@playwright/test";
import { expect, launchWith, library, showSide, test } from "./fixtures";

/** Compare the visible slot in CSS pixels with Electron's native view in window DIPs. */
async function alignmentError(app: ElectronApplication, page: Page, zoom: number) {
  const slot = await page.getByRole("region", { name: "空间主页", exact: true }).boundingBox();
  if (!slot) return Infinity;
  const bounds = await app.evaluate(({ BrowserWindow, WebContentsView }) => {
    const main = BrowserWindow.getAllWindows()[0]!;
    const home = main.contentView.children.find((view) => view instanceof WebContentsView && view.webContents.getURL().startsWith("notes-space:"));
    return home?.getBounds();
  });
  if (!bounds) return Infinity;
  return Math.max(
    Math.abs(bounds.x - slot.x * zoom),
    Math.abs(bounds.y - slot.y * zoom),
    Math.abs(bounds.x + bounds.width - (slot.x + slot.width) * zoom),
    Math.abs(bounds.y + bounds.height - (slot.y + slot.height) * zoom),
  );
}

test("the native space page follows its slot at normal, enlarged and reduced page zoom", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "阅读/书单.md": "# 书单\n",
    ".notes/空间/阅读.html": '<meta name="space-scope" content="阅读"><h1>阅读</h1><div class="space-card">目标统计</div>',
  });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await page.getByRole("list", { name: "空间", exact: true }).getByRole("button", { name: "阅读" }).click();
  await expect(page.getByRole("region", { name: "空间标题" })).toBeVisible();
  for (const zoom of [1, 1.5, 0.8, 1]) {
    await app.evaluate(({ BrowserWindow }, zoom) => BrowserWindow.getAllWindows()[0]!.webContents.setZoomFactor(zoom), zoom);
    // Native bounds are integral DIPs, so rounding either edge may differ by at most one DIP.
    await expect.poll(() => alignmentError(app, page, zoom)).toBeLessThanOrEqual(1);
  }
  await app.close();
});
