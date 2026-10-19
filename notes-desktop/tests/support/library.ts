import { mkdir, mkdtemp, readdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { afterEach } from "vitest";

const made: string[] = [];

afterEach(async () => {
  await Promise.all(made.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

/** A scratch folder removed after the test. */
export async function scratchFolder(prefix = "notes-desktop-"): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), prefix));
  made.push(dir);
  return dir;
}

/** A real library on disk; keys ending in "/" are empty folders. */
export async function library(files: Record<string, string>): Promise<string> {
  const root = await scratchFolder();
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

/** Every file under `root` with its text, "/"-separated, for comparing a whole library at once. */
export async function contents(root: string): Promise<Record<string, string>> {
  const files: Record<string, string> = {};
  for (const entry of await readdir(root, { recursive: true, withFileTypes: true })) {
    if (!entry.isFile()) continue;
    const path = join(entry.parentPath, entry.name);
    files[path.slice(root.length + 1).split(/[\\/]/).join("/")] = await readFile(path, "utf8");
  }
  return files;
}

/** Stands in for the system trash: items are moved into a folder of their own. */
export async function fakeTrash(): Promise<{ folder: string; trash(path: string): Promise<void> }> {
  const folder = await scratchFolder("notes-desktop-trash-");
  return { folder, trash: (path) => rename(path, join(folder, basename(path))) };
}
