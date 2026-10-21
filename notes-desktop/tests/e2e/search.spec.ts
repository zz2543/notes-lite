import type { Page } from "@playwright/test";
import { expect, launchWith, library, test } from "./fixtures";

const searchField = (page: Page) => page.getByRole("searchbox", { name: "搜索笔记" });
const results = (page: Page) => page.getByRole("list", { name: "搜索结果" });
const contents = (page: Page) => page.getByRole("list", { name: "当前目录内容" });

/** Types through the input method path: a pinyin composition, then (if given) the committed characters. */
async function compose(page: Page, pinyin: string, text?: string) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Input.imeSetComposition", { text: pinyin, selectionStart: pinyin.length, selectionEnd: pinyin.length });
  if (text !== undefined) await cdp.send("Input.insertText", { text });
  await cdp.detach();
}

test("⌘K turns the list header into a search field whose results stand in for the list until Esc", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "日记/雨后的散步.md": "# 雨后的散步\n\n小路上长满了青苔。\n",
    "读书/苔藓图鉴.md": "# 苔藓图鉴\n\n- 青苔喜欢阴凉潮湿的地方\n",
    "清单.md": "# 清单\n\n牛奶\n",
  });
  const { app, page } = await launchWith(scratch, root);
  await expect(contents(page).getByRole("button")).toHaveText(["读书", "日记", "清单"]);

  await page.keyboard.press("ControlOrMeta+KeyK");
  const field = searchField(page);
  await expect(field).toBeFocused();
  await expect(page.getByRole("heading", { name: "笔记库" })).toBeHidden();

  await field.fill("青苔");
  await expect(results(page).getByRole("button")).toHaveCount(2);
  await expect(contents(page)).toBeHidden();
  const walk = results(page).getByRole("button", { name: /雨后的散步/ });
  await expect(walk).toContainText("小路上长满了青苔。");
  await expect(walk).toContainText("日记");
  await expect(walk.locator("mark")).toHaveText("青苔");
  await expect(results(page).getByRole("button", { name: /苔藓图鉴/ })).toContainText("青苔喜欢阴凉潮湿的地方");

  await field.fill("不存在的词");
  await expect(page.getByText("没有找到“不存在的词”")).toBeVisible();

  // Clearing the field brings the list back; the field stays for another search.
  await field.fill("");
  await expect(contents(page).getByRole("button")).toHaveText(["读书", "日记", "清单"]);
  await expect(field).toBeFocused();

  await field.fill("牛奶");
  await expect(results(page).getByRole("button")).toHaveText([/清单/]);
  await page.keyboard.press("Escape");
  await expect(field).toBeHidden();
  await expect(page.getByRole("heading", { name: "笔记库" })).toBeVisible();
  await expect(contents(page).getByRole("button")).toHaveText(["读书", "日记", "清单"]);
  await app.close();
});

test("the search bar atop the list opens the field where it stands, can narrow to the selected folder; a result opens in its own folder", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", {
    "日记/2026/十月.md": "# 十月\n\n秋天的红叶\n",
    "日记/九月.md": "# 九月\n\n红叶还没红\n",
    "旅行/京都.md": "# 京都\n\n满山红叶\n",
  });
  const { app, page } = await launchWith(scratch, root);
  await page.getByRole("treeitem", { name: "日记" }).click();

  // In 双栏导航 the search lives atop the list only, not beside 文件夹 as well.
  const bar = page.getByRole("button", { name: "搜索", exact: true });
  await expect(bar).toHaveCount(1);
  await expect(page.locator("section.list").getByRole("button", { name: "搜索", exact: true })).toBeVisible();
  const barBox = (await bar.boundingBox())!;
  await bar.click();
  const field = searchField(page);
  await expect(field).toBeFocused();
  const fieldBox = (await page.locator("section.list .search-box").boundingBox())!;
  expect(Math.abs(fieldBox.y - barBox.y)).toBeLessThan(1);
  expect(Math.abs(fieldBox.width - barBox.width)).toBeLessThan(1);
  await field.fill("红叶");
  await expect(results(page).getByRole("button")).toHaveCount(3);
  const scope = page.getByRole("group", { name: "搜索范围" });
  await expect(scope.getByRole("button", { name: "全库" })).toHaveAttribute("aria-pressed", "true");

  await scope.getByRole("button", { name: "“日记”及子文件夹" }).click();
  await expect(results(page).getByRole("button")).toHaveCount(2);
  await expect(results(page).getByRole("button", { name: /京都/ })).toBeHidden();

  await results(page).getByRole("button", { name: /十月/ }).click();
  await expect(page.getByLabel("笔记正文")).toHaveText("# 十月\n\n秋天的红叶\n", { useInnerText: true });
  await expect(field).toBeHidden();
  await expect(page.getByRole("treeitem", { name: "2026" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByRole("heading", { name: "2026" })).toBeVisible();
  await expect(contents(page).getByRole("button", { name: "十月" })).toHaveAttribute("aria-current", "true");

  // Enter opens the first result.
  await page.keyboard.press("ControlOrMeta+KeyK");
  await field.fill("满山");
  await expect(results(page).getByRole("button")).toHaveText([/京都/]);
  await field.press("Enter");
  await expect(page.getByLabel("笔记正文")).toHaveText("# 京都\n\n满山红叶\n", { useInnerText: true });
  await expect(page.getByRole("treeitem", { name: "旅行" })).toHaveAttribute("aria-selected", "true");
  await app.close();
});

test("finds what was just saved, and searches pinyin only once it is committed", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n\n雨后\n" });
  const { app, page } = await launchWith(scratch, root);
  await page.getByRole("treeitem", { name: "日记" }).click();
  await contents(page).getByRole("button", { name: "散步" }).click();
  const editor = page.getByLabel("笔记正文");
  await expect(editor).toBeFocused();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.insertText("看见银杏");
  await expect(page.getByRole("status", { name: "保存状态" })).toHaveText("已保存");

  await page.keyboard.press("ControlOrMeta+KeyK");
  const field = searchField(page);
  await expect(field).toBeFocused();
  await compose(page, "yinxing");
  await expect(field).toHaveValue("yinxing");
  await expect(contents(page)).toBeVisible();
  await expect(page.getByText("没有找到")).toBeHidden();

  await compose(page, "yinxing", "银杏");
  await expect(field).toHaveValue("银杏");
  await expect(results(page).getByRole("button")).toHaveText([/散步/]);
  await expect(results(page).getByRole("button")).toContainText("看见银杏");
  await app.close();
});
