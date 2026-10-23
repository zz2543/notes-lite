import type { ElectronApplication, Page } from "@playwright/test";
import { readdir, readFile, realpath, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { installFakeAgent } from "../support/fakeAgent";
import { answerFolderPicker, expect, launch, launchWith, library, showSide, sideSwitch, test } from "./fixtures";

const tree = (page: Page) => page.getByRole("tree", { name: "文件夹" });
const spaceList = (page: Page) => page.getByRole("list", { name: "空间", exact: true });
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

  await expect(sideSwitch(page)).not.toBeChecked();
  await expect(sideSwitch(page)).toHaveText("资料库");
  await expect(tree(page).getByRole("treeitem")).toHaveText(["笔记库", "健身"]);
  await showSide(page, "空间");
  await expect(sideSwitch(page)).toBeChecked();
  await expect(sideSwitch(page)).toHaveText("空间");
  await expect(spaceList(page).getByRole("button")).toHaveText(["📚雅思", "🏋️健身"]);
  await expect(tree(page)).toHaveCount(0);

  await expect.poll(() => exists(join(root, ".留白"))).toBe(false);
  if (!process.env.CI) expect(await readFile(join(trash, ".留白", "空间", "健身.html"), "utf8"), "sent to the trash whole").toBe(legacy[".留白/空间/健身.html"]);
  expect(await readFile(join(root, ".notes/空间/健身.html"), "utf8")).toBe(legacy[".留白/空间/健身.html"]);
  expect(await readFile(join(root, ".notes/空间/编写说明.md"), "utf8"), "the guide is installed for this version").toContain(".notes/空间/");
  expect(await readFile(join(root, "健身/训练.md"), "utf8")).toBe(training);

  await showSide(page, "资料库");
  await expect(tree(page).getByRole("treeitem")).toHaveText(["笔记库", "健身"]);
  await app.close();
});

test("“资料库 | 空间” is one switch: it names the side shown, and its knob slides to the other end on each press", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  const { app, page } = await launchWith(scratch, root);
  const knob = sideSwitch(page).locator(".side-switch-knob");
  const label = sideSwitch(page).locator(".side-switch-label");
  const x = async (locator: typeof knob) => (await locator.boundingBox())!.x;

  await expect(sideSwitch(page)).toHaveText("资料库");
  expect(await x(knob)).toBeGreaterThan(await x(label));
  await sideSwitch(page).click();
  await expect(sideSwitch(page)).toBeChecked();
  await expect(sideSwitch(page)).toHaveText("空间");
  await expect(tree(page)).toHaveCount(0);
  await expect.poll(async () => (await x(knob)) < (await x(label))).toBe(true);
  // Pressed again: back to 资料库, the knob at the right end.
  await sideSwitch(page).click();
  await expect(sideSwitch(page)).not.toBeChecked();
  await expect(tree(page)).toBeVisible();
  await expect.poll(async () => (await x(knob)) > (await x(label))).toBe(true);
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

test("creating a space with no agent installed copies the prompt; spaces can be renamed, reordered by dragging and deleted", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/训练.md": training, "日记/今天.md": "# 今天" });
  const { app, page } = await launchWith(scratch, root);
  await standInTrash(app, join(scratch, "废纸篓"));
  await showSide(page, "空间");

  await page.getByRole("button", { name: "新建空间" }).first().click();
  const form = page.getByRole("dialog", { name: "新建空间" });
  await form.getByLabel("空间名称").fill("健身");
  await form.getByLabel("空间图标").fill("🏋️");
  await form.getByRole("checkbox", { name: "健身" }).check();
  await form.getByRole("button", { name: "新建" }).click();
  await expect(form).toHaveCount(0);
  await expect(spaceList(page).getByRole("button")).toHaveText(["🏋️健身"]);
  // No agent here for 助手 to ask: the prompt is copied for one used elsewhere.
  await expect(page.getByRole("alert")).toContainText("没有找到本机的命令行 Agent");
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
  expect((await readdir(join(root, ".notes/空间"))).sort()).toEqual(["日常.html", "编写说明.md", "顺序.json", "风格"].sort());
  expect(await readFile(join(root, "健身/训练.md"), "utf8")).toBe(training);
  await app.close();
});

