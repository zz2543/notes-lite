import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { openLibrary, watchLibrary, type LibraryWatcher } from "../../src/core";

const made: string[] = [];
const watchers: LibraryWatcher[] = [];

async function library(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "notes-desktop-"));
  made.push(root);
  return root;
}

// Generous: CI disks (Windows especially) can be slow to report. Every wait ends as soon as the
// change is seen, so this only bounds a failure.
const patience = { timeout: 10_000, interval: 20 };

/**
 * Watches `root` and returns what it has reported since. A system watcher may start a moment
 * after the call, and may still deliver the folder's own creation, so a hidden probe file is
 * touched until the watcher is seen to be live, and what came before it is dropped.
 */
async function watching(root: string) {
  let batches: string[][] = [];
  const watcher = watchLibrary(root, (paths) => batches.push(paths));
  watchers.push(watcher);
  await vi.waitFor(async () => {
    await writeFile(join(root, ".probe"), String(Math.random()));
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(batches.flat()).toContain(".probe");
  }, patience);
  batches = [];
  return {
    /** Everything reported since the last clear, the probe left out. */
    seen: () => batches.flat().filter((path) => path !== ".probe"),
    batches: () => batches.filter((batch) => batch.some((path) => path !== ".probe")),
    clear: () => (batches = []),
    close: () => watcher.close(),
  };
}

afterEach(async () => {
  // Closed first: Windows will not delete a folder that is being watched.
  for (const watcher of watchers.splice(0)) watcher.close();
  await Promise.all(made.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe("文件监视", { timeout: 30_000 }, () => {
  it("reports notes and folders created, edited and deleted elsewhere, as library-relative paths", async () => {
    const root = await library();
    const changes = await watching(root);

    await mkdir(join(root, "健身"));
    await writeFile(join(root, "健身", "训练.md"), "# 训练\n\n| 日期 |\n|---|\n");
    await vi.waitFor(() => expect(changes.seen()).toEqual(expect.arrayContaining(["健身", "健身/训练.md"])), patience);

    changes.clear();
    await writeFile(join(root, "健身", "训练.md"), "# 训练\n\n| 日期 |\n|---|\n| 周一 |\n");
    await vi.waitFor(() => expect(changes.seen()).toContain("健身/训练.md"), patience);

    changes.clear();
    await rm(join(root, "健身", "训练.md"));
    await vi.waitFor(() => expect(changes.seen()).toContain("健身/训练.md"), patience);
  });

  it("reports changes in the app's hidden folders too, for open space pages", async () => {
    const root = await library();
    const changes = await watching(root);

    await mkdir(join(root, ".notes", "spaces"), { recursive: true });
    await writeFile(join(root, ".notes", "spaces", "健身.html"), '<meta name="lb-scope" content="*">');

    await vi.waitFor(() => expect(changes.seen()).toContain(".notes/spaces/健身.html"), patience);
  });

  it("reports the app's own save as a change to the note, never its temporary file", async () => {
    const root = await library();
    await writeFile(join(root, "日记.md"), "原文");
    const lib = await openLibrary(root);
    const changes = await watching(root);

    await lib.saveNote("日记.md", "我的输入", "原文");

    await vi.waitFor(() => expect(changes.seen()).toContain("日记.md"), patience);
    expect(changes.seen().filter((path) => path !== "日记.md")).toEqual([]);
  });

  it("gathers a burst of changes, like a sync tool's, into a few notices that name each path once", async () => {
    const root = await library();
    const changes = await watching(root);
    const names = Array.from({ length: 20 }, (_, i) => `同步 ${i + 1}.md`);

    await Promise.all(names.map((name) => writeFile(join(root, name), `# ${name}\n`)));

    await vi.waitFor(() => expect(changes.seen()).toEqual(expect.arrayContaining(names)), patience);
    expect(changes.batches().length).toBeLessThan(names.length / 2);
    for (const batch of changes.batches()) expect(new Set(batch).size).toBe(batch.length);
  });

  it("stops reporting once closed", async () => {
    const root = await library();
    const closed = await watching(root);
    const open = await watching(root);

    closed.close();
    await writeFile(join(root, "关闭之后.md"), "");

    // Both would have heard it by the time the open one has.
    await vi.waitFor(() => expect(open.seen()).toContain("关闭之后.md"), patience);
    expect(closed.seen()).toEqual([]);
  });

  it("says so, rather than failing, when the library folder itself is removed", async () => {
    const root = await library();
    await mkdir(join(root, "日记"));
    const changes = await watching(root);

    await rm(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });

    await vi.waitFor(() => expect(changes.seen().length).toBeGreaterThan(0), patience);
  });
});
