import type { ElectronApplication, Page } from "@playwright/test";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { closeSettings, expect, launch, launchWith, library, openSettings, showSide, test } from "./fixtures";

// The space page loop (ticket 19), after the old SpaceWorkflowTests: the built app, a real
// temporary library, and the space homepage running in its own sandbox. Records the page writes
// reach the Markdown on disk and the operation log, and can be undone one by one.

const spaceList = (page: Page) => page.getByRole("list", { name: "空间", exact: true });

const training = "# 训练记录\n\n## 卧推\n| 日期 | 动作 | 重量 |\n|---|---|---|\n| 2026-10-12 | 卧推 | 55 |\n| 2026-10-14 | 卧推 | 57.5 |\n| 2026-10-16 | 卧推 | 60 |\n";

// A homepage as an agent might write one before the components exist: a count and a quick-entry form.
const homepage = `<meta name="lb-scope" content="健身">
<meta name="lb-icon" content="🏋️">
<p>训练 <span id="count">…</span> 次</p>
<form id="add"><input name="重量" aria-label="重量"><button>记一笔</button></form>
<script>
  window.visits = (window.visits || 0) + 1;
  const show = async () => {
    document.getElementById("count").textContent = (await lb.query("健身/训练记录.md#卧推")).length;
  };
  document.getElementById("add").addEventListener("submit", async (event) => {
    event.preventDefault();
    await lb.append("健身/训练记录.md#卧推", { 日期: lb.today(), 动作: "卧推", 重量: Number(event.target.重量.value) });
    event.target.reset();
    await show();
  });
  show();
</script>
`;

/** The page of the homepage of space `name`, found among the app's web contents by its address and title. */
async function spacePage(app: ElectronApplication, name: string): Promise<Page> {
  const find = async () => {
    for (const w of app.windows()) if (w.url().startsWith("notes-space:") && (await w.title().catch(() => "")) === name) return w;
    return null;
  };
  await expect.poll(find).not.toBeNull();
  return (await find())!;
}

/** How many homepages the window shows over its own page. */
// The main window's: 设置 may be open beside it.
const shownPages = (app: ElectronApplication) =>
  app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().find((w) => w.getTitle() !== "设置")!.contentView.children.length);

const today = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

test("a space homepage writes a record to the Markdown, logged and undone one by one", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "健身/训练记录.md": training,
    "健身/计划.md": "# 计划\n",
    "别处/秘密.md": "不在范围内",
    ".notes/空间/健身.html": homepage,
  });
  const note = join(root, "健身/训练记录.md");
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "健身" }).click();

  // The middle column holds 主页 and the notes in scope, nothing else.
  const contents = page.getByRole("list", { name: "空间内容" });
  await expect(contents.getByRole("button")).toHaveText(["主页", "计划", "训练记录"]);
  await expect(contents.getByRole("button", { name: "主页" })).toHaveAttribute("aria-current", "true");

  const home = await spacePage(app, "健身");
  await expect(home.getByText("训练 3 次")).toBeVisible();
  await home.getByLabel("重量").fill("65");
  await home.getByRole("button", { name: "记一笔" }).click();
  await expect(home.getByText("训练 4 次")).toBeVisible();
  await expect.poll(() => readFile(note, "utf8")).toContain(`| 60 |\n| ${today()} | 卧推 | 65 |\n`);

  // The operation log lists it; undoing takes back just that record.
  await home.getByLabel("重量").fill("70");
  await home.getByRole("button", { name: "记一笔" }).click();
  await expect.poll(() => readFile(note, "utf8")).toContain("| 卧推 | 70 |");
  await page.getByRole("button", { name: "操作记录" }).click();
  const log = page.getByRole("dialog", { name: "操作记录" });
  await expect(log.getByRole("listitem")).toHaveCount(2);
  await expect(log.getByRole("listitem").first()).toContainText(`新增记录 ${today()} · 卧推 · 70 → 健身/训练记录.md#卧推`);
  await expect(log.getByRole("listitem").first()).toContainText("健身");
  await log.getByRole("listitem").nth(1).getByRole("button", { name: "撤销" }).click();
  await expect.poll(() => readFile(note, "utf8")).not.toContain("| 卧推 | 65 |");
  expect(await readFile(note, "utf8")).toContain("| 卧推 | 70 |");
  await expect(log.getByRole("listitem").nth(1)).toContainText("已撤销");

  // A record changed since cannot be undone without overwriting it: the log says so.
  await writeFile(note, (await readFile(note, "utf8")).replace("| 卧推 | 70 |", "| 卧推 | 72.5 |"));
  await log.getByRole("listitem").first().getByRole("button", { name: "撤销" }).click();
  await expect(page.getByRole("alert")).toContainText("又被修改过");
  expect(await readFile(note, "utf8")).toContain("| 卧推 | 72.5 |");
  await log.getByRole("button", { name: "关闭" }).click();
  await expect(log).toHaveCount(0);
  await app.close();
});

