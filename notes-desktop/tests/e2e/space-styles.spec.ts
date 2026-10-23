import type { Page } from "@playwright/test";
import { expect, launchWith, library, showSide, test } from "./fixtures";

// 风格参考 (2026-10-23): a homepage written in a look paints its own page; the space card, title row
// included, takes the page's top colour and text colour. A homepage in the app's own style keeps the app's.

const spaceList = (page: Page) => page.getByRole("list", { name: "空间", exact: true });

const styled = `<meta name="space-scope" content="健身">
<meta name="space-icon" content="🏋️">
<style>
  html, body { background: radial-gradient(300px 120px at 20% 20%, rgba(255,255,255,.8), transparent 70%), linear-gradient(#8fbfe6, #cfe3dc); color: #1f2329; }
  .card { background: #fff; border-radius: 28px; padding: 26px 28px; font-family: Inter; }
</style>
<div class="card"><b>本周训练</b> 3 次</div>
`;

const plain = `<meta name="space-scope" content="读书">
<meta name="space-icon" content="📚">
<div class="space-card"><h2>读书</h2></div>
`;

test("a homepage in a look gives the title row its own colours; one in the app's style keeps the app's", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "健身/训练.md": "# 训练\n",
    "读书/书单.md": "# 书单\n",
    ".notes/空间/健身.html": styled,
    ".notes/空间/读书.html": plain,
  });
  const { page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  const card = page.locator('article.card[data-kind="space"]');
  const surface = () => card.evaluate((el) => (el as HTMLElement).style.getPropertyValue("--space-surface"));

  await spaceList(page).getByRole("button", { name: "健身" }).click();
  await expect.poll(surface).toBe("rgb(143, 191, 230)");
  expect(await card.evaluate((el) => (el as HTMLElement).style.getPropertyValue("--card-fg"))).toBe("rgb(31, 35, 41)");

  await spaceList(page).getByRole("button", { name: "读书" }).click();
  await expect(page.getByRole("heading", { name: "读书" }).first()).toBeVisible();
  await page.waitForTimeout(1200);
  expect(await surface()).toBe("");
});
