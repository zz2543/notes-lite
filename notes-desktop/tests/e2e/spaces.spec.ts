import type { ElectronApplication, Page } from "@playwright/test";
import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { answerFolderPicker, expect, launch, launchWith, library, test } from "./fixtures";

const tree = (page: Page) => page.getByRole("tree", { name: "文件夹" });
const spaceList = (page: Page) => page.getByRole("list", { name: "空间", exact: true });
const sideTab = (page: Page, name: "资料库" | "空间") => page.getByRole("tablist", { name: "侧栏" }).getByRole("tab", { name });
const exists = (path: string) => stat(path).then(() => true, () => false);

/** On CI the real system trash is used; locally, a folder stands in so test files stay out of yours. */
async function standInTrash(app: ElectronApplication, folder: string) {
  if (process.env.CI) return;
  await app.evaluate(({ shell }, folder) => {
    const fs = process.getBuiltinModule("node:fs");
    const path = process.getBuiltinModule("node:path");
    fs.mkdirSync(folder, { recursive: true });
    shell.trashItem = async (item) => fs.renameSync(item, path.join(folder, path.basename(item)));
  }, folder);
}

const legacy = {
  ".留白/空间/健身.html": '<meta name="lb-scope" content="健身">\n<meta name="lb-icon" content="🏋️">\n<p>主页</p>',
  ".留白/空间/雅思.html": '<meta name="lb-scope" content="*">\n<meta name="lb-icon" content="📚">\n',
  ".留白/空间/顺序.json": '["雅思", "健身"]',
  ".留白/操作记录.json": "[]",
};
const training = "## 卧推\r\n\r\n| 日期 | 重量 |\r\n|---|---|\r\n| 2026-10-18 | 60 |\r\n";

test("an old library's .留白/ moves into .notes/ on first open, the old folder to the trash; its spaces show and notes stay as they were", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { ...legacy, "健身/训练.md": training });
  const { app, page } = await launch(scratch);
  const trash = join(scratch, "trash");
  await standInTrash(app, trash);
  await answerFolderPicker(app, root);
  await page.getByRole("button", { name: "选择笔记库…" }).click();

  await expect(sideTab(page, "资料库")).toHaveAttribute("aria-selected", "true");
  await expect(tree(page).getByRole("treeitem")).toHaveText(["笔记库", "健身"]);
  await sideTab(page, "空间").click();
  await expect(sideTab(page, "空间")).toHaveAttribute("aria-selected", "true");
  await expect(spaceList(page).getByRole("button")).toHaveText(["📚雅思", "🏋️健身"]);
  await expect(tree(page)).toHaveCount(0);

  await expect.poll(() => exists(join(root, ".留白"))).toBe(false);
  if (!process.env.CI) expect(await readFile(join(trash, ".留白", "空间", "健身.html"), "utf8"), "sent to the trash whole").toBe(legacy[".留白/空间/健身.html"]);
  expect(await readFile(join(root, ".notes/空间/健身.html"), "utf8")).toBe(legacy[".留白/空间/健身.html"]);
  expect(await readFile(join(root, ".notes/空间/编写说明.md"), "utf8"), "the guide is installed for this version").toContain(".notes/空间/");
  expect(await readFile(join(root, "健身/训练.md"), "utf8")).toBe(training);

  await sideTab(page, "资料库").click();
  await expect(tree(page).getByRole("treeitem")).toHaveText(["笔记库", "健身"]);
  await app.close();
});

test("a move that cannot finish says so and leaves .留白/ as it was", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { ...legacy, ".notes": "挡路的文件", "健身/训练.md": training });
  const { app, page } = await launchWith(scratch, root);

  await expect(page.getByRole("alert")).toContainText(".留白");
  expect(await readFile(join(root, ".留白/空间/健身.html"), "utf8")).toBe(legacy[".留白/空间/健身.html"]);
  expect(await readFile(join(root, ".留白/空间/顺序.json"), "utf8")).toBe(legacy[".留白/空间/顺序.json"]);
  await app.close();
});

