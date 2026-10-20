import { existsSync } from "node:fs";
import { readdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { entryChanges, entrySummary, operationLog, spaceRequests } from "../../src/core";
import { code, fitnessLibrary, result } from "../support/spaces";

// Ported from the old SpaceNoteWriteTests: space homepages managing notes inside their scope, and
// rewriting their own space file.

describe("空间请求：管理笔记", () => {
  it("create and write, then undo each", async () => {
    const lib = await fitnessLibrary();
    const log = operationLog(lib.root, lib.options);
    expect(code(await lib.call("create", "健身/计划.md", "# 计划\n"))).toBe("ok");
    expect(code(await lib.call("create", "健身/计划.md", "x"))).toBe("exists");
    expect(code(await lib.call("write", "健身/计划.md", "# 计划\n\n周一练胸"))).toBe("ok");
    expect(await lib.read("健身/计划.md")).toBe("# 计划\n\n周一练胸");

    const entries = await log.entries();
    expect(entries.map((e) => e.kind)).toEqual(["noteWrite", "noteCreate"]);
    expect(entryChanges(entries[0]!), "the log shows what the write changed").toEqual([{ sign: "+", text: "周一练胸" }]);
    expect(entrySummary(entries[0]!)).toBe("改写笔记 健身/计划.md");
    await log.undo(entries[0]!.id);
    expect(await lib.read("健身/计划.md")).toBe("# 计划\n");
    await log.undo(entries[1]!.id);
    expect(existsSync(join(lib.root, "健身/计划.md")), "undoing a create sends the note to the trash").toBe(false);
    expect(await readdir(lib.trash.folder)).toEqual(["计划.md"]);

    expect(code(await lib.call("create", "别处/x.md", ""))).toBe("outside-scope");
    expect(code(await lib.call("write", "别处/秘密.md", ""))).toBe("outside-scope");
    expect(code(await lib.call("write", "健身/图片.png", ""))).toBe("invalid");
    expect(await lib.read("别处/秘密.md")).toBe("不在范围内");
  });

  it("says which paths each write touched, so a running assistant turn can leave them out", async () => {
    const lib = await fitnessLibrary({ "日记/今天.md": "见 [[训练记录]]" });
    const wrote: string[][] = [];
    const call = (method: string, ...args: unknown[]) =>
      spaceRequests(lib.root, "健身", { ...lib.options, wrote: (paths) => void wrote.push(paths) }).handle({ method, args });

    await call("create", "健身/计划.md", "# 计划\n");
    await call("rename", "健身/训练记录.md", "力量训练");
    await call("query", "健身/力量训练.md#卧推");

    expect(wrote).toEqual([["健身/计划.md"], ["健身/训练记录.md", "健身/力量训练.md", "日记/今天.md"]]);
  });

  it("rename and move update links, and undo together", async () => {
    const lib = await fitnessLibrary({ "日记/今天.md": "见 [[训练记录]] 和 [卧推](../健身/训练记录.md#卧推)" });
    expect(result(await lib.call("rename", "健身/训练记录.md", "力量训练"))).toEqual({ path: "健身/力量训练.md" });
    expect(existsSync(join(lib.root, "健身/力量训练.md"))).toBe(true);
    expect(existsSync(join(lib.root, "健身/训练记录.md"))).toBe(false);
    expect(await lib.read("日记/今天.md"), "links follow the note").toBe("见 [[健身/力量训练]] 和 [卧推](../健身/力量训练.md#卧推)");

    expect(result(await lib.call("move", "健身/力量训练.md", "日记"))).toEqual({ path: "日记/力量训练.md" });
    expect(existsSync(join(lib.root, "日记/力量训练.md"))).toBe(true);
    expect(code(await lib.call("move", "日记/力量训练.md", "别处"))).toBe("outside-scope");
    expect(code(await lib.call("rename", "日记/力量训练.md", "../逃逸"))).toBe("invalid");
    expect(code(await lib.call("rename", "日记/没有.md", "新"))).toBe("not-found");
    expect(code(await lib.call("rename", "日记/力量训练.md", "今天"))).toBe("exists");

    const log = operationLog(lib.root, lib.options);
    expect((await log.entries()).map(entrySummary)).toEqual(["移动 健身/力量训练.md → 日记/力量训练.md", "改名 健身/训练记录.md → 健身/力量训练.md"]);
    for (const entry of await log.entries()) await log.undo(entry.id);
    expect(existsSync(join(lib.root, "健身/训练记录.md"))).toBe(true);
    expect(await lib.read("日记/今天.md")).toBe("见 [[训练记录]] 和 [卧推](../健身/训练记录.md#卧推)");
  });

  it("a homepage's rename moves the paths in space files, and undoing it moves them back", async () => {
    const lib = await fitnessLibrary();
    const spaceFile = ".notes/空间/健身.html";
    await writeFile(join(lib.root, spaceFile), (await lib.read(spaceFile)) + '<space-records source="健身/训练记录.md#卧推"></space-records>\n');
    result(await lib.call("rename", "健身/训练记录.md", "力量训练"));
    expect(await lib.read(spaceFile)).toContain('source="健身/力量训练.md#卧推"');

    const log = operationLog(lib.root, lib.options);
    await log.undo((await log.entries())[0]!.id);
    expect(await lib.read(spaceFile)).toContain('source="健身/训练记录.md#卧推"');
  });

  it("trash sends the note to the trash, and undo brings it back", async () => {
    const lib = await fitnessLibrary();
    const reply = await lib.call("trash", "日记/2026-10.md");
    expect(code(reply)).toBe("ok");
    expect(reply.ok && reply.changes, "the trash counts as one change for the notice").toBe(1);
    expect(existsSync(join(lib.root, "日记/2026-10.md"))).toBe(false);
    expect(await readdir(lib.trash.folder), "the note sits in the system trash").toEqual(["2026-10.md"]);

    const log = operationLog(lib.root, lib.options);
    const entry = (await log.entries())[0]!;
    expect(entry.kind).toBe("noteTrash");
    await log.undo(entry.id);
    expect(await lib.read("日记/2026-10.md")).toBe("| 日期 | 心情 |\n|---|---|\n| 2026-10-18 | 好 |\n");
    expect(code(await lib.call("trash", "日记/没有.md"))).toBe("not-found");
  });

  it("the page can rewrite itself, but not its scope or other space files", async () => {
    const lib = await fitnessLibrary();
    const log = operationLog(lib.root, lib.options);
    const page = result<string>(await lib.call("page"));

    expect(code(await lib.call("writePage", `${page}<p>新主页</p>`))).toBe("ok");
    expect(await lib.read(".notes/空间/健身.html")).toBe(`${page}<p>新主页</p>`);
    expect(code(await lib.call("writePage", page.replace("健身, 日记", "*")))).toBe("scope-change");
    expect(code(await lib.call("writePage", "<p>没有范围</p>")), "dropping space-scope also changes the scope").toBe("scope-change");
    // The old name is the same meta: a page may write either, but not a different scope under it.
    const legacy = page.replace("space-scope", "lb-scope");
    expect(code(await lib.call("writePage", legacy))).toBe("ok");
    expect(code(await lib.call("writePage", legacy.replace("健身, 日记", "*")))).toBe("scope-change");
    expect(code(await lib.call("writePage", `<meta name="lb-scope" content="*">\n${page}`)), "space-scope wins over lb-scope").toBe("ok");
    expect(code(await lib.call("writePage", `<meta name="space-scope" content="*">\n${legacy}`))).toBe("scope-change");
    expect(code(await lib.call("write", ".notes/空间/雅思.html", "x"))).toBe("outside-scope");
    expect(code(await lib.call("write", ".notes/空间/编写说明.md", "x"))).toBe("outside-scope");
    expect(code(await lib.call("write", ".notes/空间/顺序.json", "x"))).toBe("outside-scope");

    for (const entry of await log.entries()) await log.undo(entry.id);
    expect(await lib.read(".notes/空间/健身.html")).toBe(page);
  });

  it("rename is refused when notes outside the scope link to it", async () => {
    const lib = await fitnessLibrary({ "别处/引用.md": "见 [[训练记录]]" });
    const reply = await lib.call("rename", "健身/训练记录.md", "力量训练");

    expect(code(reply)).toBe("outside-scope");
    expect(!reply.ok && reply.error.message).toContain("别处/引用.md");
    expect(existsSync(join(lib.root, "健身/训练记录.md")), "nothing moved").toBe(true);
    expect(await lib.read("别处/引用.md"), "notes outside the scope are never written").toBe("见 [[训练记录]]");
    expect(await operationLog(lib.root, lib.options).entries()).toEqual([]);
  });

  it("undoing a rename refuses when a note it rewrote changed since", async () => {
    const lib = await fitnessLibrary({ "日记/今天.md": "见 [[训练记录]]" });
    await lib.call("rename", "健身/训练记录.md", "力量训练");
    await writeFile(join(lib.root, "日记/今天.md"), "见 [[健身/力量训练]]，又写了一句");
    const log = operationLog(lib.root, lib.options);

    await expect(log.undo((await log.entries())[0]!.id)).rejects.toMatchObject({ code: "conflict" });
    expect(existsSync(join(lib.root, "健身/力量训练.md"))).toBe(true);
  });
});
