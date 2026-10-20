// 快照 (assistant-spec, ADR 0005): before each 一轮 the whole library is snapshotted into the app's
// own data folder, never into the library, so whatever the assistant changed can be listed once the
// turn is over and taken back, the whole turn or one file at a time.
//
// Each snapshot is a manifest (path → size, modified time and where its bytes are kept). Text goes
// into a store keyed by its content, so a file kept in a hundred snapshots is stored once; a file
// whose size and modified time have not changed since the last snapshot is not read again. Only the
// newest manifest is held in memory.
import { createHash, randomUUID } from "node:crypto";
import { copyFile, mkdir, readdir, readFile, rename, rm, stat, utimes, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

export type ChangeKind = "added" | "modified" | "deleted";

export interface TurnChange {
  /** Library-relative, "/"-separated. */
  path: string;
  kind: ChangeKind;
}

export interface Turn {
  id: string;
  /** ISO 8601, when the turn began. */
  date: string;
  changes: TurnChange[];
}

export interface SnapshotOptions {
  now?(): Date;
  /** Moves a file, by real location, to the system trash: where a file the turn added goes when taken back. */
  trash?(path: string): Promise<void>;
}

export interface TurnSnapshots {
  /** Snapshots the library before a turn; answers the turn's id. */
  begin(): Promise<string>;
  /** Snapshots it again once the turn is over; answers what the turn changed. */
  finish(id: string): Promise<Turn>;
  /** Puts back everything the turn changed. */
  revert(id: string): Promise<Turn>;
}

interface FileState {
  size: number;
  mtimeMs: number;
  /** Where its bytes are kept in the store. */
  blob: string;
}

interface Manifest {
  id: string;
  date: string;
  files: Record<string, FileState>;
}

interface StoredTurn extends Turn {
  before: string;
  after?: string;
}

/** The library's files, by "/"-separated path. */
async function walk(root: string): Promise<Map<string, { size: number; mtimeMs: number }>> {
  const found = new Map<string, { size: number; mtimeMs: number }>();
  const visit = async (folder: string, prefix: string) => {
    for (const entry of await readdir(folder, { withFileTypes: true })) {
      const path = prefix + entry.name;
      if (entry.isDirectory()) await visit(join(folder, entry.name), `${path}/`);
      else if (entry.isFile()) {
        const info = await stat(join(folder, entry.name));
        found.set(path, { size: info.size, mtimeMs: info.mtimeMs });
      }
    }
  };
  await visit(root, "");
  return found;
}

export function turnSnapshots(store: string, root: string, options: SnapshotOptions = {}): TurnSnapshots {
  const now = () => options.now?.() ?? new Date();
  const at = (path: string) => join(root, ...path.split("/"));
  const blobAt = (blob: string) => join(store, "objects", blob.slice(0, 2), blob);
  const manifestAt = (id: string) => join(store, "snapshots", `${id}.json`);
  const turnAt = (id: string) => join(store, "turns", `${id}.json`);
  const writeJson = async (file: string, value: unknown) => {
    await mkdir(dirname(file), { recursive: true });
    await writeFile(`${file}.tmp`, JSON.stringify(value));
    await rename(`${file}.tmp`, file);
  };
  const readJson = async <T>(file: string): Promise<T> => JSON.parse(await readFile(file, "utf8")) as T;

  let latest: Manifest | null = null;

  const keep = async (path: string): Promise<string> => {
    const bytes = await readFile(at(path));
    const blob = createHash("sha256").update(bytes).digest("hex");
    const file = blobAt(blob);
    await mkdir(dirname(file), { recursive: true });
    await writeFile(file, bytes, { flag: "wx" }).catch((error: NodeJS.ErrnoException) => {
      if (error.code !== "EEXIST") throw error;
    });
    return blob;
  };

  const snapshot = async (): Promise<Manifest> => {
    const files: Record<string, FileState> = {};
    for (const [path, { size, mtimeMs }] of await walk(root)) {
      const known = latest?.files[path];
      const blob = known && known.size === size && known.mtimeMs === mtimeMs ? known.blob : await keep(path);
      files[path] = { size, mtimeMs, blob };
    }
    const manifest: Manifest = { id: randomUUID(), date: now().toISOString(), files };
    await writeJson(manifestAt(manifest.id), manifest);
    latest = manifest;
    return manifest;
  };

  const restore = async (path: string, state: FileState) => {
    const target = at(path);
    await mkdir(dirname(target), { recursive: true });
    const temp = join(dirname(target), `.${randomUUID()}.restoring`);
    try {
      await copyFile(blobAt(state.blob), temp);
      await utimes(temp, new Date(), new Date(state.mtimeMs));
      await rename(temp, target);
    } catch (error) {
      await rm(temp, { force: true });
      throw error;
    }
  };

  const begin = async () => {
    const before = await snapshot();
    const turn: StoredTurn = { id: randomUUID(), date: before.date, before: before.id, changes: [] };
    await writeJson(turnAt(turn.id), turn);
    return turn.id;
  };

  const finish = async (id: string): Promise<Turn> => {
    const turn = await readJson<StoredTurn>(turnAt(id));
    const before = await readJson<Manifest>(manifestAt(turn.before));
    const after = await snapshot();
    const changes: TurnChange[] = [];
    for (const [path, state] of Object.entries(after.files)) {
      const old = before.files[path];
      if (!old) changes.push({ path, kind: "added" });
      else if (old.blob !== state.blob) changes.push({ path, kind: "modified" });
    }
    for (const path of Object.keys(before.files)) if (!after.files[path]) changes.push({ path, kind: "deleted" });
    changes.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
    const done: StoredTurn = { ...turn, after: after.id, changes };
    await writeJson(turnAt(id), done);
    return { id, date: done.date, changes };
  };

  const revert = async (id: string): Promise<Turn> => {
    const turn = await readJson<StoredTurn>(turnAt(id));
    const before = await readJson<Manifest>(manifestAt(turn.before));
    for (const change of turn.changes) {
      if (change.kind === "added") {
        if (options.trash) await options.trash(at(change.path));
        else await rm(at(change.path));
      } else await restore(change.path, before.files[change.path]!);
    }
    return { id, date: turn.date, changes: turn.changes };
  };

  return { begin, finish, revert };
}