test("creating a space copies the prompt; spaces can be renamed, reordered by dragging and deleted", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/训练.md": training, "日记/今天.md": "# 今天" });
  const { app, page } = await launchWith(scratch, root);
  await standInTrash(app, join(scratch, "废纸篓"));
  await sideTab(page, "空间").click();

  await page.getByRole("button", { name: "新建空间" }).first().click();
  const form = page.getByRole("dialog", { name: "新建空间" });
  await form.getByLabel("空间名称").fill("健身");
  await form.getByLabel("空间图标").fill("🏋️");
  await form.getByRole("checkbox", { name: "健身" }).check();
  await form.getByRole("button", { name: "新建" }).click();
  await expect(form).toHaveCount(0);
  await expect(spaceList(page).getByRole("button")).toHaveText(["🏋️健身"]);
  await expect(page.getByRole("alert")).toContainText("提示词");
  const prompt = await app.evaluate(({ clipboard }) => clipboard.readText());
  expect(prompt).toContain(join(root, ".notes", "空间", "健身.html"));
  expect(prompt).toContain("健身/训练.md#卧推：日期 | 重量");
  expect(await readFile(join(root, ".notes/空间/健身.html"), "utf8")).toContain('content="健身"');

  await page.getByRole("button", { name: "新建空间" }).first().click();
  await form.getByLabel("空间名称").fill("日常");
  await form.getByRole("checkbox", { name: "整个笔记库" }).check();
  await form.getByRole("button", { name: "新建" }).click();
  await expect(spaceList(page).getByRole("button")).toHaveText(["🏋️健身", "✨日常"]);

  // Dragged above the first one: the order is kept in the library.
  const from = await spaceList(page).getByRole("button", { name: "日常" }).boundingBox();
  const to = await spaceList(page).getByRole("button", { name: "健身" }).boundingBox();
  await page.mouse.move(from!.x + from!.width / 2, from!.y + from!.height / 2);
  await page.mouse.down();
  await page.mouse.move(to!.x + to!.width / 2, to!.y + 4, { steps: 12 });
  await page.mouse.move(to!.x + to!.width / 2, to!.y + 2, { steps: 4 });
  await page.mouse.up();
  await expect(spaceList(page).getByRole("button")).toHaveText(["✨日常", "🏋️健身"]);
  await expect.poll(async () => JSON.parse(await readFile(join(root, ".notes/空间/顺序.json"), "utf8"))).toEqual(["日常", "健身"]);

  // Renamed and re-scoped, keeping its page.
  await writeFile(join(root, ".notes/空间/健身.html"), (await readFile(join(root, ".notes/空间/健身.html"), "utf8")) + "<p>主页</p>");
  await spaceList(page).getByRole("button", { name: "健身" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "编辑空间…" }).click();
  const edit = page.getByRole("dialog", { name: "编辑空间" });
  await expect(edit.getByLabel("空间名称")).toHaveValue("健身");
  await expect(edit.getByRole("checkbox", { name: "健身" })).toBeChecked();
  await edit.getByLabel("空间名称").fill("力量");
  await edit.getByRole("checkbox", { name: "日记" }).check();
  await edit.getByRole("button", { name: "保存" }).click();
  await expect(spaceList(page).getByRole("button")).toHaveText(["✨日常", "🏋️力量"]);
  const renamed = await readFile(join(root, ".notes/空间/力量.html"), "utf8");
  expect(renamed).toContain('content="健身, 日记"');
  expect(renamed).toContain("<p>主页</p>");

  // Deleting asks first, and leaves the notes alone.
  await app.evaluate(({ dialog }) => {
    dialog.showMessageBox = (async () => ({ response: 1, checkboxChecked: false })) as typeof dialog.showMessageBox;
  });
  await spaceList(page).getByRole("button", { name: "力量" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "删除空间…" }).click();
  await expect(spaceList(page).getByRole("button")).toHaveText(["✨日常"]);
  expect((await readdir(join(root, ".notes/空间"))).sort()).toEqual(["日常.html", "编写说明.md", "顺序.json"].sort());
  expect(await readFile(join(root, "健身/训练.md"), "utf8")).toBe(training);
  await app.close();
});

test("a space file written by another program shows up in the list", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/训练.md": training });
  const { app, page } = await launchWith(scratch, root);
  await sideTab(page, "空间").click();
  await expect(page.getByText("空间围绕一个主题")).toBeVisible();

  await library(scratch, "笔记库", { ".notes/空间/外部.html": '<meta name="lb-scope" content="*">\n<meta name="lb-icon" content="🌍">\n' });
  await expect(spaceList(page).getByRole("button")).toHaveText(["🌍外部"]);
  await app.close();
});
