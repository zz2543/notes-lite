import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { openLibrary } from "../../src/core";
import { refuseWrites } from "../support/disk";
import { contents, fakeTrash, library } from "../support/library";

describe("新建", () => {
  it("creates a note in the folder, numbering the name when it is taken", async () => {
    const root = await library({ "日记/日记.md": "今天散步看见了落叶" });
    const lib = await openLibrary(root);

    expect(await lib.createNote("日记", "日记")).toBe("日记/日记 2.md");
    expect(await lib.createNote("日记")).toBe("日记/未命名笔记.md");
    expect(await lib.createNote("日记")).toBe("日记/未命名笔记 2.md");

    expect(await readFile(join(root, "日记/日记.md"), "utf8")).toBe("今天散步看见了落叶");
    expect(await readFile(join(root, "日记/日记 2.md"), "utf8")).toBe("# 日记 2\n\n");
    expect((await lib.readFolder("日记")).notes.map((n) => n.title).sort()).toEqual(["日记", "日记 2", "未命名笔记", "未命名笔记 2"]);
  });
});

describe("新建文件夹", () => {
  it("creates a folder inside another, refusing a name that is taken or unusable", async () => {
    const root = await library({ "A/子目录/深层.md": "# 深层" });
    const lib = await openLibrary(root);

    expect(await lib.createFolder("", "A B")).toBe("A B");
    expect(await lib.createFolder("A", "空目录")).toBe("A/空目录");
    await expect(lib.createFolder("A", "子目录")).rejects.toMatchObject({ code: "exists", message: "已经存在“子目录”，请换一个名称。" });
    for (const name of ["", "  ", ".隐藏", "a/b", "a\\b", "问:答", "为什么?", "../出去"]) {
      await expect(lib.createFolder("A", name), name).rejects.toMatchObject({ code: "invalid-name" });
    }

    expect((await lib.readFolder("A")).folders.map((f) => f.path)).toEqual(["A/空目录", "A/子目录"]);
    expect(await lib.readFolder("A/子目录")).toMatchObject({ notes: [{ path: "A/子目录/深层.md" }] });
  });
});

describe("改名", () => {
  it("updates real links to a renamed note but leaves code examples alone", async () => {
    const explained = "链接 [[目标]]\n\n`[[目标]]`\n\n```text\n[[目标]]\n```\n";
    const root = await library({ "目标.md": "# 目标\n", "说明.md": explained });
    const lib = await openLibrary(root);

    expect(await lib.rename("目标.md", "新目标")).toEqual({ path: "新目标.md", updated: ["说明.md"] });

    expect(await contents(root)).toEqual({
      "新目标.md": "# 目标\n",
      "说明.md": "链接 [[新目标]]\n\n`[[目标]]`\n\n```text\n[[目标]]\n```\n",
    });
  });

  it("never overwrites: a taken name or an unusable one changes nothing", async () => {
    const files = { "日记.md": "# 日记", "日记 2.md": "# 日记 2", "入口.md": "[[日记]] [[日记 2]]", "归档/日记.md": "# 旧日记", "照片/": "" };
    const root = await library(files);
    const lib = await openLibrary(root);

    await expect(lib.rename("日记 2.md", "日记")).rejects.toMatchObject({ code: "exists", message: "已经存在“日记”，请换一个名称。" });
    await expect(lib.rename("日记 2.md", "照片.md")).resolves.toMatchObject({ path: "照片.md" });
    await expect(lib.rename("照片.md", "日记 2")).resolves.toMatchObject({ path: "日记 2.md" });
    await expect(lib.rename("照片", "归档")).rejects.toMatchObject({ code: "exists", message: "已经存在“归档”，请换一个名称。" });
    await expect(lib.move("日记.md", "归档")).rejects.toMatchObject({ code: "exists" });
    await expect(lib.rename("日记.md", "../不应创建")).rejects.toMatchObject({ code: "invalid-name" });

    expect(await contents(root)).toEqual({ ...files, "照片/": undefined });
  });

  it("changes nothing at all when a note linking to it can't be rewritten", async () => {
    const files = { "目标.md": "# 目标", "乙/一.md": "[[目标]]", "甲/二.md": "[二](../目标.md)" };
    const root = await library(files);
    const lib = await openLibrary(root);

    await refuseWrites(join(root, "甲/二.md"), true);
    try {
      await expect(lib.rename("目标.md", "新目标")).rejects.toMatchObject({ code: "write-failed" });
    } finally {
      await refuseWrites(join(root, "甲/二.md"), false);
    }

    expect(await contents(root)).toEqual(files);
  });

  it("can change only the letter case of a name", async () => {
    const root = await library({ "readme.md": "# readme", "入口.md": "[[readme]]" });
    const lib = await openLibrary(root);

    expect(await lib.rename("readme.md", "README")).toEqual({ path: "README.md", updated: ["入口.md"] });

    expect(await contents(root)).toEqual({ "README.md": "# readme", "入口.md": "[[README]]" });
  });
});