test("the homepage runs sandboxed: no Node, no app interface, only its own scope", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "健身/训练记录.md": training,
    "别处/秘密.md": "不在范围内",
    ".notes/空间/健身.html": homepage,
    ".notes/空间/全局.html": '<meta name="lb-scope" content="*">\n<p id="global">全局主页</p>',
  });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "健身" }).click();
  const home = await spacePage(app, "健身");
  await expect(home.getByText("训练 3 次")).toBeVisible();

  expect(await home.evaluate(() => [typeof (window as { require?: unknown }).require, typeof (window as { process?: unknown }).process, typeof (window as { notes?: unknown }).notes])).toEqual([
    "undefined",
    "undefined",
    "undefined",
  ]);
  const refused = await home.evaluate(() => (window as unknown as { lb: { read(p: string): Promise<string> } }).lb.read("别处/秘密.md").catch((e: { code: string }) => e.code));
  expect(refused).toBe("outside-scope");
  // Embedded frames never get the interface.
  const framed = await home.evaluate(async () => {
    const frame = document.createElement("iframe");
    frame.srcdoc = "<p>x</p>";
    document.body.append(frame);
    await new Promise((resolve) => (frame.onload = resolve));
    return typeof (frame.contentWindow as unknown as { lb?: unknown }).lb;
  });
  expect(framed).toBe("undefined");
  // The page cannot navigate itself away.
  await home.evaluate(() => (location.href = "https://example.com/"));
  await page.waitForTimeout(300);
  expect(home.url()).toMatch(/^notes-space:/);

  // Each space keeps its own storage.
  await home.evaluate(() => localStorage.setItem("周期", "本周"));
  await spaceList(page).getByRole("button", { name: "全局" }).click();
  const global = await spacePage(app, "全局");
  await expect(global.getByText("全局主页")).toBeVisible();
  expect(await global.evaluate(() => localStorage.getItem("周期"))).toBeNull();
  await app.close();
});

test("a homepage's own storage stays with its space when the space is renamed, after a restart too", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/训练记录.md": training, ".notes/空间/健身.html": homepage });
  const first = await launchWith(scratch, root);
  await showSide(first.page, "空间");
  await spaceList(first.page).getByRole("button", { name: "健身" }).click();
  const home = await spacePage(first.app, "健身");
  await expect(home.getByText("训练 3 次")).toBeVisible();
  await home.evaluate(() => localStorage.setItem("周期", "本周"));

  await spaceList(first.page).getByRole("button", { name: "健身" }).click({ button: "right" });
  await first.page.getByRole("menuitem", { name: "编辑空间…" }).click();
  const edit = first.page.getByRole("dialog", { name: "编辑空间" });
  await edit.getByLabel("空间名称").fill("力量");
  await edit.getByRole("button", { name: "保存" }).click();
  await spaceList(first.page).getByRole("button", { name: "力量" }).click();
  const renamed = await spacePage(first.app, "力量");
  await expect(renamed.getByText("训练 3 次")).toBeVisible();
  expect(await renamed.evaluate(() => localStorage.getItem("周期"))).toBe("本周");
  await first.app.close();

  const { app, page } = await launch(scratch);
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "力量" }).click();
  const again = await spacePage(app, "力量");
  await expect(again.getByText("训练 3 次")).toBeVisible();
  expect(await again.evaluate(() => localStorage.getItem("周期"))).toBe("本周");
  await app.close();
});

