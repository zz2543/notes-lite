import type { Page } from "@playwright/test";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { installFakeAgent } from "../support/fakeAgent";
import { closeSettings, expect, launchWith, library, openSettings, showSide, sideSwitch, test } from "./fixtures";

// 界面特效 (设置 › 动画): the effects from the design libraries, each on its own switch under one for all.
// Off, the interface is as it was without them.

const column = (page: Page) => page.getByRole("complementary", { name: "助手栏" });
const input = (page: Page) => column(page).getByRole("textbox", { name: "给助手的消息" });

test("界面特效 in 设置 › 动画: one switch for all of them, one for each; off takes every effect away", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "一.md": "一" });
  // An agent installed, so the column has its composer.
  await installFakeAgent(join(scratch, "agents"), "claude", { session: "s-1", steps: [{ say: "好。" }] });
  const { app, page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  // On by default: the segments' pill and the side switch's knob are liquid; the assistant keeps its figure.
  await expect(column(page).getByRole("img", { name: /助手形象/ })).toHaveClass(/assistant-figure/);
  await expect(column(page).locator(".segmented.liquid")).toHaveCount(await column(page).locator(".segmented").count());
  await expect(sideSwitch(page)).toHaveClass(/liquid/);
  await expect(column(page).locator(".composer-beam")).toHaveCount(1);

  const panel = await openSettings(app, page, "动画");
  const group = panel.getByRole("group", { name: "界面特效" });
  await expect(group.getByRole("switch")).toHaveCount(4);
  for (const name of ["界面特效", "流光边框", "思考光球", "液态滑块"]) await expect(group.getByRole("switch", { name })).toHaveAttribute("aria-checked", "true");

  // One effect off: only it goes.
  await group.getByRole("switch", { name: "液态滑块" }).click();
  await expect(sideSwitch(page)).not.toHaveClass(/liquid/);
  await expect(panel.locator(".segmented.liquid")).toHaveCount(0);
  await expect(column(page).locator(".composer-beam")).toHaveCount(1);

  // All off: the effect switches go with them, and so does every effect.
  await group.getByRole("switch", { name: "界面特效" }).click();
  await expect(group.getByRole("switch")).toHaveCount(1);
  await expect(sideSwitch(page)).not.toHaveClass(/liquid/);
  await expect(page.locator(".segmented.liquid, [data-beam]")).toHaveCount(0);
  await expect(panel.locator(".segmented.liquid")).toHaveCount(0);

  // Back on, each effect as it was left.
  await group.getByRole("switch", { name: "界面特效" }).click();
  await expect(group.getByRole("switch", { name: "液态滑块" })).toHaveAttribute("aria-checked", "false");
  await expect(group.getByRole("switch", { name: "流光边框" })).toHaveAttribute("aria-checked", "true");
  await expect(column(page).locator(".composer-beam")).toHaveCount(1);
  await expect(sideSwitch(page)).not.toHaveClass(/liquid/);
  await closeSettings(app, panel);
  await app.close();
});

test("while the assistant works the composer's border beams, and an orb thinks beside the step under way", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记\n" });
  const hold = join(scratch, "go-on");
  await installFakeAgent(join(scratch, "agents"), "claude", {
    session: "s-1",
    steps: [{ tool: "Edit", input: { file_path: join(root, "随记.md") }, write: { path: "随记.md", text: "随记\n\n- 跑步\n" }, waitFor: hold }, { say: "好了。" }],
  });
  const { page } = await launchWith(scratch, root);
  await page.getByRole("button", { name: "打开助手栏" }).click();
  const beam = column(page).locator(".composer-beam");
  await expect(beam).toHaveAttribute("data-beam", /.+/);
  await expect(beam).not.toHaveAttribute("data-active");

  await input(page).fill("帮我补充计划");
  await input(page).press("Enter");
  await expect(beam).toHaveAttribute("data-active", "");
  const conversation = column(page).getByRole("log", { name: "对话" });
  await expect(conversation.locator(".timeline-orb")).toBeVisible();
  await expect(conversation.getByRole("button", { name: /1 个步骤 · 正在写入/ })).toBeVisible();
  await expect(column(page).getByRole("img", { name: "助手形象：写入" })).toHaveClass(/assistant-figure/);

  await writeFile(hold, "");
  await expect(conversation).toContainText("好了。");
  await expect(beam).not.toHaveAttribute("data-active", "", { timeout: 5000 });
  await expect(conversation.locator(".timeline-orb")).toHaveCount(0);
  await expect(column(page).getByRole("img", { name: /助手形象：(完成|待命)/ })).toBeVisible();
});

test("让助手生成主页 glows from inside, and 资料库 | 空间 slides its knob as liquid", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "随记.md": "随记\n", ".notes/空间/空白.html": '<meta name="lb-scope" content="">\n' });
  const { page } = await launchWith(scratch, root);
  await showSide(page, "空间");
  await page.getByRole("list", { name: "空间", exact: true }).getByRole("button", { name: "空白" }).click();
  const generate = page.getByRole("button", { name: "让助手生成主页" });
  await expect(generate).toBeVisible();
  await expect(page.locator(".generate-beam")).toHaveAttribute("data-active", "");
  await expect(sideSwitch(page).locator("svg[aria-hidden]").first()).toBeAttached();
});
