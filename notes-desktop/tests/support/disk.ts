import { chmod } from "node:fs/promises";
import { dirname } from "node:path";

/**
 * Makes the disk refuse to replace a note, or lets it again: Windows honors a read-only file,
 * other systems a read-only folder.
 */
export async function refuseWrites(note: string, refuse: boolean) {
  if (process.platform === "win32") await chmod(note, refuse ? 0o444 : 0o644);
  else await chmod(dirname(note), refuse ? 0o555 : 0o755);
}
