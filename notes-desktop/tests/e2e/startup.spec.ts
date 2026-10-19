import type { Page } from "@playwright/test";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cpus, release } from "node:os";
import { join } from "node:path";
import { expect, launch, launchWith, library, test } from "./fixtures";

/** Opens `title` in `folder` from the tree and the list, the way a user would. */
async function openNote(page: Page, folder: string, title: string) {
  await page.getByRole("treeitem", { name: folder, exact: true }).click();
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title, exact: true }).click();
  await expect(page.getByLabel("笔记正文")).toBeFocused();
}

test("reopens the last note in its folder, ready to type", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "日记/散步.md": "# 散步\n\n雨后",
    "日记/读书.md": "# 读书",
    "工作/周报.md": "# 周报",
  });
  let { app, page } = await launchWith(scratch, root);
  await openNote(page, "日记", "散步");
  await app.close();

  ({ app, page } = await launch(scratch));
  const editor = page.getByLabel("笔记正文");
  await expect(editor).toBeFocused();
  await expect(editor).toHaveText("# 散步\n\n雨后", { useInnerText: true });
  await expect(page.getByRole("treeitem", { name: "日记" })).toHaveAttribute("aria-selected", "true");
  const contents = page.getByRole("list", { name: "当前目录内容" }).getByRole("button");
  await expect(contents).toHaveCount(2);
  await expect(contents.filter({ hasText: "读书" })).toBeVisible();

  // The caret waits at the end of the note, so typing carries on where it left off.
  await page.keyboard.type("，青苔");
  await expect(page.getByRole("status", { name: "保存状态" })).toHaveText("已保存");
  expect(await readFile(join(root, "日记/散步.md"), "utf8")).toBe("# 散步\n\n雨后，青苔");

  // The search index is built after the note shows, in the background; it is there when asked.
  await page.keyboard.press("ControlOrMeta+KeyK");
  await page.getByRole("searchbox", { name: "搜索笔记" }).fill("周报");
  await expect(page.getByRole("list", { name: "搜索结果" }).getByRole("button")).toHaveText([/周报/]);
  await app.close();
});

// 启动性能 (desktop-rewrite-spec): with about ten thousand notes, a cold launch is ready to type in
// the last note within 1 s, and a window closed and opened again within 0.3 s, on an Apple M4.
// Other machines (CI, Windows) only record their numbers. STARTUP_RUNS sets how many launches are
// measured; the median counts (`STARTUP_RUNS=10 npm run measure:startup`). Times run from asking
// for the app to a typed mark showing in the note, so they include Playwright's own launch.
const coldBudget = 1000;
const reopenBudget = 300;
const runs = Number(process.env.STARTUP_RUNS ?? 3);
const gated = process.platform === "darwin" && !process.env.CI;
const folders = 100;
const perFolder = 100;

/** A library of `folders` × `perFolder` notes of about 1.3 KB each. */
async function largeLibrary(scratch: string): Promise<string> {
  const paragraph = "雨后的小路上有青苔，石头缝里长出了新的草。".repeat(20);
  const root = join(scratch, "一万篇");
  for (let f = 0; f < folders; f++) {
    const dir = join(root, `文件夹 ${f}`);
    await mkdir(dir, { recursive: true });
    await Promise.all(
      Array.from({ length: perFolder }, (_, n) => writeFile(join(dir, `笔记 ${n}.md`), `# 笔记 ${f}-${n}\n\n${paragraph}\n`)),
    );
  }
  return root;
}

/** Types `mark` once the editor has focus, and answers when it shows in the note. */
async function readyToType(page: Page, mark: string): Promise<number> {
  const editor = page.getByLabel("笔记正文");
  await expect(editor).toBeFocused({ timeout: 15_000 });
  await page.keyboard.type(mark);
  await expect(editor).toContainText(mark);
  return performance.now();
}

const median = (values: number[]) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)]!;

function record(name: string, values: number[], budget: number) {
  const machine = `${process.platform} ${process.arch} · ${cpus()[0]?.model ?? "?"} · kernel ${release()}`;
  const line = `${name}: median ${Math.round(median(values))} ms (${values.map(Math.round).join(", ")}), budget ${budget} ms`;
  test.info().annotations.push({ type: "startup", description: `${machine} · ${folders * perFolder} notes · ${line}` });
  console.log(`[startup] ${machine} · ${folders * perFolder} notes · ${line}`);
}

test("starts ready to type within budget in a library of ten thousand notes", async ({ scratch }) => {
  test.setTimeout(180_000);
  const root = await largeLibrary(scratch);
  const first = await launchWith(scratch, root);
  await openNote(first.page, "文件夹 0", "笔记 7");
  await first.app.close();

  const cold: number[] = [];
  const reopen: number[] = [];
  for (let run = 0; run < runs; run++) {
    const start = performance.now();
    const { app, page } = await launch(scratch);
    cold.push((await readyToType(page, `冷${run}`)) - start);
    await expect(page.getByRole("status", { name: "保存状态" })).toHaveText("已保存");

    if (process.platform === "darwin") {
      // Closing the window keeps the app running on macOS; the Dock icon brings it back.
      const visible = () => app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().filter((w) => w.isVisible()).length);
      await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.close());
      await expect.poll(visible).toBe(0);
      const again = performance.now();
      await app.evaluate(({ app }) => app.emit("activate"));
      // The page that is open now: the same one shown again, or a new window's.
      let shown: Page | undefined;
      await expect.poll(() => (shown = app.windows().find((p) => !p.isClosed()))).toBeTruthy();
      reopen.push((await readyToType(shown!, `再${run}`)) - again);
    }
    await app.close();
  }

  record("cold launch to typing", cold, coldBudget);
  if (reopen.length) record("reopen to typing", reopen, reopenBudget);
  if (gated) {
    expect(median(cold)).toBeLessThanOrEqual(coldBudget);
    if (reopen.length) expect(median(reopen)).toBeLessThanOrEqual(reopenBudget);
  }
});
