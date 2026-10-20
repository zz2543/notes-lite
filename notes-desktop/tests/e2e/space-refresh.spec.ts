import type { ElectronApplication, Page } from "@playwright/test";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

// Space homepages stay current and say when they break (ticket 21): the built app, a real temporary
// library, a homepage in its sandbox. Changes to notes in scope reach `space.on("change")` and the
// components whoever made them; a rewritten space file shows at once; errors show in a bar above the page.

const sideTab = (page: Page, name: "资料库" | "空间") => page.getByRole("tablist", { name: "侧栏" }).getByRole("tab", { name });
const spaceList = (page: Page) => page.getByRole("list", { name: "空间", exact: true });

const training = "# 训练记录\n\n## 卧推\n| 日期 | 动作 | 重量 |\n|---|---|---|\n| 2026-10-12 | 卧推 | 55 |\n| 2026-10-14 | 卧推 | 57.5 |\n\n备注\n";

// Counts the records through its own script and through a component, and keeps what change told it.
const homepage = `<meta name="space-scope" content="健身">
<p id="count">…</p>
<p id="heard"></p>
<space-stat id="stat" source="健身/训练记录.md#卧推" op="count" label="次数"></space-stat>
<space-quick-add target="健身/训练记录.md#卧推" defaults='{"动作":"卧推"}' fields="日期, 重量" label="记一笔"></space-quick-add>
<script>
  window.heard = [];
  const show = async () => (document.getElementById("count").textContent = "训练 " + (await space.query("健身/训练记录.md#卧推")).length + " 次");
  space.on("change", (paths) => {
    window.heard.push(paths);
    document.getElementById("heard").textContent = paths.join(",");
    show();
  });
  show();
</script>
`;

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

test("changes to notes in scope refresh the homepage, whether another program, the editor or the page made them", async ({ scratch }) => {
  const { root, app, page, home } = await openSpace(
    scratch,
    { "健身/训练记录.md": training, "别处/秘密.md": "不在范围内", ".notes/空间/健身.html": homepage },
    "健身",
  );
  const note = join(root, "健身/训练记录.md");
  await expect(home.locator("#count")).toHaveText("训练 2 次");
  await expect(home.locator("#stat")).toContainText("2");

  // Another program adds a row: the page's own script and the component both redraw.
  await writeFile(note, training.replace("| 57.5 |\n", "| 57.5 |\n| 2026-10-16 | 卧推 | 60 |\n"));
  await expect(home.locator("#count")).toHaveText("训练 3 次");
  await expect(home.locator("#stat")).toContainText("3");
  await expect(home.locator("#heard")).toContainText("健身/训练记录.md");

  // A note outside the scope is none of the page's business.
  const heardBefore = await home.evaluate(() => (window as unknown as { heard: unknown[] }).heard.length);
  await writeFile(join(root, "别处/秘密.md"), "改过");
  // Something the page does hear, written after, proves the outside change went by unheard.
  await writeFile(join(root, "健身/计划.md"), "# 计划\n");
  await expect(home.locator("#heard")).toContainText("健身/计划.md");
  const heard = await home.evaluate((n) => (window as unknown as { heard: string[][] }).heard.slice(n).flat(), heardBefore);
  expect(heard).not.toContain("别处/秘密.md");

  // The editor saves a change: heard too, while the homepage waits behind the note.
  await page.getByRole("list", { name: "空间内容" }).getByRole("button", { name: "训练记录" }).click();
  const editor = page.getByLabel("笔记正文");
  await editor.click();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("：周三");
  await expect.poll(() => readFile(note, "utf8")).toContain("：周三");
  await expect.poll(() => home.evaluate(() => (window as unknown as { heard: string[][] }).heard.at(-1))).toContain("健身/训练记录.md");
  await page.getByRole("list", { name: "空间内容" }).getByRole("button", { name: "主页" }).click();

  // The page writes a record: its component redraws, and the app says the homepage wrote.
  const add = home.locator("space-quick-add");
  await add.getByLabel("重量").fill("62.5");
  await add.getByRole("button", { name: "记一笔" }).click();
  await expect(home.locator("#count")).toHaveText("训练 4 次");
  await expect(home.locator("#stat")).toContainText("4");
  const notice = page.getByRole("status", { name: "主页写入" });
  await expect(notice).toContainText("主页刚修改了 1 条记录");
  await notice.getByRole("button", { name: "查看" }).click();
  await expect(page.getByRole("dialog", { name: "操作记录" }).getByRole("listitem")).toHaveCount(1);
  await app.close();
});

test("an agent rewriting the space file shows the new homepage at once", async ({ scratch }) => {
  const { root, app, home } = await openSpace(scratch, { "健身/训练记录.md": training, ".notes/空间/健身.html": homepage }, "健身");
  await expect(home.locator("#count")).toHaveText("训练 2 次");
  await writeFile(join(root, ".notes/空间/健身.html"), '<meta name="space-scope" content="健身">\n<h1 id="new">新主页</h1>\n');
  await expect(home.locator("#new")).toHaveText("新主页");
  await app.close();
});

test("errors on the page show in a bar above it, ready to copy to an agent", async ({ scratch }) => {
  const broken = `<meta name="space-scope" content="健身">
<p>主页</p>
<script>
  showChart();
</script>
`;
  const { root, app, page, home } = await openSpace(scratch, { "健身/训练记录.md": training, ".notes/空间/健身.html": broken }, "健身");
  await expect(home.getByText("主页")).toBeVisible();

  const bar = page.getByRole("alert", { name: "主页出错了" });
  await expect(bar).toContainText("showChart is not defined");
  await expect(bar).toContainText("空间文件第 4 行");
  // It opens on 展开 and settles fully shown, pushing the page down rather than covering it.
  const frame = page.locator(".space-bar-frame").filter({ has: bar });
  await expect(frame).toHaveCSS("opacity", "1");
  const [barBox, slotBox] = await Promise.all([frame.boundingBox(), page.getByRole("region", { name: "空间主页" }).boundingBox()]);
  expect(slotBox!.y).toBeGreaterThanOrEqual(barBox!.y + barBox!.height);
  await bar.getByRole("button", { name: "复制错误给 agent" }).click();
  await expect(bar.getByRole("button", { name: "已复制" })).toBeVisible();
  const report = await app.evaluate(({ clipboard }) => clipboard.readText());
  expect(report).toContain("空间“健身”的主页出错了。");
  expect(report).toContain(join(root, ".notes", "空间", "健身.html"));
  expect(report).toContain("编写说明");

  // Closed, it stays closed until something else goes wrong: a resource that fails to load.
  await bar.getByRole("button", { name: "关闭错误提示" }).click();
  await expect(bar).toHaveCount(0);
  await home.evaluate(() => {
    const image = document.createElement("img");
    image.src = "notes-space://page/没有这张图.png";
    document.body.append(image);
  });
  await expect(bar).toContainText("资源加载失败");
  await expect(bar).toContainText("没有这张图.png");

  // A component refused its table (outside the scope) says so in the bar too.
  await writeFile(join(root, ".notes/空间/健身.html"), '<meta name="space-scope" content="健身">\n<space-stat source="别处/秘密.md" op="count"></space-stat>\n');
  await expect(bar).toContainText("space-stat");

  // Fixed by the agent: the new page loads, and the bar goes with the old one.
  await writeFile(join(root, ".notes/空间/健身.html"), '<meta name="space-scope" content="健身">\n<h1 id="fixed">修好了</h1>\n');
  await expect(home.locator("#fixed")).toBeVisible();
  await expect(bar).toHaveCount(0);
  await app.close();
});
