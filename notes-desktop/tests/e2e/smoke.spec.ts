import { _electron as electron, expect, test, type ElectronApplication } from "@playwright/test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const appDir = join(__dirname, "../..");
let scratch: string;

test.beforeEach(async () => {
  scratch = await mkdtemp(join(tmpdir(), "notes-desktop-e2e-"));
});

test.afterEach(async () => {
  await rm(scratch, { recursive: true, force: true });
});

async function library(name: string, files: Record<string, string>): Promise<string> {
  const root = join(scratch, name);
  for (const [path, body] of Object.entries(files)) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), body);
  }
  return root;
}

/** Launches the built app with its own settings under the scratch folder. */
async function launch() {
  const app = await electron.launch({ args: [appDir], env: { ...process.env, NOTES_DESKTOP_USER_DATA: join(scratch, "profile") } });
  return { app, page: await app.firstWindow() };
}

/** The next folder picker answers with this folder instead of asking. */
async function answerFolderPicker(app: ElectronApplication, folder: string) {
  await app.evaluate(({ dialog }, path) => {
    dialog.showOpenDialog = (async () => ({ canceled: false, filePaths: [path] })) as typeof dialog.showOpenDialog;
  }, folder);
}

test("first launch opens a chosen library and browses it", async () => {
  const source = "# 雨后的散步\n\n- 小路  \n- 青苔\n";
  const root = await library("我的笔记库", {
    "日记/雨后的散步.md": source,
    "日记/2026/十月.md": "# 十月",
    "读书.md": "# 读书",
    ".notes/order.json": "{}",
  });
  const { app, page } = await launch();

  await answerFolderPicker(app, root);
  await page.getByRole("button", { name: "选择笔记库…" }).click();

  const tree = page.getByRole("tree", { name: "文件夹" });
  await expect(tree.getByRole("treeitem", { name: "我的笔记库" })).toHaveAttribute("aria-selected", "true");
  await expect(tree.getByRole("treeitem")).toHaveText(["我的笔记库", "日记"]);
  const contents = page.getByRole("list", { name: "当前目录内容" });
  await expect(contents.getByRole("button")).toHaveText(["日记", "读书"]);

  const diary = tree.getByRole("treeitem", { name: "日记" });
  await diary.click();
  await expect(contents.getByRole("button")).toHaveText(["2026", "雨后的散步"]);
  await expect(tree.getByRole("treeitem")).toHaveText(["我的笔记库", "日记", "2026"]);
  // Clicking the selected, open folder folds it; once more unfolds it.
  await diary.click();
  await expect(tree.getByRole("treeitem")).toHaveText(["我的笔记库", "日记"]);
  await expect(diary).toHaveAttribute("aria-selected", "true");
  await diary.click();
  await expect(tree.getByRole("treeitem")).toHaveText(["我的笔记库", "日记", "2026"]);

  await contents.getByRole("button", { name: "雨后的散步" }).click();
  await expect(page.getByLabel("笔记原文")).toHaveJSProperty("textContent", source);

  await app.close();
});

test("remembers the library across launches, switches, and explains when it is gone", async () => {
  const first = await library("工作", { "周报.md": "# 周报" });
  const second = await library("生活", { "菜谱.md": "# 菜谱" });

  let { app, page } = await launch();
  await answerFolderPicker(app, first);
  await page.getByRole("button", { name: "选择笔记库…" }).click();
  await expect(page.getByRole("treeitem", { name: "工作" })).toBeVisible();
  await app.close();

  ({ app, page } = await launch());
  await expect(page.getByRole("treeitem", { name: "工作" })).toBeVisible();
  await expect(page.getByRole("button", { name: "周报" })).toBeVisible();

  await answerFolderPicker(app, second);
  await page.getByRole("button", { name: "切换笔记库" }).click();
  await expect(page.getByRole("treeitem", { name: "生活" })).toBeVisible();
  await expect(page.getByRole("button", { name: "菜谱" })).toBeVisible();
  await app.close();

  ({ app, page } = await launch());
  await expect(page.getByRole("treeitem", { name: "生活" })).toBeVisible();
  await app.close();

  await rm(second, { recursive: true });
  ({ app, page } = await launch());
  await expect(page.getByRole("status")).toContainText(`找不到上次的笔记库“${second}”`);
  await expect(page.getByRole("button", { name: "选择笔记库…" })).toBeVisible();
  await app.close();
});
