import type { ElectronApplication, Page } from "@playwright/test";
import { readdir } from "node:fs/promises";
import { join } from "node:path";
import { installFakeAgent } from "../support/fakeAgent";
import { expect, launchWith, library, showSide, test } from "./fixtures";

// 空间外壳、样式基础与示例空间 (ticket 31): the built app, a real temporary library, the homepage in
// its sandbox. The title area over the homepage, the style kit's cards, grey text and scroll bar, and
// 新建示例空间.

const spaceList = (page: Page) => page.getByRole("list", { name: "空间", exact: true });

async function spacePage(app: ElectronApplication, name: string): Promise<Page> {
  const find = async () => {
    for (const w of app.windows()) if (w.url().startsWith("notes-space:") && (await w.title().catch(() => "")) === name) return w;
    return null;
  };
  await expect.poll(find).not.toBeNull();
  return (await find())!;
}

test("新建示例空间, from the empty list or the menu beside 新建空间, makes 组件示例 with its notes and a homepage already drawn", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/今天.md": "今天" });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");

  await page.getByRole("button", { name: "新建示例空间" }).click();
  await expect(spaceList(page).getByRole("button")).toHaveText(["🧩组件示例"]);
  await expect(spaceList(page).getByRole("button", { name: "组件示例" })).toHaveAttribute("aria-current", "true");
  await expect(page.getByRole("list", { name: "空间内容" }).getByRole("button")).toHaveText(["主页", "待办清单", "读书进度", "健身记录", "专注时长"]);
  const home = await spacePage(app, "组件示例");
  await expect(home.locator("space-stat").first()).toContainText(/\d/);
  await expect(home.locator("space-chart svg").first()).toBeVisible();
  // Written by the app: 助手 is not asked for it.
  await expect(page.getByRole("complementary", { name: "助手栏", includeHidden: true })).toHaveAttribute("aria-hidden", "true");

  // A card's markup, copied from under it.
  await home.getByRole("button", { name: "复制写法" }).first().click();
  await expect.poll(() => app.evaluate(({ clipboard }) => clipboard.readText())).toContain("<space-stat ");
  await expect(home.getByRole("button", { name: "已复制" })).toHaveCount(1);

  // Again from the menu beside 新建空间: the next free name.
  await page.getByRole("button", { name: "更多新建方式" }).click();
  await page.getByRole("menuitem", { name: "新建示例空间" }).click();
  await expect(spaceList(page).getByRole("button")).toHaveText(["🧩组件示例", "🧩组件示例 2"]);
  expect((await readdir(root)).sort()).toEqual(["组件示例", "组件示例 2", ".notes", "日记"].sort());
  await app.close();
});

const training = "## 卧推\n\n| 日期 | 重量 |\n|---|---|\n| 2026-10-18 | 60 |\n";
const homepage = '<meta name="space-scope" content="健身, 日记">\n<meta name="space-icon" content="🏋️">\n<div class="space-card"><p class="space-muted">本周</p><space-stat source="健身/训练.md#卧推" op="count" label="训练"></space-stat></div>\n';

test("the title area over a homepage shows its icon, name and scope, with 让助手修改, 复制提示词 and 查看源码", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/训练.md": training, "日记/今天.md": "今天", ".notes/空间/健身.html": homepage });
  await installFakeAgent(join(scratch, "agents"), "claude", { session: "s-1", steps: [{ say: "好的。" }] });
  const { app, page } = await launchWith(scratch, root);
  await app.evaluate(({ shell }) => {
    const shown: string[] = [];
    (globalThis as { shown?: string[] }).shown = shown;
    shell.showItemInFolder = (path) => void shown.push(path);
  });
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "健身" }).click();

  const title = page.getByRole("region", { name: "空间标题" });
  await expect(title.getByRole("heading", { level: 1 })).toHaveText("🏋️健身");
  await expect(title).toContainText("范围：健身/、日记/");

  await title.getByRole("button", { name: "复制提示词" }).click();
  await expect.poll(() => app.evaluate(({ clipboard }) => clipboard.readText())).toContain("请为笔记应用编写“健身”空间的空间主页。");

  await title.getByRole("button", { name: "查看源码" }).click();
  await expect.poll(() => app.evaluate(() => (globalThis as { shown?: string[] }).shown)).toEqual([join(root, ".notes", "空间", "健身.html")]);

  // 让助手修改: the column opens on its message field; the open space goes with what is asked.
  await title.getByRole("button", { name: "让助手修改" }).click();
  await expect(page.getByRole("complementary", { name: "助手栏" })).toHaveAttribute("aria-hidden", "false");
  await expect(page.getByRole("textbox", { name: "给助手的消息" })).toBeFocused();
  await app.close();
});

