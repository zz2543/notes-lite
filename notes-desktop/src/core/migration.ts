import { cp, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { notesFolder } from "./spaces";

/** The old app's folder for its own data inside a note library. */
export const legacyFolder = ".留白";
const logName = "操作记录.json";

export type Migration =
  /** Nothing to move: no `.留白/`. */
  | { kind: "none" }
  | { kind: "migrated" }
  /** `.留白/` is left exactly as it was; `message` is shown to the user. */
  | { kind: "failed"; message: string };

const exists = (path: string) => stat(path).then(
  () => true,
  () => false,
);

/**
 * Moves the old app's spaces, authoring guide, order and operation log from `.留白/` into
 * `.notes/`. Everything is gathered in a staging folder first and swapped in whole, so a move
 * that cannot finish leaves `.留白/` (and any `.notes/`) as they were. What `.notes/` already
 * holds wins over the old copy. Notes are never touched.
 */
export async function migrateLegacyFolder(root: string): Promise<Migration> {
  const legacy = join(root, legacyFolder);
  const target = join(root, notesFolder);
  const staging = join(root, `${notesFolder}.migrating`);
  const previous = join(root, `${notesFolder}.replaced`);
  if (!(await exists(legacy))) return { kind: "none" };

  try {
    // Left over from a move that was cut short (the app quit, say): it starts again.
    await rm(staging, { recursive: true, force: true });
    await rm(previous, { recursive: true, force: true });
    const hadTarget = await exists(target);
    if (hadTarget) await cp(target, staging, { recursive: true, errorOnExist: true, force: false });
    await cp(legacy, staging, { recursive: true, force: false });
    // The log names space files by their library path, which moves with them.
    const log = join(staging, logName);
    const text = await readFile(log, "utf8").catch(() => null);
    if (text !== null) await writeFile(log, text.replaceAll(`"${legacyFolder}/`, `"${notesFolder}/`), "utf8");

    if (hadTarget) await rename(target, previous);
    try {
      await rename(staging, target);
    } catch (error) {
      if (hadTarget) await rename(previous, target);
      throw error;
    }
    await rm(previous, { recursive: true, force: true });
  } catch (error) {
    await rm(staging, { recursive: true, force: true }).catch(() => undefined);
    return {
      kind: "failed",
      message: `无法把旧版的空间和操作记录从 ${legacyFolder}/ 搬进 ${notesFolder}/：${(error as Error).message}。原来的 ${legacyFolder}/ 保持原样，下次打开笔记库时会再试一次。`,
    };
  }
  // Everything is in `.notes/` now; an old folder that will not go away is harmless, since what
  // `.notes/` holds wins the next time round.
  await rm(legacy, { recursive: true, force: true }).catch(() => undefined);
  return { kind: "migrated" };
}
