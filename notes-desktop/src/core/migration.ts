import { cp, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { notesFolder } from "./spaces";

/** The old app's folder for its own data inside a note library. */
export const legacyFolder = ".留白";
const logName = "操作记录.json";

export type Migration =
  /** Nothing to move: no `.留白/`, or a `.notes/` already there. */
  | { kind: "none" }
  | { kind: "migrated" }
  /** `.留白/` is left exactly as it was; `message` is shown to the user. */
  | { kind: "failed"; message: string };

export interface MigrationOptions {
  /** Moves a folder, by real location, to the system trash: where `.留白/` goes once moved. Without it, it stays. */
  trash?(path: string): Promise<void>;
}

const exists = (path: string) => stat(path).then(
  () => true,
  () => false,
);
const isFolder = (path: string) => stat(path).then(
  (found) => found.isDirectory(),
  () => false,
);

/**
 * Moves the old app's spaces, authoring guide, order and operation log from `.留白/` into
 * `.notes/`, the first time a library with `.留白/` and no `.notes/` opens. Everything is gathered
 * in a staging folder first and swapped in whole, so a move that cannot finish leaves `.留白/` as
 * it was. Once moved, `.留白/` goes to the system trash (never deleted outright), or stays when
 * there is no trash. A library that has `.notes/` already is left alone, both folders as they are.
 * Notes are never touched.
 */
export async function migrateLegacyFolder(root: string, options: MigrationOptions = {}): Promise<Migration> {
  const legacy = join(root, legacyFolder);
  const target = join(root, notesFolder);
  const staging = join(root, `${notesFolder}.migrating`);
  if (!(await exists(legacy)) || (await isFolder(target))) return { kind: "none" };

  try {
    // Something else named `.notes` is in the way. Windows would let the swap below replace a file there,
    // so it is refused here on every platform.
    if (await exists(target)) throw new Error(`已有不是文件夹的 ${notesFolder}`);
    // Left over from a move that was cut short (the app quit, say): it starts again.
    await rm(staging, { recursive: true, force: true });
    await cp(legacy, staging, { recursive: true, force: false });
    // The log names space files by their library path, which moves with them.
    const log = join(staging, logName);
    const text = await readFile(log, "utf8").catch(() => null);
    if (text !== null) await writeFile(log, text.replaceAll(`"${legacyFolder}/`, `"${notesFolder}/`), "utf8");
    await rename(staging, target);
  } catch (error) {
    await rm(staging, { recursive: true, force: true }).catch(() => undefined);
    return {
      kind: "failed",
      message: `无法把旧版的空间和操作记录从 ${legacyFolder}/ 搬进 ${notesFolder}/：${(error as Error).message}。原来的 ${legacyFolder}/ 保持原样，下次打开笔记库时会再试一次。`,
    };
  }
  // Everything is in `.notes/` now; an old folder the trash will not take is harmless where it is.
  await options.trash?.(legacy).catch(() => undefined);
  return { kind: "migrated" };
}
