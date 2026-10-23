import type { ElectronApplication, Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, showSide, test } from "./fixtures";

// Space homepage components, style kit and interface names (ticket 20): the built app, a real
// temporary library, a homepage in its sandbox. Homepages written for the old app (lb-*) run as they are.

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
  await showSide(page, "空间");
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
  const card = home.locator("#week-card");
  expect(await card.evaluate((el) => getComputedStyle(el).borderRadius)).not.toBe("0px");
  expect(await home.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--lb-chart-1").trim())).not.toBe("");

  // Quick entry writes the record to the Markdown.
  const add = home.locator("lb-quick-add");
  await add.getByLabel("重量").fill("62.5");
  await add.getByRole("button", { name: "记一组" }).click();
  await expect.poll(() => readFile(join(root, "健身/训练记录.md"), "utf8")).toContain(`| ${today()} | 卧推 | 62.5 | 5 |`);
  await app.close();
});

// A homepage on the new names only.
const homepage = `<meta name="space-scope" content="健身">
<meta name="space-icon" content="🏋️">
<h1>健身</h1>
<div class="space-grid">
  <div class="space-card" id="record-card"><space-stat source="健身/训练记录.md#卧推" op="max" field="重量" label="卧推纪录" unit="kg"></space-stat></div>
  <div class="space-card"><space-stat source="健身/训练记录.md#卧推" op="sum" field="组数" label="总组数" unit="组"></space-stat></div>
</div>
<div class="space-card"><space-chart source="健身/训练记录.md#卧推" x="日期" y="重量" title="卧推重量"></space-chart></div>
<div class="space-card"><space-calendar source="健身/训练记录.md#卧推" label="打卡"></space-calendar></div>
<div class="space-card"><space-records source="健身/训练记录.md#卧推" limit="2" fields="日期, 重量" title="最近训练"></space-records></div>
<div class="space-card"><space-quick-add target="健身/训练记录.md#卧推" defaults='{"动作":"卧推","组数":3}' label="记一组"></space-quick-add></div>
<p id="mine"></p>
<script>
  space.query("健身/训练记录.md#卧推").then((rows) => (document.getElementById("mine").textContent = "自己写的 " + rows.length + " 条"));
</script>
`;

const rootStyle = (home: Page, name: string) => home.evaluate((n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), name);
/** A colour as the page resolves it, written as rgb(…). */
const resolved = (home: Page, value: string) =>
  home.evaluate((v) => {
    const probe = document.createElement("i");
    probe.style.color = v;
    document.body.append(probe);
    const colour = getComputedStyle(probe).color;
    probe.remove();
    return colour;
  }, value);

test("the five components, the space interface and the style kit under the new names", async ({ scratch }) => {
  const { root, app, home } = await openSpace(scratch, { "健身/训练记录.md": training, ".notes/空间/健身.html": homepage }, "健身");

  await expect(home.locator("#mine")).toHaveText("自己写的 3 条");
  expect(await home.evaluate(() => (window as unknown as { space: unknown; lb: unknown }).space === (window as unknown as { lb: unknown }).lb)).toBe(true);
  await expect(home.locator("space-stat[op=max]")).toContainText("60");
  await expect(home.locator("space-stat[op=sum]")).toContainText("14");
  await expect(home.locator("space-chart svg")).toHaveAttribute("aria-label", "卧推重量");
  await expect(home.locator("space-calendar")).toContainText("天");
  await expect(home.locator("space-records li")).toHaveCount(2);
  await expect(home.locator("space-records li").first()).toContainText("2026-10-16");

  // The kit is the app's design system (组件 2.0): widgets the note card's colour on a page a shade off
  // it, the widget radius, the notes' typography.
  expect(await resolved(home, "var(--space-card)")).toBe("rgb(255, 255, 255)");
  expect(await resolved(home, "var(--space-bg)")).not.toBe("rgb(255, 255, 255)");
  expect(await resolved(home, "var(--space-text)")).toBe("rgb(29, 29, 31)");
  expect(await rootStyle(home, "--space-radius")).toBe("18px");
  const card = home.locator("#record-card");
  expect(await card.evaluate((el) => getComputedStyle(el).borderRadius)).toBe("18px");
  expect(await home.evaluate(() => getComputedStyle(document.body).fontSize)).toBe("17px");

  const add = home.locator("space-quick-add");
  await expect(add.getByLabel("日期")).toHaveValue(today());
  await add.getByLabel("重量").fill("62.5");
  await add.getByRole("button", { name: "记一组" }).click();
  await expect.poll(() => readFile(join(root, "健身/训练记录.md"), "utf8")).toContain(`| ${today()} | 卧推 | 62.5 | 3 |`);
  await app.close();
});

