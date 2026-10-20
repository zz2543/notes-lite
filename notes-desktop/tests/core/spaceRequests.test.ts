import { symlink } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { expandPlaceholders, spaceLibrary, spaceRequests } from "../../src/core";
import { code, fitnessLibrary, result, today } from "../support/spaces";

// Ported from the old SpaceAPITests: one request from a space homepage in, one JSON-ready reply
// out, checked against a real library on disk.

type Records = { records: Array<Record<string, unknown>>; fields: Array<{ name: string; type: string }> };

describe("空间请求：读取", () => {
  it("query returns typed records from the table under a heading", async () => {
    const lib = await fitnessLibrary();
    const { records, fields } = result<Records>(await lib.call("query", "健身/训练记录.md#卧推"));

    expect(records).toHaveLength(3);
    expect(records[1]!["日期"]).toBe("2026-10-14");
    expect(records[1]!["重量"]).toBe(57.5);
    expect(records[1]!["组数"], "empty cells are null").toBeNull();
    expect(records[2]!["_row"]).toBe(2);
    expect(fields.map((f) => f.name)).toEqual(["日期", "动作", "重量", "组数"]);
    expect(fields.map((f) => f.type)).toEqual(["date", "text", "number", "number"]);
  });

  it("query without a heading uses the first table and supports filter, sort and limit", async () => {
    const lib = await fitnessLibrary();
    const query = async (...args: unknown[]) => result<Records>(await lib.call("query", ...args)).records;

    expect(await query("健身/训练记录.md"), "the first table is 卧推").toHaveLength(3);
    expect((await query("健身/训练记录.md#深蹲"))[0]!["重量"]).toBe(80);
    expect((await query("健身/训练记录.md#卧推", { sort: "-日期", limit: 2 })).map((r) => r["日期"])).toEqual(["2026-10-16", "2026-10-14"]);
    expect((await query("健身/训练记录.md#卧推", { filter: { 重量: 60 } })).map((r) => r["日期"])).toEqual(["2026-10-16"]);
    expect(await query("健身/没有这篇.md"), "a missing record table reads as empty").toEqual([]);
  });

  it("placeholders expand to today", async () => {
    const lib = await fitnessLibrary({ "日记/2026-10-18.md": "| 日期 | 事 |\n|---|---|\n| {今天} | 跑步 |\n" });

    expect(result<Records>(await lib.call("query", "日记/{今天}.md")).records).toHaveLength(1);
    expect(result<Records>(await lib.call("query", "日记/{月}.md")).records[0]!["心情"]).toBe("好");
    expect(expandPlaceholders("{年}/{月}/{周}/{今天}", today)).toBe("2026/2026-10/2026-W42/2026-10-18");
    expect(expandPlaceholders("{周}", new Date(2027, 0, 1, 12)), "the ISO week year").toBe("2026-W53");
  });

  it("scope, notes, read and tables see only the scope", async () => {
    const lib = await fitnessLibrary();

    expect(result(await lib.call("scope"))).toEqual({ library: false, folders: ["健身", "日记"] });
    const notes = result<Array<{ path: string; title: string; modified: string }>>(await lib.call("notes"));
    expect(notes.map((n) => n.path).sort()).toEqual(["健身/训练记录.md", "日记/2026-10.md"]);
    expect(notes[0]!.title).toBe("训练记录");
    expect(Number.isNaN(Date.parse(notes[0]!.modified))).toBe(false);
    expect(result<unknown[]>(await lib.call("notes", "日记"))).toHaveLength(1);
    expect(result(await lib.call("read", "日记/2026-10.md"))).toBe("| 日期 | 心情 |\n|---|---|\n| 2026-10-18 | 好 |\n");
    const tables = result<Array<{ source: string }>>(await lib.call("tables"));
    expect(tables.map((t) => t.source)).toEqual(["健身/训练记录.md#卧推", "健身/训练记录.md#深蹲", "日记/2026-10.md"]);
  });

  it("refuses paths outside the scope", async () => {
    const lib = await fitnessLibrary();
    await symlink(join(lib.root, "别处/秘密.md"), join(lib.root, "健身/捷径.md"));
    await symlink(join(lib.root, "别处"), join(lib.root, "健身/捷径目录"), "junction");
    for (const path of [
      "别处/秘密.md",
      "健身/../别处/秘密.md",
      "../外面.md",
      "/etc/passwd",
      "C:/Windows/win.ini",
      "健身\\..\\别处\\秘密.md",
      "健身/捷径.md",
      "健身/捷径目录/秘密.md",
      ".notes/空间/编写说明.md",
      "健身/.隐藏.md",
      ".notes/空间/健身.html",
      ".notes/操作记录.json",
    ]) {
      expect(code(await lib.call("read", path)), path).toBe("outside-scope");
    }
    expect(code(await lib.call("query", "别处/秘密.md"))).toBe("outside-scope");
    expect(code(await lib.call("notes", "别处"))).toBe("outside-scope");
    expect(code(await lib.call("nonsense"))).toBe("invalid");
    expect(code(await spaceRequests(lib.root, "健身").handle("not a request"))).toBe("invalid");
  });

  it("a whole-library scope still refuses the app's own folder", async () => {
    const lib = await fitnessLibrary();
    await spaceLibrary(lib.root).create({ name: "全局", icon: "🌍", scope: { library: true } });

    expect(code(await lib.callAs("全局", "read", "别处/秘密.md"))).toBe("ok");
    expect(code(await lib.callAs("全局", "read", ".notes/空间/健身.html"))).toBe("outside-scope");
    expect(code(await lib.callAs("没有这个空间", "scope"))).toBe("not-found");
  });

  it("page reads the space file itself", async () => {
    const lib = await fitnessLibrary();
    expect(result<string>(await lib.call("page"))).toContain("space-scope");
  });
});
