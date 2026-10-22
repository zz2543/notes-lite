import { readdir } from "node:fs/promises";
import { join } from "node:path";
import { expect, test } from "vitest";

// macOS and Windows file systems ignore case: two sources whose names differ only by it are one file there,
// and an import of either finds whichever is on disk (markdownView.ts vs MarkdownView.tsx broke the build).
test("no two modules share a name apart from case", async () => {
  // Imports name modules without their extension, so markdownView.ts and MarkdownView.tsx are one import.
  const modules = (await readdir(join(__dirname, "../../src"), { recursive: true })).map(String).filter((file) => /\.(tsx?|mjs|js)$/.test(file));
  const byName = Map.groupBy(modules, (file) => file.replace(/\.[^.]+$/, "").toLowerCase());
  expect([...byName.values()].filter((same) => same.length > 1)).toEqual([]);
});
