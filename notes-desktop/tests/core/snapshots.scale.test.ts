import { randomBytes } from "node:crypto";
import { mkdir, statfs, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { turnSnapshots } from "../../src/core";
import { scratchFolder } from "../support/library";

// 快照 at the user's real scale (assistant-spec): about ten thousand notes and 1 GB of attachments.
// Slow and disk-hungry, so it runs only when asked: NOTES_DESKTOP_MEASURE_SNAPSHOTS=1 npx vitest run
// tests/core/snapshots.scale.test.ts. It prints what it measured; the numbers go in ticket 27.

const notes = 10_000;
const attachments = 200;
const attachmentSize = 5 * 1024 * 1024;

const free = async (folder: string) => {
  const s = await statfs(folder);
  return s.bavail * s.bsize;
};
const mb = (bytes: number) => `${(bytes / 1024 / 1024).toFixed(1)} MB`;

async function realScaleLibrary() {
  const root = await scratchFolder("notes-desktop-scale-");
  for (let folder = 0; folder < 100; folder++) {
    await mkdir(join(root, `文件夹 ${folder}`, "图片"), { recursive: true });
    for (let n = 0; n < notes / 100; n++) {
      const body = `# 笔记 ${folder}-${n}\n\n${"这是一段正文，记录一些想法。".repeat(60)}\n`;
      await writeFile(join(root, `文件夹 ${folder}`, `笔记 ${n}.md`), body);
    }
  }
  for (let a = 0; a < attachments; a++) await writeFile(join(root, `文件夹 ${a % 100}`, "图片", `图 ${a}.png`), randomBytes(attachmentSize));
  return root;
}

async function timed<T>(run: () => Promise<T>): Promise<[T, number]> {
  const start = performance.now();
  const value = await run();
  return [value, Math.round(performance.now() - start)];
}

describe.skipIf(!process.env.NOTES_DESKTOP_MEASURE_SNAPSHOTS)("快照：真实规模", () => {
  for (const mode of ["clone", "copy"] as const)
    it(`ten thousand notes and 1 GB of attachments (${mode})`, { timeout: 600_000 }, async () => {
      const root = await realScaleLibrary();
      const store = await scratchFolder("notes-desktop-scale-store-");
      const snapshots = turnSnapshots(store, root, { attachments: mode });
      global.gc?.();
      const heapBefore = process.memoryUsage().heapUsed;
      const freeBefore = await free(store);

      const [, baseline] = await timed(() => snapshots.baseline());
      const freeAfterBaseline = await free(store);
      const [id, begin] = await timed(() => snapshots.begin());
      for (let n = 0; n < 10; n++) await writeFile(join(root, "文件夹 1", `笔记 ${n}.md`), `改过 ${n}\n`);
      await writeFile(join(root, "文件夹 2", "图片", "图 2.png"), randomBytes(1024));
      const [turn, finish] = await timed(() => snapshots.finish(id));
      const [, revert] = await timed(() => snapshots.revert(id));
      const [, secondBegin] = await timed(() => snapshots.begin());
      global.gc?.();
      const heap = process.memoryUsage().heapUsed - heapBefore;
      const usage = await snapshots.usage();

      console.log(
        [
          `mode ${mode}: ${notes} notes, ${attachments} × ${mb(attachmentSize)} attachments`,
          `baseline (first snapshot): ${baseline} ms; disk used ${mb(freeBefore - freeAfterBaseline)} (files in store ${mb(usage.bytes)})`,
          `turn start with nothing changed: ${begin} ms`,
          `turn end (11 files changed): ${finish} ms; undo the turn: ${revert} ms; next turn start: ${secondBegin} ms`,
          `heap held after: ${mb(heap)}`,
        ].join("\n"),
      );
      expect(turn.changes).toHaveLength(11);
    });
});
