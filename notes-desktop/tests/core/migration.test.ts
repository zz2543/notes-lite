import { chmod, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { migrateLegacyFolder, spaceLibrary } from "../../src/core";
import { contents, library } from "../support/library";

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
  it("moves the spaces, the guide, the order and the operation log into .notes/, leaving notes as they are", async () => {
    const root = await library({ ...legacy, ...notes });

    expect(await migrateLegacyFolder(root)).toEqual({ kind: "migrated" });

    expect(await contents(root)).toEqual({
      ...notes,
      ".notes/空间/健身.html": legacy[".留白/空间/健身.html"],
      ".notes/空间/编写说明.md": "旧版编写说明",
      ".notes/空间/顺序.json": '["健身"]',
      ".notes/操作记录.json": '[{"path":".notes/空间/健身.html","kind":"writePage"},{"path":"健身/训练.md","kind":"append"}]',
    });
    const spaces = await spaceLibrary(root).spaces();
    expect(spaces.map((s) => [s.name, s.icon, s.hasPage])).toEqual([["健身", "🏋️", true]]);
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

  it("adds to a .notes/ that already exists, keeping what is there, and clears a half-done earlier attempt", async () => {
    const root = await library({
      ...legacy,
      ".留白/空间/雅思.html": '<meta name="lb-scope" content="英语">',
      ".notes/空间/健身.html": "新版写的主页",
      ".notes/空间/顺序.json": '["健身"]',
      ".notes.migrating/空间/半截.html": "上次中断留下的",
      ...notes,
    });

    expect(await migrateLegacyFolder(root)).toEqual({ kind: "migrated" });

    const files = await contents(root);
    expect(files[".notes/空间/健身.html"]).toBe("新版写的主页");
    expect(files[".notes/空间/雅思.html"]).toBe('<meta name="lb-scope" content="英语">');
    expect(files[".notes/操作记录.json"]).toContain(".notes/空间/健身.html");
    expect(Object.keys(files).filter((path) => !path.startsWith(".notes/")).sort()).toEqual(Object.keys(notes).sort());
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