test("显示源文件 in a space's menu shows its HTML file in the system file manager", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/训练.md": training, ".notes/空间/健身.html": legacy[".留白/空间/健身.html"] });
  const { app, page } = await launchWith(scratch, root);
  await app.evaluate(({ shell }) => {
    const shown: string[] = [];
    (globalThis as { shown?: string[] }).shown = shown;
    shell.showItemInFolder = (path) => void shown.push(path);
  });
  await showSide(page, "空间");
  await spaceList(page).getByRole("button", { name: "健身" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "显示源文件" }).click();

  await expect.poll(() => app.evaluate(() => (globalThis as { shown?: string[] }).shown)).toEqual([join(root, ".notes", "空间", "健身.html")]);
  await app.close();
});

test("a space file written by another program shows up in the list", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/训练.md": training });
  const { app, page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await expect(page.getByText("空间围绕一个主题")).toBeVisible();

  await library(scratch, "笔记库", { ".notes/空间/外部.html": '<meta name="lb-scope" content="*">\n<meta name="lb-icon" content="🌍">\n' });
  await expect(spaceList(page).getByRole("button")).toHaveText(["🌍外部"]);
  await app.close();
});

test("creating a space opens 助手, which waits for 开始 with what the user wants; it then works in a new conversation in the library itself", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "健身/训练.md": training });
  const agent = await installFakeAgent(join(scratch, "agents"), "claude", { session: "s-1", steps: [{ say: "方案如下……你更关心哪些数字？" }] });
  const { page } = await launchWith(scratch, root);
  await showSide(page, "空间");

  await page.getByRole("button", { name: "新建空间" }).first().click();
  const form = page.getByRole("dialog", { name: "新建空间" });
  await form.getByLabel("空间名称").fill("健身");
  await form.getByRole("checkbox", { name: "健身" }).check();
  await form.getByRole("button", { name: "新建" }).click();

  const column = page.getByRole("complementary", { name: "助手栏" });
  await expect(column).toHaveAttribute("aria-hidden", "false");
  // Nothing is sent yet: the column asks first.
  const start = column.getByRole("region", { name: "生成主页" });
  await expect(start).toContainText("为“健身”生成主页");
  await expect(start).toContainText("范围：健身");
  await expect(start.getByRole("checkbox", { name: "先给我看方案，确认后再写" })).toBeChecked();
  expect(await agent.runs()).toHaveLength(0);
  await start.getByRole("textbox", { name: "你希望主页上有什么？（可选）" }).fill("体重曲线");
  // 风格: 不指定 at first; a 风格参考 picked shows larger, with its summary.
  const styles = start.getByRole("radiogroup", { name: "风格（可选）" });
  await expect(styles.getByRole("radio")).toHaveText(["不指定", "晴空", "暗夜", "玻璃", "便当", "大地", "活力", "自己描述"]);
  await expect(styles.getByRole("radio", { name: "不指定" })).toHaveAttribute("aria-checked", "true");
  await styles.getByRole("radio", { name: "晴空" }).click();
  await expect(start.getByRole("img", { name: "晴空风格预览" })).toBeVisible();
  await expect(start).toContainText("橙色胶囊进度条");
  await start.getByRole("button", { name: "开始" }).click();

  const conversation = column.getByRole("log", { name: "对话" });
  // The column shows what was asked in a line; the agent gets the whole prompt.
  await expect(conversation).toContainText("生成“健身”的主页");
  await expect(conversation).toContainText("我希望主页上有：体重曲线");
  await expect(conversation).not.toContainText("请为笔记应用编写");
  await expect(conversation).toContainText("你更关心哪些数字？");
  const [run] = await agent.runs();
  expect(run!.stdin).toContain("请为笔记应用编写“健身”空间的空间主页。");
  expect(run!.stdin).toContain(join(root, ".notes", "空间", "健身.html"));
  expect(run!.stdin).toContain("健身/训练.md#卧推：日期 | 重量");
  expect(run!.stdin).toContain("我希望主页上有：体重曲线");
  await expect(conversation).toContainText("风格：晴空");
  expect(run!.stdin).toContain("风格：用风格参考里的「晴空」。先完整阅读风格参考文件夹里的 晴空.md");
  expect(run!.stdin).toContain(`- 风格参考：${join(root, ".notes", "空间", "风格")}`);
  expect(await readFile(join(root, ".notes", "空间", "风格", "晴空.md"), "utf8")).toContain("胶囊进度条");
  expect(run!.stdin).toContain("先给方案、再动手");
  expect(run!.stdin).toContain("请先按“工作方式”给出方案并问我的偏好");
  // The space is told with its authoring guide, as the open one.
  expect(run!.stdin).toContain("- 健身：.notes/空间/健身.html（当前打开）");
  expect(await realpath(run!.cwd)).toBe(await realpath(root));

  // Asked again from the space's menu: 取消 sends nothing; 开始 without a plan, another new conversation.
  await spaceList(page).getByRole("button", { name: "健身" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "让助手生成主页" }).click();
  await start.getByRole("button", { name: "取消" }).click();
  await expect(start).toHaveCount(0);
  await expect(conversation).toContainText("你更关心哪些数字？");
  await spaceList(page).getByRole("button", { name: "健身" }).click({ button: "right" });
  await page.getByRole("menuitem", { name: "让助手生成主页" }).click();
  await start.getByRole("checkbox", { name: "先给我看方案，确认后再写" }).uncheck();
  await start.getByRole("radiogroup", { name: "风格（可选）" }).getByRole("radio", { name: "自己描述" }).click();
  await start.getByRole("textbox", { name: "描述你想要的风格" }).fill("深蓝底、霓虹绿数字");
  await start.getByRole("button", { name: "开始" }).click();
  await expect.poll(async () => (await agent.runs()).length).toBe(2);
  const second = (await agent.runs())[1]!;
  expect(second.argv).not.toContain("--resume");
  expect(second.stdin).toContain("这次不用先给方案，直接写空间文件。");
  expect(second.stdin).toContain("风格：我自己描述——深蓝底、霓虹绿数字。");
  await expect(conversation).toContainText("直接生成，不用先看方案");
});