describe("移动", () => {
  it("moves a note into a folder, keeping its image and the links to it working", async () => {
    const root = await library({
      "附件/示例.png": "png",
      "图片笔记.md": "# 图片笔记\n![示例.png](附件/示例.png)\n",
      "入口.md": "见 [[图片笔记]]",
      "归档/": "",
    });
    const lib = await openLibrary(root);

    expect(await lib.move("图片笔记.md", "归档")).toEqual({ path: "归档/图片笔记.md", updated: ["入口.md", "归档/图片笔记.md"] });

    expect(await contents(root)).toEqual({
      "附件/示例.png": "png",
      "归档/图片笔记.md": "# 图片笔记\n![示例.png](../附件/示例.png)\n",
      "入口.md": "见 [[归档/图片笔记]]",
    });
  });

  it("moves a folder with its notes, so links into it, out of it and within it all still resolve", async () => {
    const root = await library({
      "附件/图.png": "png",
      "阅读/v1.0.md": "![图](../附件/图.png) [同级](摘记.md#小节) [[摘记]]",
      "阅读/摘记.md": "# 摘记",
      "入口.md": "[[阅读/v1.0|版本]] [摘记](阅读/%E6%91%98%E8%AE%B0.md)",
      "归档/": "",
    });
    const lib = await openLibrary(root);

    expect(await lib.move("阅读", "归档")).toEqual({ path: "归档/阅读", updated: ["入口.md", "归档/阅读/v1.0.md"] });

    expect(await contents(root)).toEqual({
      "附件/图.png": "png",
      "归档/阅读/v1.0.md": "![图](../../附件/图.png) [同级](摘记.md#小节) [[摘记]]",
      "归档/阅读/摘记.md": "# 摘记",
      "入口.md": "[[归档/阅读/v1.0|版本]] [摘记](%E5%BD%92%E6%A1%A3/%E9%98%85%E8%AF%BB/%E6%91%98%E8%AE%B0.md)",
    });
  });

  it("refuses to move a folder into itself, and leaves an item already in place alone", async () => {
    const lib = await openLibrary(await library({ "A/B/笔记.md": "" }));

    await expect(lib.move("A", "A/B")).rejects.toMatchObject({ code: "not-allowed" });
    await expect(lib.move("A", "A")).rejects.toMatchObject({ code: "not-allowed" });
    expect(await lib.move("A/B/笔记.md", "A/B")).toEqual({ path: "A/B/笔记.md", updated: [] });
    await expect(lib.move("", "A")).rejects.toMatchObject({ code: "not-allowed" });
  });
});

describe("移到废纸篓与恢复上次删除", () => {
  it("sends a note to the trash and restores the last one deleted", async () => {
    const { folder: trashed, trash } = await fakeTrash();
    const root = await library({ "日记/散步.md": "# 散步\r\n雨后\r\n", "日记/读书.md": "# 读书" });
    const lib = await openLibrary(root, { trash });

    await lib.trash("日记/读书.md");
    await lib.trash("日记/散步.md");

    expect(await contents(root)).toEqual({});
    expect(await contents(trashed)).toEqual({ "散步.md": "# 散步\r\n雨后\r\n", "读书.md": "# 读书" });
    expect(await lib.restoreLastDeleted()).toBe("日记/散步.md");
    expect(await contents(root)).toEqual({ "日记/散步.md": "# 散步\r\n雨后\r\n" });
    await expect(lib.restoreLastDeleted()).rejects.toMatchObject({ code: "nothing-to-restore" });
  });

  it("restores a deleted folder with everything in it", async () => {
    const { trash } = await fakeTrash();
    const root = await library({ "阅读/摘记.md": "# 摘记", "阅读/图/封面.png": "png", "阅读/空/": "" });
    const lib = await openLibrary(root, { trash });

    await lib.trash("阅读");
    expect((await lib.readFolder()).folders).toEqual([]);

    expect(await lib.restoreLastDeleted()).toBe("阅读");
    expect(await contents(root)).toEqual({ "阅读/摘记.md": "# 摘记", "阅读/图/封面.png": "png" });
    expect((await lib.readFolder("阅读")).folders.map((f) => f.name)).toEqual(["空", "图"]);
  });

  it("does not restore over a note that took the deleted one's place", async () => {
    const { trash } = await fakeTrash();
    const root = await library({ "读书.md": "# 旧的" });
    const lib = await openLibrary(root, { trash });

    await lib.trash("读书.md");
    await writeFile(join(root, "读书.md"), "# 新的");
    await expect(lib.restoreLastDeleted()).rejects.toMatchObject({ code: "exists" });
    expect(await contents(root)).toEqual({ "读书.md": "# 新的" });

    await lib.rename("读书.md", "新读书");
    expect(await lib.restoreLastDeleted()).toBe("读书.md");
    expect(await contents(root)).toEqual({ "读书.md": "# 旧的", "新读书.md": "# 新的" });
  });

  it("keeps the note when the trash refuses it", async () => {
    const root = await library({ "读书.md": "# 读书" });
    const lib = await openLibrary(root, { trash: () => Promise.reject(new Error("废纸篓不可用")) });

    await expect(lib.trash("读书.md")).rejects.toMatchObject({ code: "write-failed", message: "无法移到废纸篓：废纸篓不可用。" });
    expect(await contents(root)).toEqual({ "读书.md": "# 读书" });
    await expect(lib.restoreLastDeleted()).rejects.toMatchObject({ code: "nothing-to-restore" });
    await expect(lib.trash("")).rejects.toMatchObject({ code: "not-allowed" });
  });
});
