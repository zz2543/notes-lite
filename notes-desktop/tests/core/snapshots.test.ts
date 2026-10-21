import { existsSync } from "node:fs";
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { entryChanges, entrySummary, logPath, operationLog, snapshotStore, turnEntry, turnSnapshots } from "../../src/core";
import { contents, fakeTrash, library, scratchFolder } from "../support/library";

// 快照 (assistant-spec): before each 一轮 the whole library is snapshotted, so everything the
// assistant changed can be listed afterwards and taken back, whole or one file at a time.

async function setup(files: Record<string, string | Buffer>) {
  const root = await library(files);
  const store = await scratchFolder("notes-desktop-snapshots-");
  const trash = await fakeTrash();
  const snapshots = turnSnapshots(store, root, { trash: trash.trash });
  const write = (path: string, text: string | Buffer) => writeFile(join(root, path), text);
  const remove = (path: string) => rm(join(root, path));
  return { root, store, trash, snapshots, write, remove };
}

describe("按轮快照", () => {
  it("lists what a turn changed and undoes the whole turn", async () => {
    const lib = await setup({ "日记/今天.md": "# 今天\n", "日记/昨天.md": "# 昨天\n", "读书/书单.md": "- 三体\n" });
    const before = await contents(lib.root);

    const id = await lib.snapshots.begin();
    await lib.write("日记/今天.md", "# 今天\n\n跑步五公里\n");
    await lib.remove("日记/昨天.md");
    await lib.write("读书/新书.md", "# 新书\n");
    const turn = await lib.snapshots.finish(id);

    expect(turn.changes.map(({ path, kind }) => ({ path, kind }))).toEqual([
      { path: "日记/今天.md", kind: "modified" },
      { path: "日记/昨天.md", kind: "deleted" },
      { path: "读书/新书.md", kind: "added" },
    ]);

    await lib.snapshots.revert(id);
    expect(await contents(lib.root)).toEqual(before);
  });

  it("counts the lines each note gained and lost, for the review card; an attachment has no lines", async () => {
    const lib = await setup({ "计划.md": "# 计划\n\n- 跑步\n- 读书\n", "旧.md": "一\n二\n", "图.png": Buffer.from([1, 2, 3]) });

    const id = await lib.snapshots.begin();
    await lib.write("计划.md", "# 计划\n\n- 跑步五公里\n- 读书\n- 早睡\n");
    await lib.remove("旧.md");
    await lib.write("新.md", "甲\n乙\n丙");
    await lib.write("图.png", Buffer.from([4, 5, 6, 7]));
    const turn = await lib.snapshots.finish(id);

    expect(turn.changes.map(({ path, lines }) => ({ path, lines }))).toEqual([
      { path: "图.png", lines: undefined },
      { path: "新.md", lines: { added: 3, removed: 0 } },
      { path: "旧.md", lines: { added: 0, removed: 2 } },
      { path: "计划.md", lines: { added: 2, removed: 1 } },
    ]);
  });

  it("shows what a turn did to one note, line by line; an attachment has nothing to show", async () => {
    const lib = await setup({ "计划.md": "# 计划\n\n- 跑步\n- 读书\n", "图.png": Buffer.from([1, 2, 3]) });

    const id = await lib.snapshots.begin();
    await lib.write("计划.md", "# 计划\n\n- 跑步五公里\n- 读书\n");
    await lib.write("新.md", "甲\n");
    await lib.write("图.png", Buffer.from([4, 5]));
    await lib.snapshots.finish(id);

    expect(await lib.snapshots.diff(id, "计划.md")).toEqual([
      { sign: "-", text: "- 跑步" },
      { sign: "+", text: "- 跑步五公里" },
    ]);
    expect(await lib.snapshots.diff(id, "新.md")).toEqual([{ sign: "+", text: "甲" }]);
    expect(await lib.snapshots.diff(id, "图.png")).toBeNull();
    await expect(lib.snapshots.diff(id, "没改.md")).rejects.toMatchObject({ code: "not-found" });
  });

  it("leaves out what the app itself wrote during the turn, so undoing the turn keeps the user's typing", async () => {
    const lib = await setup({ "日记/今天.md": "# 今天\n", "随记.md": "随记\n", "旧.md": "旧\n" });

    const id = await lib.snapshots.begin();
    await lib.write("日记/今天.md", "# 今天\n\n跑步\n");
    // Meanwhile the user goes on typing in another note, which the app autosaves, and trashes one.
    await lib.write("随记.md", "随记\n\n用户自己写的\n");
    await lib.remove("旧.md");
    await lib.snapshots.appWrote(["随记.md", "旧.md"]);
    const turn = await lib.snapshots.finish(id);

    expect(turn.changes.map(({ path, kind }) => ({ path, kind }))).toEqual([{ path: "日记/今天.md", kind: "modified" }]);
    await lib.snapshots.revert(id);
    expect(await contents(lib.root)).toEqual({ "日记/今天.md": "# 今天\n", "随记.md": "随记\n\n用户自己写的\n" });
  });

  it("still counts a file the agent changed after the app last wrote it", async () => {
    const lib = await setup({ "a.md": "A\n" });

    const id = await lib.snapshots.begin();
    await lib.write("a.md", "用户\n");
    await lib.snapshots.appWrote(["a.md"]);
    await lib.write("a.md", "Agent\n");
    const turn = await lib.snapshots.finish(id);

    expect(turn.changes.map(({ path, kind }) => ({ path, kind }))).toEqual([{ path: "a.md", kind: "modified" }]);
    // Between turns nothing is remembered: the next turn counts the file as usual.
    await lib.snapshots.appWrote(["a.md"]);
    const next = await lib.snapshots.begin();
    await lib.write("a.md", "Agent 又改\n");
    expect((await lib.snapshots.finish(next)).changes.map((c) => c.path)).toEqual(["a.md"]);
  });

  it("takes back one file at a time, then the rest of the turn", async () => {
    const lib = await setup({ "a.md": "A\n", "b.md": "B\n" });
    const id = await lib.snapshots.begin();
    await lib.write("a.md", "A2\n");
    await lib.write("b.md", "B2\n");
    await mkdir(join(lib.root, "新文件夹/更深"), { recursive: true });
    await lib.write("新文件夹/更深/c.md", "C\n");
    await lib.snapshots.finish(id);

    const turn = await lib.snapshots.revert(id, "b.md");
    expect(await contents(lib.root)).toEqual({ "a.md": "A2\n", "b.md": "B\n", "新文件夹/更深/c.md": "C\n" });
    expect(turn.changes.find((c) => c.path === "b.md")?.reverted).toBe(true);
    expect(turn.changes.find((c) => c.path === "a.md")?.reverted).toBe(false);

    await lib.snapshots.revert(id);
    expect(await contents(lib.root)).toEqual({ "a.md": "A\n", "b.md": "B\n" });
    expect(existsSync(join(lib.root, "新文件夹")), "folders the turn made go once empty").toBe(false);
    expect(await readdir(lib.trash.folder), "a file the turn added goes to the trash").toEqual(["c.md"]);
  });

  for (const attachments of ["clone", "copy"] as const)
    it(`puts back images the turn rewrote or deleted (${attachments})`, async () => {
      const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 1, 2, 255]);
      const root = await library({ "旅行/海边.md": "![](海边.png)", "旅行/海边.png": png, "旅行/山.jpg": Buffer.from([0xff, 0xd8, 1, 2]) });
      const snapshots = turnSnapshots(await scratchFolder(), root, { attachments });
      const id = await snapshots.begin();
      await writeFile(join(root, "旅行/海边.png"), Buffer.from([1, 2, 3]));
      await rm(join(root, "旅行/山.jpg"));
      await writeFile(join(root, "工作目录外.md"), "也在笔记库里");
      expect((await snapshots.finish(id)).changes.map((c) => `${c.kind} ${c.path}`)).toEqual(["added 工作目录外.md", "deleted 旅行/山.jpg", "modified 旅行/海边.png"]);

      await snapshots.revert(id);
      expect(await readFile(join(root, "旅行/海边.png"))).toEqual(png);
      expect(await readFile(join(root, "旅行/山.jpg"))).toEqual(Buffer.from([0xff, 0xd8, 1, 2]));
      expect(existsSync(join(root, "工作目录外.md"))).toBe(false);
    });

  it("past the copy limit, keeps only what attachments were, and says so", async () => {
    const root = await library({ "a.md": "A", "图.png": Buffer.alloc(2000, 7), "录音.m4a": Buffer.alloc(2000, 3) });
    const snapshots = turnSnapshots(await scratchFolder(), root, { attachments: "copy", copyLimit: 1000 });
    const id = await snapshots.begin();
    await writeFile(join(root, "图.png"), Buffer.alloc(10, 1));
    await writeFile(join(root, "a.md"), "A2");
    const turn = await snapshots.finish(id);
    expect(turn.changes.map((c) => [c.path, c.restorable])).toEqual([
      ["a.md", true],
      ["图.png", false],
    ]);
    expect(await snapshots.usage()).toMatchObject({ attachmentsKept: false });

    await expect(snapshots.revert(id, "图.png")).rejects.toMatchObject({ code: "not-kept" });
    await snapshots.revert(id);
    expect(await readFile(join(root, "a.md"), "utf8")).toBe("A");
    expect(await readFile(join(root, "图.png")), "an attachment it could not keep stays as the turn left it").toEqual(Buffer.alloc(10, 1));
  });

  it("stores an unchanged note once, however many turns keep it", async () => {
    const long = "长".repeat(100_000);
    const lib = await setup({ "长文.md": long, "短.md": "x" });
    await lib.snapshots.finish(await lib.snapshots.begin());
    const first = await lib.snapshots.usage();
    expect(first.bytes).toBeGreaterThan(300_000);

    for (let i = 0; i < 3; i++) {
      const id = await lib.snapshots.begin();
      await lib.write("短.md", `第 ${i} 轮`);
      await lib.snapshots.finish(id);
    }
    expect((await lib.snapshots.usage()).bytes - first.bytes).toBeLessThan(100_000);
  });

  it("lets turns go after 30 days, and everything at once on request", async () => {
    const root = await library({ "a.md": "A", "b.md": "B".repeat(50_000) });
    const store = await scratchFolder();
    let today = new Date("2026-10-01T09:00:00Z");
    const snapshots = turnSnapshots(store, root, { now: () => today });
    const old = await snapshots.begin();
    await writeFile(join(root, "b.md"), "B2");
    await snapshots.finish(old);
    const kept = (await snapshots.usage()).bytes;

    today = new Date("2026-10-30T09:00:00Z");
    await snapshots.clean();
    expect((await snapshots.turn(old)).changes, "29 days on, still there").toHaveLength(1);
    expect((await snapshots.usage()).bytes).toBe(kept);

    today = new Date("2026-11-01T09:00:00Z");
    const recent = await snapshots.begin();
    await writeFile(join(root, "a.md"), "A2");
    await snapshots.finish(recent);
    await expect(snapshots.revert(old), "the turn begun 31 days ago is gone").rejects.toMatchObject({ code: "not-found" });
    expect((await snapshots.usage()).bytes, "with what only it kept").toBeLessThan(kept);
    await snapshots.revert(recent);
    expect(await contents(root)).toEqual({ "a.md": "A", "b.md": "B2" });

    await snapshots.clear();
    expect((await snapshots.usage()).bytes).toBe(0);
    await expect(snapshots.revert(recent)).rejects.toMatchObject({ code: "not-found" });
    const next = await snapshots.begin();
    await rm(join(root, "a.md"));
    await snapshots.finish(next);
    await snapshots.revert(next);
    expect(await contents(root)).toEqual({ "a.md": "A", "b.md": "B2" });
  });

  it("a turn is one entry in the operation log, undone as a whole", async () => {
    const lib = await setup({ "日记/今天.md": "# 今天\n", "日记/图.png": Buffer.from([1, 2, 3]) });
    const log = operationLog(lib.root, { trash: lib.trash.trash, turns: lib.snapshots });
    const before = await contents(lib.root);
    const id = await lib.snapshots.begin();
    await lib.write("日记/今天.md", "# 今天\n\n改过\n");
    await lib.remove("日记/图.png");
    await lib.write("别处.md", "新的\n");
    const [entry] = await log.record([turnEntry(await lib.snapshots.finish(id))]);

    expect(entrySummary(entry!)).toBe("助手一轮：改动 3 个文件");
    expect(entryChanges(entry!)).toEqual([
      { sign: "+", text: "新建 别处.md" },
      { sign: "+", text: "改写 日记/今天.md" },
      { sign: "-", text: "删除 日记/图.png" },
    ]);
    expect(await contents(lib.root), "recording the turn leaves the library's notes alone").toMatchObject({ "别处.md": "新的\n" });

    await log.undo(entry!.id);
    const { [logPath]: _, ...after } = await contents(lib.root);
    expect(after).toEqual(before);
    expect((await log.entries())[0]?.undone).toBe(true);
  });

  it("refuses to undo a turn from the log when a file changed since", async () => {
    const lib = await setup({ "a.md": "A\n" });
    const log = operationLog(lib.root, { turns: lib.snapshots });
    const id = await lib.snapshots.begin();
    await lib.write("a.md", "A2\n");
    const [entry] = await log.record([turnEntry(await lib.snapshots.finish(id))]);
    await lib.write("a.md", "用户又改了，长一点\n");
    await expect(log.undo(entry!.id)).rejects.toMatchObject({ code: "conflict" });
    expect((await log.entries())[0]?.undone).toBe(false);
  });

  it("keeps each library's snapshots apart in the app's folder, and adds them up for 设置", async () => {
    const base = await scratchFolder();
    let today = new Date("2026-10-01T09:00:00Z");
    const store = snapshotStore(base, { now: () => today });
    const one = await library({ "a.md": "一".repeat(10_000) });
    const two = await library({ "a.md": "二".repeat(20_000) });
    const first = await store.library(one).begin();
    await store.library(one).finish(first);
    await store.library(two).finish(await store.library(two).begin());
    expect(await contents(one), "nothing is written into the library").toEqual({ "a.md": "一".repeat(10_000) });
    const both = await store.usage();
    expect(both.bytes).toBeGreaterThan(90_000);
    expect(both.attachmentsKept).toBe(true);

    today = new Date("2026-11-15T09:00:00Z");
    await writeFile(join(two, "a.md"), "短");
    await store.library(two).begin();
    expect((await store.library(one).turn(first)).id).toBe(first);
    await store.clean();
    await expect(store.library(one).turn(first), "cleaned however long since the library was opened").rejects.toMatchObject({ code: "not-found" });
    expect((await store.usage()).bytes, "a library not opened for weeks keeps only its newest snapshot").toBeLessThan(both.bytes);

    await store.clear();
    expect((await store.usage()).bytes).toBe(0);
    const next = await store.library(one).begin();
    await writeFile(join(one, "a.md"), "改");
    await store.library(one).finish(next);
    await store.library(one).revert(next);
    expect(await contents(one)).toEqual({ "a.md": "一".repeat(10_000) });
  });

  it("refuses to take back a file changed again since the turn, and leaves the turn alone", async () => {
    const lib = await setup({ "a.md": "A\n", "b.md": "B\n" });
    const id = await lib.snapshots.begin();
    await lib.write("a.md", "A2\n");
    await lib.write("b.md", "B2\n");
    await lib.snapshots.finish(id);
    await lib.write("b.md", "用户又改了\n");

    await expect(lib.snapshots.revert(id)).rejects.toMatchObject({ code: "conflict" });
    await expect(lib.snapshots.revert(id, "b.md")).rejects.toMatchObject({ code: "conflict" });
    expect(await contents(lib.root)).toEqual({ "a.md": "A2\n", "b.md": "用户又改了\n" });

    await lib.snapshots.revert(id, "a.md");
    expect(await contents(lib.root)).toEqual({ "a.md": "A\n", "b.md": "用户又改了\n" });
  });
});
