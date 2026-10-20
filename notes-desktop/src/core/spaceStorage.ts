// A space homepage's own storage (localStorage and the like, spaces-spec #51) lives in a browser
// partition named by a key kept here, in the app's data folder: one per library and space, stable
// across restarts, carried over when the space is renamed in the app, and never handed on to a new
// space that takes a renamed or deleted one's name.
import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { serialized } from "./serialized";

export interface SpaceStorage {
  /** The storage key of the space `name` in the library at `root`. */
  key(root: string, name: string): Promise<string>;
  /** The space was renamed: its storage goes with it. */
  renamed(root: string, from: string, to: string): Promise<void>;
  /** The space was deleted: a new one of that name starts empty. */
  deleted(root: string, name: string): Promise<void>;
}

const hash = (text: string) => createHash("sha256").update(text).digest("hex").slice(0, 32);

export function spaceStorage(file: string): SpaceStorage {
  const id = (root: string, name: string) => `${root}\u0000${name}`;
  const read = async (): Promise<Record<string, string>> => {
    const text = await readFile(file, "utf8").catch(() => null);
    if (text === null) return {};
    try {
      const keys: unknown = JSON.parse(text);
      return typeof keys === "object" && keys !== null ? (keys as Record<string, string>) : {};
    } catch {
      return {};
    }
  };
  const write = async (keys: Record<string, string>) => {
    await mkdir(dirname(file), { recursive: true });
    await writeFile(`${file}.tmp`, JSON.stringify(keys));
    await rename(`${file}.tmp`, file);
  };
  // A space never renamed keeps the key it always had, so storage from before this file is kept.
  const keyIn = (keys: Record<string, string>, root: string, name: string) => keys[id(root, name)] ?? hash(id(root, name));
  const change = (run: (keys: Record<string, string>) => void) =>
    serialized(`space-storage:${file}`, async () => {
      const keys = await read();
      run(keys);
      await write(keys);
    });

  return {
    key: async (root, name) => keyIn(await read(), root, name),
    renamed: (root, from, to) =>
      change((keys) => {
        keys[id(root, to)] = keyIn(keys, root, from);
        keys[id(root, from)] = hash(randomUUID());
      }),
    deleted: (root, name) => change((keys) => void (keys[id(root, name)] = hash(randomUUID()))),
  };
}
