import type { Page } from "@playwright/test";
import { mkdir, readFile, rename, rm, utimes, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, launchWith, library, test } from "./fixtures";

// Changes made by other programs — a sync tool, another editor, an agent — while the app is open.

const saveState = (page: Page) => page.getByRole("status", { name: "保存状态" });

async function openNote(page: Page, folder: string, title: string) {
  await page.getByRole("treeitem", { name: folder }).click();
  await page.getByRole("list", { name: "当前目录内容" }).getByRole("button", { name: title, exact: true }).click();
  await expect(page.getByLabel("笔记正文")).toBeFocused();
}

/**
 * Starts a pinyin composition and leaves it open. The input method holds the text until it
 * commits, so nothing is saved meanwhile: unsaved input for as long as the test needs.
 */
async function startComposing(page: Page, pinyin: string) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Input.imeSetComposition", { text: pinyin, selectionStart: pinyin.length, selectionEnd: pinyin.length });
  return async function commit(text: string) {
    await cdp.send("Input.insertText", { text });
    await cdp.detach();
  };
}

test("notes and folders added, edited, moved or deleted elsewhere show up in the tree and list", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n", "日记/读书.md": "# 读书\n" });
  const lastWeek = new Date(Date.now() - 7 * 24 * 3600 * 1000);
  await utimes(join(root, "日记/散步.md"), lastWeek, lastWeek);
  const { app, page } = await launchWith(scratch, root);
  const list = page.getByRole("list", { name: "当前目录内容" }).getByRole("button");
  await page.getByRole("treeitem", { name: "日记" }).click();
  await expect(list).toHaveText(["读书", "散步"]);

  await writeFile(join(root, "日记/早餐.md"), "# 早餐\n");
  await expect(list).toHaveText(["早餐", "读书", "散步"]);

  // Edited elsewhere: newest first.
  await writeFile(join(root, "日记/散步.md"), "# 散步\n\n雨后\n");
  await expect(list).toHaveText(["散步", "早餐", "读书"]);

  await rm(join(root, "日记/早餐.md"));
  await expect(list).toHaveText(["散步", "读书"]);

  await mkdir(join(root, "学习"));
  await rename(join(root, "日记/读书.md"), join(root, "学习/读书.md"));
  await expect(page.getByRole("treeitem", { name: "学习" })).toBeVisible();
  await expect(list).toHaveText(["散步"]);
  await page.getByRole("treeitem", { name: "学习" }).click();
  await expect(list).toHaveText(["读书"]);

  // The open folder deleted elsewhere: the list falls back to the nearest folder still there.
  await rm(join(root, "学习"), { recursive: true });
  await expect(page.getByRole("treeitem", { name: "学习" })).toHaveCount(0);
  await expect(page.getByRole("treeitem", { name: "笔记库" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByRole("heading", { name: "笔记库" })).toBeVisible();
  await app.close();
});

test("search finds notes as other programs leave them", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n\n小路\n" });
  const { app, page } = await launchWith(scratch, root);
  await expect(page.getByRole("list", { name: "当前目录内容" }).getByRole("button")).toHaveText(["日记"]);
  await page.keyboard.press("ControlOrMeta+KeyK");
  const field = page.getByRole("searchbox", { name: "搜索笔记" });
  const hits = page.getByRole("list", { name: "搜索结果" }).getByRole("button");
  await field.fill("青苔");
  await expect(page.getByText("没有找到“青苔”")).toBeVisible();

  await writeFile(join(root, "日记/散步.md"), "# 散步\n\n小路上长满了青苔。\n");
  await writeFile(join(root, "苔藓图鉴.md"), "# 苔藓图鉴\n\n青苔喜欢阴凉\n");
  // Asked again until the watcher's notice has reached the index.
  await expect(async () => {
    await field.fill("");
    await field.fill("青苔");
    await expect(hits).toHaveCount(2, { timeout: 500 });
  }).toPass();
  await app.close();
});

test("an open note with nothing unsaved follows the disk, and is let go when deleted elsewhere", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n", "日记/读书.md": "# 读书\n" });
  const walk = join(root, "日记/散步.md");
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "日记", "散步");
  const editor = page.getByLabel("笔记正文");

  await writeFile(walk, "# 散步\n\n同步来的一段\n");
  await expect(editor).toContainText("同步来的一段");
  await expect(editor).toBeFocused();

  // Typing goes on from the version now on disk, with nothing to resolve.
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("雨后");
  await expect(saveState(page)).toHaveText("已保存");
  expect(await readFile(walk, "utf8")).toBe("# 散步\n\n同步来的一段\n雨后");

  await rm(walk);
  await expect(page.getByRole("alert")).toContainText("找不到“散步”，它可能已在别处移动或删除。");
  await expect(page.getByText("选择一篇笔记")).toBeVisible();
  await expect(page.getByRole("list", { name: "当前目录内容" }).getByRole("button")).toHaveText(["读书"]);
  await app.close();
});

