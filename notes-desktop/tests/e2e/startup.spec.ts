import type { Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launch, launchWith, library, test } from "./fixtures";

/** Opens `title` in `folder` from the tree and the list, the way a user would. */
async function openNote(page: Page, folder: string, title: string) {
  await page.getByRole("treeitem", { name: folder }).click();
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title }).click();
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
  await app.close();
});