test("the scope is a folded tree: a folder opens with its caret; ticking one ticks the folders inside, and names the space", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "学习/英语/单词.md": "# 单词", "学习/英语/语法/时态.md": "# 时态", "学习/数学/线代.md": "# 线代", "日记/今天.md": "# 今天" });
  const { page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await page.getByRole("button", { name: "新建空间" }).first().click();
  const form = page.getByRole("dialog", { name: "新建空间" });
  const folders = form.getByRole("group", { name: "笔记库中的文件夹" });
  // Only the top level at first.
  await expect(folders.getByRole("checkbox")).toHaveCount(2);
  await folders.getByRole("button", { name: "展开“学习”" }).click();
  await expect(folders.getByRole("checkbox", { name: "学习 / 英语", exact: true })).toBeVisible();
  await folders.getByRole("button", { name: "展开“英语”" }).click();
  // One inside ticked: the folder around it shows a dash.
  await folders.getByRole("checkbox", { name: "学习 / 英语 / 语法" }).check();
  await expect(folders.getByRole("checkbox", { name: "学习", exact: true })).toHaveAttribute("aria-checked", "mixed");
  await expect(form.getByLabel("空间名称")).toHaveValue("语法");
  // The whole folder: everything inside is ticked with it, and waits for it.
  await folders.getByRole("checkbox", { name: "学习", exact: true }).check();
  for (const inside of ["学习 / 英语", "学习 / 数学", "学习 / 英语 / 语法"]) {
    await expect(folders.getByRole("checkbox", { name: inside, exact: true })).toBeChecked();
    await expect(folders.getByRole("checkbox", { name: inside, exact: true })).toBeDisabled();
  }
  await expect(form.getByLabel("空间名称")).toHaveValue("学习");
  await folders.getByRole("button", { name: "收起“学习”" }).click();
  await expect(folders.getByRole("checkbox")).toHaveCount(2);
  await form.getByRole("button", { name: "新建" }).click();
  await expect(form).toHaveCount(0);
  expect(await readFile(join(root, ".notes/空间/学习.html"), "utf8")).toContain('content="学习"');
});