test("unsaved input is never overwritten: the conflict lets you keep it, retry, or save it as a copy", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n" });
  const walk = join(root, "日记/散步.md");
  const synced = "# 散步\n\n同步来的一段\n";
  const { app, page } = await launchWith(scratch, root);
  await openNote(page, "日记", "散步");
  const editor = page.getByLabel("笔记正文");
  const conflict = page.getByRole("alert", { name: "保存冲突" });
  await page.keyboard.press("ControlOrMeta+End");

  // Mid-pinyin, so nothing is saved yet, a sync tool rewrites the note.
  const commit = await startComposing(page, "yuhou");
  await writeFile(walk, synced);
  await expect(conflict).toContainText("这篇笔记已在别处修改。你的输入还没有保存，仍保留在编辑器中。");
  await commit("雨后");
  await expect(editor).toContainText("雨后");
  await expect(editor).not.toContainText("同步来的一段");
  expect(await readFile(walk, "utf8")).toBe(synced);

  // Keep the input for now: back to typing, still unsaved, nothing written over.
  await conflict.getByRole("button", { name: "保留输入" }).click();
  await expect(conflict).toHaveCount(0);
  // And it stays away: nothing new happened, so nothing raises it again (a save the input method put off
  // must not try again behind the user's back and meet the same conflict).
  await page.waitForTimeout(1000);
  await expect(conflict).toHaveCount(0);
  await expect(editor).toBeFocused();
  await page.keyboard.type("，青苔");
  await expect(saveState(page)).toContainText("保存冲突：这篇笔记已在别处修改。");
  expect(await readFile(walk, "utf8")).toBe(synced);

  // Retrying while the disk still holds the other version asks again.
  await saveState(page).getByRole("button", { name: "重试" }).click();
  await expect(conflict).toBeVisible();
  expect(await readFile(walk, "utf8")).toBe(synced);

  // A copy keeps both: the input in a new note beside the original, opened in its place.
  await conflict.getByRole("button", { name: "另存副本" }).click();
  const list = page.getByRole("list", { name: "当前目录内容" });
  await expect(list.getByRole("button", { name: "散步 副本" })).toHaveAttribute("aria-current", "true");
  await expect(saveState(page)).toHaveText("已保存");
  expect(await readFile(join(root, "日记/散步 副本.md"), "utf8")).toBe("# 散步\n雨后，青苔");
  expect(await readFile(walk, "utf8")).toBe(synced);

  await list.getByRole("button", { name: "散步", exact: true }).click();
  await expect(editor).toContainText("同步来的一段");
  await app.close();
});

test("reloading the disk's version, or dropping input for a note deleted elsewhere, asks first", async ({ scratch }) => {
  const root = await library(scratch, "笔记库", { "日记/散步.md": "# 散步\n", "日记/读书.md": "# 读书\n" });
  const walk = join(root, "日记/散步.md");
  const { app, page } = await launchWith(scratch, root);
  const editor = page.getByLabel("笔记正文");
  const conflict = page.getByRole("alert", { name: "保存冲突" });
  const answerConfirm = (response: number) =>
    app.evaluate(({ dialog }, choice) => {
      dialog.showMessageBox = (async () => ({ response: choice, checkboxChecked: false })) as typeof dialog.showMessageBox;
    }, response);

  await openNote(page, "日记", "散步");
  await page.keyboard.press("ControlOrMeta+End");
  let commit = await startComposing(page, "yuhou");
  await writeFile(walk, "# 散步\n\n同步来的一段\n");
  await expect(conflict).toBeVisible();
  await commit("雨后");

  await answerConfirm(0); // 取消
  await conflict.getByRole("button", { name: "重新载入…" }).click();
  await expect(editor).toContainText("雨后");
  await answerConfirm(1); // 放弃输入并重新载入
  await conflict.getByRole("button", { name: "重新载入…" }).click();
  await expect(editor).toContainText("同步来的一段");
  await expect(editor).not.toContainText("雨后");
  await expect(conflict).toHaveCount(0);
  await expect(saveState(page)).toHaveText("已保存");

  // Deleted elsewhere while the input is unsaved: kept until the user drops it.
  await page.keyboard.press("ControlOrMeta+End");
  commit = await startComposing(page, "qingtai");
  await rm(walk);
  await expect(conflict).toContainText("找不到“散步”，它可能已在别处移动或删除。");
  await commit("青苔");
  await conflict.getByRole("button", { name: "放弃输入…" }).click();
  await expect(page.getByText("选择一篇笔记")).toBeVisible();
  await expect(page.getByRole("list", { name: "当前目录内容" }).getByRole("button")).toHaveText(["读书"]);
  await app.close();
});
