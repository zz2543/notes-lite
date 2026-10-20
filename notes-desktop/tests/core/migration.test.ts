import { chmod, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { migrateLegacyFolder, spaceLibrary } from "../../src/core";
import { contents, fakeTrash, library } from "../support/library";

// The old app kept its own data in `.留白/`; the new one keeps it in `.notes/`. Checked through
// the files left on disk.
const legacy = {
  ".留白/空间/健身.html": '<meta name="lb-scope" content="健身">\n<meta name="lb-icon" content="🏋️">\n<p>主页</p>',
  ".留白/空间/编写说明.md": "旧版编写说明",
  ".留白/空间/顺序.json": '["健身"]',
  ".留白/操作记录.json": '[{"path":".留白/空间/健身.html","kind":"writePage"},{"path":"健身/训练.md","kind":"append"}]',
};
const notes = { "健身/训练.md": "| 日期 | 重量 |\r\n|---|---|\r\n| 2026-10-18 | 60 |", "根.md": "# 根" };

describe(".留白/ 搬迁", () => {
  it("moves the spaces, the guide, the order and the operation log into .notes/, leaving notes as they are, and sends .留白/ to the trash", async () => {
    const root = await library({ ...legacy, ...notes });
    const trash = await fakeTrash();

    expect(await migrateLegacyFolder(root, { trash: trash.trash })).toEqual({ kind: "migrated" });

    expect(await contents(root)).toEqual({
      ...notes,
      ".notes/空间/健身.html": legacy[".留白/空间/健身.html"],
      ".notes/空间/编写说明.md": "旧版编写说明",
      ".notes/空间/顺序.json": '["健身"]',
      ".notes/操作记录.json": '[{"path":".notes/空间/健身.html","kind":"writePage"},{"path":"健身/训练.md","kind":"append"}]',
    });
    const spaces = await spaceLibrary(root).spaces();
    expect(spaces.map((s) => [s.name, s.icon, s.hasPage])).toEqual([["健身", "🏋️", true]]);
    // The old folder is in the trash, whole: never deleted outright.
    expect(await contents(trash.folder)).toEqual(legacy);
  });

  it("leaves .留白/ where it was when there is no trash to send it to", async () => {
    const root = await library({ ...legacy, ...notes });

    expect(await migrateLegacyFolder(root)).toEqual({ kind: "migrated" });

    const files = await contents(root);
    for (const [path, text] of Object.entries(legacy)) expect(files[path]).toBe(text);
    expect(files[".notes/空间/健身.html"]).toBe(legacy[".留白/空间/健身.html"]);
  });

  it("does nothing for a library without .留白/, or once it has moved", async () => {
    const root = await library(notes);
    expect(await migrateLegacyFolder(root)).toEqual({ kind: "none" });
    expect(await contents(root)).toEqual(notes);

    const moved = await library({ ...legacy, ...notes });
    await migrateLegacyFolder(moved);
    const after = await contents(moved);
    expect(await migrateLegacyFolder(moved)).toEqual({ kind: "none" });
    expect(await contents(moved)).toEqual(after);
  });

  it("leaves both folders alone when .notes/ already exists, so no old 操作记录 entry is lost", async () => {
    const files = {
      ...legacy,
      ".留白/空间/雅思.html": '<meta name="lb-scope" content="英语">',
      ".notes/空间/健身.html": "新版写的主页",
      ".notes/操作记录.json": "[]",
      ...notes,
    };
    const root = await library(files);
    const trash = await fakeTrash();

    expect(await migrateLegacyFolder(root, { trash: trash.trash })).toEqual({ kind: "none" });

    expect(await contents(root)).toEqual(files);
    expect(await contents(trash.folder)).toEqual({});
  });

  it("starts again after an earlier attempt was cut short", async () => {
    const root = await library({ ...legacy, ".notes.migrating/空间/半截.html": "上次中断留下的", ...notes });

    expect(await migrateLegacyFolder(root)).toEqual({ kind: "migrated" });

    const files = await contents(root);
    expect(files[".notes/空间/健身.html"]).toBe(legacy[".留白/空间/健身.html"]);
    expect(Object.keys(files).some((path) => path.includes("半截") || path.startsWith(".notes.migrating"))).toBe(false);
  });

  it("leaves .留白/ exactly as it was when the move cannot finish", async () => {
    const root = await library({ ...legacy, ...notes });
    // Something in the way of `.notes/`: a file of that name.
    await writeFile(join(root, ".notes"), "不是文件夹");

    const result = await migrateLegacyFolder(root);

    expect(result.kind).toBe("failed");
    expect(result.kind === "failed" && result.message).toContain(".留白");
    expect(await contents(root)).toEqual({ ...legacy, ...notes, ".notes": "不是文件夹" });
  });

  it.skipIf(process.platform === "win32")("leaves .留白/ as it was when a file in it cannot be read halfway through", async () => {
    const root = await library({ ...legacy, ".留白/空间/锁住.html": "读不了", ...notes });
    await chmod(join(root, ".留白/空间/锁住.html"), 0o000);
    try {
      const result = await migrateLegacyFolder(root);
      expect(result.kind).toBe("failed");
    } finally {
      await chmod(join(root, ".留白/空间/锁住.html"), 0o644);
    }
    expect(await contents(root)).toEqual({ ...legacy, ".留白/空间/锁住.html": "读不了", ...notes });
  });
});