test("a note in the space opens in the editor, and 主页 brings the same page back", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "健身/训练记录.md": training,
    "健身/计划.md": "# 计划\n",
    ".notes/空间/健身.html": homepage,
    ".notes/空间/空白.html": '<meta name="lb-scope" content="健身">\n',
  });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "健身" }).click();
  const home = await spacePage(app, "健身");
  await expect(home.getByText("训练 3 次")).toBeVisible();
  expect(await shownPages(app)).toBe(1);

  const contents = page.getByRole("list", { name: "空间内容" });
  await contents.getByRole("button", { name: "计划" }).click();
  await expect(page.getByRole("textbox", { name: "笔记正文" })).toContainText("计划");
  await expect.poll(() => shownPages(app)).toBe(0);

  await contents.getByRole("button", { name: "主页" }).click();
  await expect.poll(() => shownPages(app)).toBe(1);
  expect(await home.evaluate(() => (window as unknown as { visits: number }).visits), "the page kept its state").toBe(1);

  // A dialog over the window hides the homepage while it is open.
  await spaceList(page).getByRole("button", { name: "健身" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "编辑空间…" }).click();
  await expect.poll(() => shownPages(app)).toBe(0);
  await page.getByRole("dialog", { name: "编辑空间" }).getByRole("button", { name: "取消" }).click();
  await expect.poll(() => shownPages(app)).toBe(1);

  // A space without a homepage yet has 助手 write one; with no agent installed the prompt is copied.
  await spaceList(page).getByRole("button", { name: "空白" }).click();
  await expect.poll(() => shownPages(app)).toBe(0);
  await page.getByRole("region", { name: "空间标题" }).getByRole("button", { name: "让助手生成主页" }).click();
  await expect(page.getByRole("alert")).toContainText("提示词");
  await page.keyboard.press("ControlOrMeta+KeyJ");
  await page.getByRole("paragraph").filter({ hasText: "交给外部 agent" }).getByRole("button", { name: "复制提示词" }).click();
  await expect(page.getByRole("alert")).toContainText("提示词");
  expect(await app.evaluate(({ clipboard }) => clipboard.readText())).toContain("空白.html");

  // Back in 资料库, no homepage covers the editor.
  await spaceList(page).getByRole("button", { name: "健身" }).click();
  await expect.poll(() => shownPages(app)).toBe(1);
  await showSide(page, "资料库");
  await expect.poll(() => shownPages(app)).toBe(0);
  await app.close();
});

test("in 单栏导航 an open space shows 主页 and its notes under the spaces", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "健身/训练记录.md": training,
    "健身/计划.md": "# 计划\n",
    ".notes/空间/健身.html": homepage,
  });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "健身" }).click();
  const home = await spacePage(app, "健身");
  await expect(home.getByText("训练 3 次")).toBeVisible();
  await expect.poll(() => shownPages(app)).toBe(1);

  // 设置 is a window of its own: the homepage stays where it is meanwhile.
  const settings = await openSettings(app, page);
  await expect.poll(() => shownPages(app)).toBe(1);
  await settings.getByRole("radiogroup", { name: "导航模式" }).getByRole("radio", { name: "单栏" }).click();
  await closeSettings(app, settings);
  await expect(page.locator("section.list")).toHaveCount(0);

  const contents = page.getByRole("complementary").getByRole("list", { name: "空间内容" });
  await expect(contents.getByRole("button")).toHaveText(["主页", "计划", "训练记录"]);
  await expect.poll(() => shownPages(app)).toBe(1);
  await expect(home.getByText("训练 3 次")).toBeVisible();

  await contents.getByRole("button", { name: "计划" }).click();
  await expect(page.getByRole("textbox", { name: "笔记正文" })).toContainText("计划");
  await expect.poll(() => shownPages(app)).toBe(0);
  await contents.getByRole("button", { name: "主页" }).click();
  await expect.poll(() => shownPages(app)).toBe(1);
  await app.close();
});
