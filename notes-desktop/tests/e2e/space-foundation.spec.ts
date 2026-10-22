import type { ElectronApplication, Page } from "@playwright/test";
import { expect, launchWith, library, showSide, test } from "./fixtures";

// The design foundation for homepages: hues, card styles, ECharts served offline from the kit,
// the resolved theme, toasts, count-up numbers and space.open into the app.

const spaceList = (page: Page) => page.getByRole("list", { name: "空间", exact: true });

async function spacePage(app: ElectronApplication, name: string): Promise<Page> {
  const find = async () => {
    for (const w of app.windows()) if (w.url().startsWith("notes-space:") && (await w.title().catch(() => "")) === name) return w;
    return null;
  };
  await expect.poll(find).not.toBeNull();
  return (await find())!;
}

const homepage = `<meta name="space-scope" content="健身">
<div class="space-bento">
  <div class="space-glow space-m" data-hue="red" id="glow"><div class="space-label">本月</div><div class="space-big" id="count" data-space-count="12">0</div></div>
  <div class="space-tint" data-hue="teal" id="tint"><button id="open-plan">计划</button></div>
  <div class="space-card space-full"><div id="trend" style="height:200px"></div></div>
</div>
<script>
  window.chartReady = space.chart("#trend", (t) => ({ xAxis: { type: "category", data: ["一", "二", "三"] }, yAxis: {}, series: [{ type: "line", data: [1, 3, 2], color: t.hues.blue.color }] })).then(() => true);
  document.getElementById("open-plan").onclick = () => space.open("健身/计划.md");
</script>
`;

test("a homepage draws with the foundation: hues, glow cards, an offline chart, theme, toast and count-up", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/计划.md": "# 计划\n\n周三练腿\n", ".notes/空间/健身.html": homepage });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "健身" }).click();
  const home = await spacePage(app, "健身");

  // Glow card: a dark coloured base and light text, whatever the app's scheme.
  const glow = home.locator("#glow");
  const bg = await glow.evaluate((el) => getComputedStyle(el).backgroundColor + " " + getComputedStyle(el).backgroundImage);
  expect(bg).not.toMatch(/^rgba\(0, 0, 0, 0\) none$/);
  expect(await home.locator("#tint").evaluate((el) => getComputedStyle(el).backgroundColor)).not.toBe("rgba(0, 0, 0, 0)");
  // The number counts up to its value.
  await expect(home.locator("#count")).toHaveText("12");

  // ECharts comes from the kit, offline, and draws a canvas.
  expect(await home.evaluate(() => (window as unknown as { chartReady: Promise<boolean> }).chartReady)).toBe(true);
  await expect(home.locator("#trend canvas").first()).toBeVisible();

  // The theme resolves to colours the page can hand to anything.
  const theme = await home.evaluate(() => {
    const t = (window as unknown as { space: { theme(): { accent: string; hues: Record<string, { color: string }>; chart: string[] } } }).space.theme();
    return { accent: t.accent, red: t.hues.red!.color, chart: t.chart.length };
  });
  expect(theme.accent).toMatch(/^rgba?\(/);
  expect(theme.red).toMatch(/^rgba?\(/);
  expect(theme.chart).toBeGreaterThan(3);

  // A toast with an action.
  await home.evaluate(() => {
    (window as unknown as { space: { toast(m: string, o: object): void } }).space.toast("已删除 1 条", { action: "撤销", onAction: () => ((window as unknown as { undone: boolean }).undone = true) });
  });
  await expect(home.getByText("已删除 1 条")).toBeVisible();
  await home.getByRole("button", { name: "撤销" }).click();
  expect(await home.evaluate(() => (window as unknown as { undone?: boolean }).undone)).toBe(true);

  // space.open opens the note in the app.
  await home.locator("#open-plan").click();
  await expect(page.getByRole("textbox", { name: "笔记正文" })).toContainText("周三练腿");
  await app.close();
});
