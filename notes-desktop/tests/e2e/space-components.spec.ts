import type { ElectronApplication, Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

// Space homepage components, style kit and interface names (ticket 20): the built app, a real
// temporary library, a homepage in its sandbox. Homepages written for the old app (lb-*) run as they are.

const sideTab = (page: Page, name: "资料库" | "空间") => page.getByRole("tablist", { name: "侧栏" }).getByRole("tab", { name });
const spaceList = (page: Page) => page.getByRole("list", { name: "空间", exact: true });

const training =
  "# 训练记录\n\n## 卧推\n| 日期 | 动作 | 重量 | 组数 |\n|---|---|---|---|\n| 2026-10-12 | 卧推 | 55 | 5 |\n| 2026-10-14 | 卧推 | 57.5 | 4 |\n| 2026-10-16 | 卧推 | 60 | 5 |\n";

async function spacePage(app: ElectronApplication, name: string): Promise<Page> {
  const find = async () => {
    for (const w of app.windows()) if (w.url().startsWith("notes-space:") && (await w.title().catch(() => "")) === name) return w;
    return null;
  };
  await expect.poll(find).not.toBeNull();
  return (await find())!;
}

async function openSpace(scratch: string, files: Record<string, string>, name: string) {
  const root = await library(scratch, "笔记库", files);
  const { app, page } = await launchWith(scratch, root);
  await sideTab(page, "空间").click();
  await spaceList(page).getByRole("button", { name }).click();
  return { root, app, page, home: await spacePage(app, name) };
}

const today = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

test("a homepage written for the old app runs unchanged: lb, lb-* components and --lb-* variables", async ({ scratch }) => {
  const legacy = await readFile(join(__dirname, "samples/legacy-homepage.html"), "utf8");
  const { root, app, home } = await openSpace(scratch, { "健身/训练记录.md": training, ".notes/空间/健身.html": legacy }, "健身");

  // Its own script, through lb: 3 records.
  await expect(home.locator("#streak")).toContainText("共 3 次");
  // The components draw the records.
  await expect(home.locator("lb-stat[op=max]")).toContainText("60");
  await expect(home.locator("lb-records")).toContainText("57.5");
  await expect(home.locator("lb-chart svg")).toHaveCount(1);
  await expect(home.locator("lb-calendar")).toContainText("最近");
  // The style kit under its old names.
  const card = home.locator(".lb-card").first();
  expect(await card.evaluate((el) => getComputedStyle(el).borderRadius)).not.toBe("0px");
  expect(await home.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--lb-chart-1").trim())).not.toBe("");

  // Quick entry writes the record to the Markdown.
  const add = home.locator("lb-quick-add");
  await add.getByLabel("重量").fill("62.5");
  await add.getByRole("button", { name: "记一组" }).click();
  await expect.poll(() => readFile(join(root, "健身/训练记录.md"), "utf8")).toContain(`| ${today()} | 卧推 | 62.5 | 5 |`);
  await app.close();
});
