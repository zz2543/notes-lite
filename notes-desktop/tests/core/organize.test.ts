import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { openLibrary } from "../../src/core";
import { contents, library } from "../support/library";

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
