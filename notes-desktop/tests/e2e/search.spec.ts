import type { Page } from "@playwright/test";
import { expect, launchWith, library, test } from "./fixtures";

const searchField = (page: Page) => page.getByRole("searchbox", { name: "搜索笔记" });
const results = (page: Page) => page.getByRole("list", { name: "搜索结果" });
const contents = (page: Page) => page.getByRole("list", { name: "当前目录内容" });

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