test("a whole-library space's title says so", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { ".notes/空间/全局.html": '<meta name="space-scope" content="*">\n<p>主页</p>\n' });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "全局" }).click();
  await expect(page.getByRole("region", { name: "空间标题" })).toContainText("范围：整个笔记库");
  await app.close();
});

// Relative luminance and contrast, WCAG's way, of two computed rgb() colours.
function contrast(a: string, b: string): number {
  const lum = (c: string) => {
    const [r = 0, g = 0, b = 0] = (c.match(/[\d.]+/g) ?? []).slice(0, 3).map((v) => {
      const x = Number(v) / 255;
      return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const hi = Math.max(lum(a), lum(b));
  const lo = Math.min(lum(a), lum(b));
  return (hi + 0.05) / (lo + 0.05);
}

test("the style kit: cards without an outline, a shadow in light and a fine edge in dark, grey text at 4.5:1, a thin scroll bar", async ({ scratch }) => {
  const page0 = '<div class="space-card"><p class="space-muted">灰字</p></div>\n<p class="space-muted">页面上的灰字</p>\n';
  const root = await library(scratch, "笔记库", { ".notes/空间/样式.html": '<meta name="space-scope" content="*">\n' + page0 });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "样式" }).click();
  const home = await spacePage(app, "样式");
  await expect(home.locator(".space-card")).toBeVisible();

  const look = () =>
    home.evaluate(() => {
      const card = getComputedStyle(document.querySelector(".space-card")!);
      const html = getComputedStyle(document.documentElement);
      // color-mix() resolves to color(srgb …); a probe turns any colour into rgb().
      const rgb = (c: string) => {
        const probe = document.createElement("canvas").getContext("2d")!;
        probe.fillStyle = c;
        probe.fillRect(0, 0, 1, 1);
        const [r, g, b] = probe.getImageData(0, 0, 1, 1).data;
        return `rgb(${r}, ${g}, ${b})`;
      };
      return {
        border: card.borderTopWidth,
        shadow: card.boxShadow,
        widget: rgb(card.backgroundColor),
        surface: rgb(getComputedStyle(document.body).backgroundColor),
        mutedOnCard: rgb(getComputedStyle(document.querySelector(".space-card .space-muted")!).color),
        mutedOnPage: rgb(getComputedStyle(document.querySelector("body > .space-muted")!).color),
        scrollbarWidth: html.scrollbarWidth,
        scrollbarColor: html.scrollbarColor,
      };
    });

  for (const scheme of ["light", "dark"] as const) {
    await home.emulateMedia({ colorScheme: scheme });
    const s = await look();
    expect(s.border).toBe("0px");
    expect(s.shadow).not.toBe("none");
    if (scheme === "dark") expect(s.shadow).toContain("inset");
    else expect(s.shadow).not.toContain("inset");
    expect(s.widget).not.toBe(s.surface);
    expect(contrast(s.mutedOnCard, s.widget)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(s.mutedOnPage, s.surface)).toBeGreaterThanOrEqual(4.5);
    expect(s.scrollbarWidth).toBe("thin");
    expect(s.scrollbarColor).not.toBe("auto");
  }
  await app.close();
});
