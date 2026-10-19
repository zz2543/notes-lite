import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { openLibrary } from "../../src/core";
import { library } from "../support/library";

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
