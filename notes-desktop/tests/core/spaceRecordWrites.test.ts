import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { operationLog } from "../../src/core";
import { code, fitnessLibrary, result, today } from "../support/spaces";

// Ported from the old SpaceRecordWriteTests: writing records through the page interface, and
// undoing them one record at a time from the operation log.

const day = 86_400_000;

describe("空间请求：写记录与操作记录", () => {
  it("append adds rows at the table's end and keeps the rest of the note", async () => {
    const lib = await fitnessLibrary();
    const reply = await lib.call("append", "健身/训练记录.md#卧推", [
      { 日期: "{今天}", 动作: "卧推", 重量: 62.5, 组数: 5 },
      { 日期: "2026-10-19", 重量: 65 },
    ]);

    expect(result(reply)).toEqual({ count: 2 });
    expect(reply.ok && reply.changes).toBe(2);
    expect(reply.ok && reply.recordChanges).toBe(2);
    const text = await lib.read("健身/训练记录.md");
    expect(text).toContain("| 2026-10-16 | 卧推 | 60 | 5 |\n| 2026-10-18 | 卧推 | 62.5 | 5 |\n| 2026-10-19 |  | 65 |  |\n\n## 深蹲");
    expect(text.endsWith("| 2026-10-15 | 80 |"), "other tables are untouched").toBe(true);
    const entries = await operationLog(lib.root, lib.options).entries();
    expect(entries, "one entry per record").toHaveLength(2);
    expect(entries[0]!.space).toBe("健身");
    expect(entries[0]!.kind).toBe("recordAppend");
  });

  it("append refuses unknown fields and escapes bars", async () => {
    const lib = await fitnessLibrary();
    expect(code(await lib.call("append", "健身/训练记录.md#卧推", { 心情: "好" }))).toBe("unknown-field");
    expect(code(await lib.call("append", "健身/训练记录.md#卧推", { 动作: "a|b\nc" }))).toBe("ok");
    expect(await lib.read("健身/训练记录.md")).toContain("| a\\|b c |");
    const { records } = result<{ records: Array<Record<string, unknown>> }>(await lib.call("query", "健身/训练记录.md#卧推"));
    expect(records.at(-1)!["动作"]).toBe("a|b c");
    expect(code(await lib.call("append", "健身/训练记录.md#卧推", "不是记录"))).toBe("invalid");
  });

  it("append creates missing notes and tables from the header", async () => {
    const lib = await fitnessLibrary();
    expect(code(await lib.call("append", "健身/{月}.md", { 日期: "{今天}", 时长: 30 }, { header: ["日期", "时长", "备注"] }))).toBe("ok");
    expect(await lib.read("健身/2026-10.md")).toBe("# 2026-10\n\n| 日期 | 时长 | 备注 |\n|---|---|---|\n| 2026-10-18 | 30 |  |\n");
    expect(code(await lib.call("append", "健身/训练记录.md#硬拉", { 日期: "2026-10-18", 重量: 100 }))).toBe("ok");
    expect(await lib.read("健身/训练记录.md")).toMatch(/\| 2026-10-15 \| 80 \|\n\n## 硬拉\n\n\| 日期 \| 重量 \|\n\|---\|---\|\n\| 2026-10-18 \| 100 \|\n$/);
    expect(code(await lib.call("append", "新目录/x.md", { a: 1 })), "creating still respects the scope").toBe("outside-scope");
  });

  it("appending to a CRLF note keeps its line breaks", async () => {
    const lib = await fitnessLibrary({ "日记/windows.md": "| 日期 | 事 |\r\n|---|---|\r\n| 2026-10-17 | 写 |\r\n\r\n结尾\r\n" });
    expect(code(await lib.call("append", "日记/windows.md", { 日期: "2026-10-18", 事: "读" }))).toBe("ok");
    expect(await lib.read("日记/windows.md")).toBe("| 日期 | 事 |\r\n|---|---|\r\n| 2026-10-17 | 写 |\r\n| 2026-10-18 | 读 |\r\n\r\n结尾\r\n");
  });

  it("update and remove find records by field or row", async () => {
    const lib = await fitnessLibrary();
    expect(result(await lib.call("update", "健身/训练记录.md#卧推", { 重量: 60 }, { 组数: 6 }))).toEqual({ count: 1 });
    expect(await lib.read("健身/训练记录.md")).toContain("| 2026-10-16 | 卧推 | 60 | 6 |");
    expect(result(await lib.call("remove", "健身/训练记录.md#卧推", { _row: 0 }))).toEqual({ count: 1 });
    expect(await lib.read("健身/训练记录.md")).not.toContain("2026-10-12");
    expect(code(await lib.call("update", "健身/训练记录.md#卧推", { 重量: 60 }, { 体重: 1 }))).toBe("unknown-field");
    expect(code(await lib.call("update", "健身/训练记录.md#卧推", {}, { 组数: 1 }))).toBe("invalid");
    expect(result(await lib.call("remove", "健身/训练记录.md#卧推", { 重量: 999 }))).toEqual({ count: 0 });
    expect((await operationLog(lib.root, lib.options).entries()).map((e) => e.kind), "newest first").toEqual(["recordRemove", "recordUpdate"]);
  });

  it("each record undoes on its own, even after reopening", async () => {
    const lib = await fitnessLibrary();
    await lib.call("append", "健身/训练记录.md#卧推", [
      { 日期: "2026-10-18", 重量: 61 },
      { 日期: "2026-10-19", 重量: 62 },
    ]);
    await lib.call("remove", "健身/训练记录.md#卧推", { 日期: "2026-10-14" });

    // A fresh log, as after relaunching the app.
    const reopened = operationLog(lib.root, lib.options);
    const entries = await reopened.entries();
    expect(entries).toHaveLength(3);
    const firstAppend = entries.find((e) => e.kind === "recordAppend" && e.after?.join(",") === "2026-10-18,,61,")!;
    await reopened.undo(firstAppend.id);
    let text = await lib.read("健身/训练记录.md");
    expect(text).not.toContain("| 2026-10-18 |  | 61 |");
    expect(text, "the other appended record stays").toContain("| 2026-10-19 |  | 62 |  |");

    await reopened.undo(entries.find((e) => e.kind === "recordRemove")!.id);
    text = await lib.read("健身/训练记录.md");
    expect(text, "a removed record returns to its place").toContain("| 2026-10-12 | 卧推 | 55 | 5 |\n| 2026-10-14 | 卧推 | 57.5 |  |\n| 2026-10-16");
    expect((await operationLog(lib.root, lib.options).entries()).find((e) => e.id === firstAppend.id)?.undone).toBe(true);
    await expect(reopened.undo(firstAppend.id), "an entry undoes once").rejects.toMatchObject({ code: "conflict" });
  });

  it("undo refuses when the record changed since", async () => {
    const lib = await fitnessLibrary();
    await lib.call("update", "健身/训练记录.md#卧推", { 日期: "2026-10-16" }, { 重量: 61 });
    const path = join(lib.root, "健身/训练记录.md");
    await writeFile(path, (await readFile(path, "utf8")).replace("| 2026-10-16 | 卧推 | 61 | 5 |", "| 2026-10-16 | 卧推 | 70 | 5 |"));
    const log = operationLog(lib.root, lib.options);

    const refused = log.undo((await log.entries())[0]!.id);
    await expect(refused).rejects.toMatchObject({ code: "conflict" });
    await expect(refused).rejects.toThrow("又被修改过");
    expect(await lib.read("健身/训练记录.md"), "nothing is overwritten").toContain("| 70 |");
  });

  it("entries older than thirty days are pruned", async () => {
    const lib = await fitnessLibrary();
    await lib.call("append", "健身/训练记录.md#卧推", { 日期: "2026-10-18" });
    lib.setClock(new Date(today.getTime() + 29 * day));
    expect(await operationLog(lib.root, lib.options).entries()).toHaveLength(1);
    lib.setClock(new Date(today.getTime() + 31 * day));
    expect(await operationLog(lib.root, lib.options).entries()).toHaveLength(0);
    await lib.call("append", "健身/训练记录.md#卧推", { 日期: "2026-11-18" });
    const stored = await lib.read(".notes/操作记录.json");
    expect(stored, "expired entries leave the file").not.toContain('"2026-10-18"');
    expect(stored).toContain('"2026-11-18"');
  });

  it("reads the old app's log, moved into .notes/", async () => {
    const lib = await fitnessLibrary();
    // As the old app wrote it (Swift's JSONEncoder, ISO 8601 dates without milliseconds).
    const old = [
      {
        after: ["2026-10-17", "卧推", "58", "5"],
        date: "2026-10-17T04:00:00Z",
        header: ["日期", "动作", "重量", "组数"],
        heading: "卧推",
        id: "6F1C2A4E-1D3B-4C55-9E2A-0B7D8F9A1C3E",
        kind: "recordAppend",
        path: "健身/训练记录.md",
        space: "健身",
        undone: false,
      },
    ];
    await writeFile(join(lib.root, ".notes/操作记录.json"), JSON.stringify(old, null, 2));
    await writeFile(join(lib.root, "健身/训练记录.md"), (await lib.read("健身/训练记录.md")).replace("| 2026-10-16 | 卧推 | 60 | 5 |", "| 2026-10-16 | 卧推 | 60 | 5 |\n| 2026-10-17 | 卧推 | 58 | 5 |"));
    const log = operationLog(lib.root, lib.options);

    expect((await log.entries()).map((e) => e.id)).toEqual(["6F1C2A4E-1D3B-4C55-9E2A-0B7D8F9A1C3E"]);
    await log.undo("6F1C2A4E-1D3B-4C55-9E2A-0B7D8F9A1C3E");
    expect(await lib.read("健身/训练记录.md")).not.toContain("2026-10-17");
  });

  it("the log is not reachable through the page interface", async () => {
    const lib = await fitnessLibrary();
    expect(code(await lib.call("read", ".notes/操作记录.json"))).toBe("outside-scope");
  });
});