test("cards enter on the 浮现 spring one after another, and settle with nothing left applied", async ({ scratch }) => {
  const { app, home } = await openSpace(scratch, { "健身/训练记录.md": training, ".notes/空间/健身.html": homepage }, "健身");
  await expect(home.locator("space-stat[op=max]")).toContainText("60");

  // 设计规范 · 幅度, 强 (the default): from 28px below, scale 0.92, blur 6px, 0.06s apart.
  expect(await rootStyle(home, "--space-enter-rise")).toBe("28px");
  expect(await rootStyle(home, "--space-enter-scale")).toBe("0.92");
  expect(await rootStyle(home, "--space-enter-blur")).toBe("6px");
  expect(await rootStyle(home, "--space-stagger")).toBe("0.06s");
  expect(await rootStyle(home, "--space-emerge-visual")).toBe("0.55s");
  expect(await rootStyle(home, "--space-expand-visual")).toBe("0.42s");
  // The blur eases on its own: 0.28s × 1.3 at 强.
  expect(await rootStyle(home, "--space-blur-duration")).toBe("0.36s");

  const declared = (selector: string) =>
    home.locator(selector).first().evaluate((el) => {
      const style = getComputedStyle(el);
      return { name: style.animationName, easing: style.animationTimingFunction, delay: style.animationDelay, fill: style.animationFillMode };
    });
  const heading = await declared("h1");
  expect(heading.name).toBe("space-rise, space-unblur");
  expect(heading.easing).toMatch(/^linear\(.*\), cubic-bezier\(0\.2, 0\.8, 0\.2, 1\)$/);
  expect(heading.delay).toBe("0s, 0s");
  expect(heading.fill).toBe("backwards, backwards");
  expect((await declared("body > .space-card")).delay, "the third card in the page, after the heading and the grid").toBe("0.12s, 0.12s");
  expect((await declared(".space-grid > .space-card:nth-child(2)")).delay).toBe("0.06s, 0.06s");

  // Once they have arrived, nothing is left on them.
  await expect.poll(() => home.evaluate(() => document.getAnimations().filter((a) => a.playState === "running").length), { timeout: 10_000 }).toBe(0);
  const final = await home.locator("body > .space-card").first().evaluate((el) => {
    const style = getComputedStyle(el);
    return [style.opacity, style.transform, style.filter];
  });
  expect(final).toEqual(["1", "none", "none"]);

  // At 轻 the travel shrinks (幅度 × 0.6 of 标准) and the springs soften.
  await app.firstWindow().then((page) => page.evaluate(() => window.notes.setPreferences({ motion: "light" })));
  await expect.poll(() => rootStyle(home, "--space-enter-rise")).toBe("8.4px");
  expect(await rootStyle(home, "--space-enter-scale")).toBe("0.976");
  expect(await rootStyle(home, "--space-emerge-visual")).toBe("0.36s");

  // 减弱动态效果: the cards only fade in.
  await home.emulateMedia({ reducedMotion: "reduce" });
  expect((await declared("h1")).name).toBe("space-fade");
  await app.close();
});

test("the homepage follows 排版, 强调色 and 外观 as they change", async ({ scratch }) => {
  const { app, page, home } = await openSpace(scratch, { "健身/训练记录.md": training, ".notes/空间/健身.html": homepage }, "健身");
  await expect(home.locator("space-stat[op=max]")).toContainText("60");
  const statLabel = home.locator("space-stat[op=max]").locator(".label");

  await page.evaluate(() =>
    window.notes.setPreferences({ typography: { bodyFont: "songti", headingFont: "serif", size: 20 } as never, accent: "pink", colorScheme: "dark" }),
  );
  await expect.poll(() => home.evaluate(() => getComputedStyle(document.body).fontSize)).toBe("20px");
  expect(await home.evaluate(() => getComputedStyle(document.body).fontFamily)).toContain("Noto Serif SC");
  expect(await home.locator("h1").evaluate((el) => getComputedStyle(el).fontFamily)).toContain("Source Serif 4");
  expect(await statLabel.evaluate((el) => getComputedStyle(el).fontFamily), "components inherit the page's font").toContain("Noto Serif SC");
  expect(await resolved(home, "var(--space-accent)")).toBe("rgb(255, 55, 95)");
  expect(await resolved(home, "var(--lb-accent)")).toBe("rgb(255, 55, 95)");
  // 深色 is its own set: the note card's dark colour.
  // (Playwright fixes pages to light unless told otherwise.)
  await home.emulateMedia({ colorScheme: null });
  await expect.poll(() => resolved(home, "var(--space-bg)")).toBe("rgb(30, 30, 33)");
  expect(await home.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(30, 30, 33)");
  await app.close();
});

test("a homepage that wants the network asks atop the page; until allowed its requests are blocked, then they go through; the choice can be taken back", async ({ scratch }) => {
  const { createServer } = await import("node:http");
  const server = createServer((_, res) => {
    res.writeHead(200, { "content-type": "application/json", "access-control-allow-origin": "*" });
    res.end(JSON.stringify({ rate: 7.1 }));
  });
  await new Promise<void>((done) => server.listen(0, "127.0.0.1", done));
  const port = (server.address() as { port: number }).port;
  const html = `<meta name="space-scope" content="健身">
<meta name="space-network" content="127.0.0.1:${port}">
<meta name="space-network-reason" content="查汇率">
<button id="go">查</button><p id="out">…</p>
<script>
document.getElementById("go").onclick = () => fetch("http://127.0.0.1:${port}/rate").then((r) => r.json()).then((d) => (out.textContent = "汇率 " + d.rate), () => (out.textContent = "未允许联网"));
</script>`;
  try {
    const { app, page, home } = await openSpace(scratch, { "健身/训练记录.md": training, ".notes/空间/健身.html": html }, "健身");
    const bar = page.getByRole("alert", { name: "主页想联网" });
    await expect(bar).toContainText(`127.0.0.1:${port}`);
    await expect(bar).toContainText("查汇率");
    await home.locator("#go").click();
    await expect(home.locator("#out")).toHaveText("未允许联网");

    await bar.getByRole("button", { name: "允许联网" }).click();
    await expect(bar).toHaveCount(0);
    const again = await spacePage(app, "健身");
    await again.locator("#go").click();
    await expect(again.locator("#out")).toHaveText("汇率 7.1");

    // Taken back from the title: it asks again.
    await page.getByRole("button", { name: "已允许联网" }).click();
    await expect(page.getByRole("alert", { name: "主页想联网" })).toBeVisible();
    await page.getByRole("alert", { name: "主页想联网" }).getByRole("button", { name: "不允许" }).click();
    await expect(page.getByRole("button", { name: "未允许联网" })).toBeVisible();
    await app.close();
  } finally {
    server.close();
  }
});
