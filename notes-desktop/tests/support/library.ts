import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const made: string[] = [];

/** A real library on disk; keys ending in "/" are empty folders. */
export async function library(files: Record<string, string | Buffer>): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "notes-desktop-"));
  made.push(root);
  for (const [path, body] of Object.entries(files)) {
    if (path.endsWith("/")) {
      await mkdir(join(root, path), { recursive: true });
      continue;
    }
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), body);
  }
  return root;
}

/** Removes every library made so far; call from `afterEach`. */
export async function removeLibraries() {
  await Promise.all(made.splice(0).map((root) => rm(root, { recursive: true, force: true })));
}
