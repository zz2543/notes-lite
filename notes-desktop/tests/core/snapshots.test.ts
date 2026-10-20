import { existsSync } from "node:fs";
import { mkdir, readdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { turnSnapshots } from "../../src/core";
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
