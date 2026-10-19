import { mkdtemp, mkdir, readdir, readFile, rm, symlink, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { openLibrary } from "../../src/core";
import { refuseWrites } from "../support/disk";

const made: string[] = [];

/** A real library on disk; keys ending in "/" are empty folders. */
async function library(files: Record<string, string>): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "notes-desktop-"));
  made.push(root);
  for (const [path, body] of Object.entries(files)) {
    if (path.endsWith("/")) {
      await mkdir(join(root, path), { recursive: true });
      continue;
    }
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), body);
  }
  return root;
}

afterEach(async () => {
  await Promise.all(made.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe("当前目录内容", () => {
  it("lists direct subfolders before direct notes, without descendants", async () => {
    const lib = await openLibrary(
      await library({
        "A/直属.md": "# 直属",
        "A/子目录/深层.md": "# 深层",
        "A/空目录/": "",
        "A/图片.png": "png",
        "根目录.md": "# 根目录",
      }),
    );

    const a = await lib.readFolder("A");

    expect(a.folders.map((f) => f.path)).toEqual(["A/空目录", "A/子目录"]);
    expect(a.notes.map((n) => n.path)).toEqual(["A/直属.md"]);
    expect(a.notes[0]?.title).toBe("直属");
  });

  it("hides the app's own folders and other hidden entries", async () => {
    const lib = await openLibrary(
      await library({
        ".notes/spaces/健身.html": "<p>",
        ".留白/operations.json": "[]",
        ".草稿.md": "# 草稿",
        "日记/今天.md": "# 今天",
        "读书.md": "# 读书",
      }),
    );

    const root = await lib.readFolder();

    expect(root.folders.map((f) => f.path)).toEqual(["日记"]);
    expect(root.notes.map((n) => n.path)).toEqual(["读书.md"]);
  });

  it("orders notes by last modification, newest first", async () => {
    const root = await library({ "旧.md": "", "新.md": "", "中.md": "" });
    const at = (name: string, day: number) => utimes(join(root, name), new Date(2026, 9, day), new Date(2026, 9, day));
    await Promise.all([at("旧.md", 1), at("中.md", 5), at("新.md", 9)]);
    const lib = await openLibrary(root);

    const { notes } = await lib.readFolder();

    expect(notes.map((n) => n.title)).toEqual(["新", "中", "旧"]);
  });

  it("tells which subfolders can be expanded further", async () => {
    const lib = await openLibrary(
      await library({ "学习/英语/单词.md": "", "日记/今天.md": "", "附件/.notes/": "" }),
    );

    const { folders } = await lib.readFolder();

    expect(folders.map((f) => [f.name, f.hasSubfolders])).toEqual([
      ["附件", false],
      ["日记", false],
      ["学习", true],
    ]);
  });
});

describe("笔记原文", () => {
  it("reads a note's Markdown exactly as stored", async () => {
    const source = "# 散步\r\n\r\n- 雨后  \r\n- 小路\t\r\n";
    const lib = await openLibrary(await library({ "日记/散步.md": source }));

    expect(await lib.readNote("日记/散步.md")).toBe(source);
  });
});

describe("库内路径", () => {
  it("refuses paths that leave the library or reach hidden app data", async () => {
    const outside = await library({ "秘密.md": "# 秘密" });
    const root = await library({ ".notes/order.json": "{}", "日记/今天.md": "# 今天" });
    await symlink(outside, join(root, "外链"), "junction");
    const lib = await openLibrary(root);

    for (const path of ["../秘密.md", join(outside, "秘密.md"), "外链/秘密.md", ".notes/order.json", "日记/../../秘密.md"]) {
      await expect(lib.readNote(path), path).rejects.toMatchObject({ code: "outside-library" });
    }
    await expect(lib.readFolder("..")).rejects.toMatchObject({ code: "outside-library" });
    await expect(lib.readFolder("外链")).rejects.toMatchObject({ code: "outside-library" });
    expect((await lib.readFolder()).folders.map((f) => f.path)).toEqual(["日记"]);
  });
});

describe("打开笔记库", () => {
  it("refuses a location that is not an existing folder", async () => {
    const root = await library({ "读书.md": "# 读书" });

    await expect(openLibrary(join(root, "不存在"))).rejects.toMatchObject({ code: "not-a-folder" });
    await expect(openLibrary(join(root, "读书.md"))).rejects.toMatchObject({ code: "not-a-folder" });
  });
});

describe("保存笔记", () => {
  it("writes the note exactly as typed", async () => {
    const before = "# 散步\r\n\r\n雨后\r\n";
    const typed = "# 散步\r\n\r\n雨后，青苔  \r\n- 小路\t\r\n";
    const root = await library({ "日记/散步.md": before });
    const lib = await openLibrary(root);

    await lib.saveNote("日记/散步.md", typed, before);

    expect(await readFile(join(root, "日记/散步.md"), "utf8")).toBe(typed);
  });

  it("refuses to overwrite a note that changed on disk since it was read", async () => {
    const root = await library({ "读书.md": "# 读书\n" });
    const lib = await openLibrary(root);
    await writeFile(join(root, "读书.md"), "# 读书\n\n同步工具写入的一段\n");

    await expect(lib.saveNote("读书.md", "# 读书\n\n我的输入\n", "# 读书\n")).rejects.toMatchObject({ code: "conflict" });
    expect(await readFile(join(root, "读书.md"), "utf8")).toBe("# 读书\n\n同步工具写入的一段\n");
  });

  it("leaves the note untouched when the disk refuses the write, and saves on retry", async () => {
    const root = await library({ "日记/散步.md": "# 散步\n" });
    const note = join(root, "日记/散步.md");
    const lib = await openLibrary(root);

    await refuseWrites(note, true);
    await expect(lib.saveNote("日记/散步.md", "# 散步\n\n雨后\n", "# 散步\n")).rejects.toMatchObject({
      code: "write-failed",
      message: "无法保存“散步”：没有写入权限。",
    });
    await refuseWrites(note, false);

    expect(await readFile(note, "utf8")).toBe("# 散步\n");
    expect(await readdir(join(root, "日记"))).toEqual(["散步.md"]);
    await lib.saveNote("日记/散步.md", "# 散步\n\n雨后\n", "# 散步\n");
    expect(await readFile(note, "utf8")).toBe("# 散步\n\n雨后\n");
  });
});
