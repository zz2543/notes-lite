// 快照 (assistant-spec, ADR 0005): before each 一轮 the whole library is snapshotted into the app's
// own data folder, never into the library, so whatever the assistant changed can be listed once the
// turn is over and taken back, the whole turn or one file at a time.
//
// Each snapshot is a manifest (path → size, modified time and where its bytes are kept). Text goes
// into a store keyed by its content, so a file kept in a hundred snapshots is stored once; a file
// whose size and modified time have not changed since the last snapshot is not read again. Only the
// newest manifest is held in memory.
import { execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { copyFile, mkdir, readdir, readFile, rename, rm, rmdir, stat, utimes, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { logPath } from "./operationLog";
import { serialized } from "./serialized";

const retention = 30 * 86_400_000;

export type ChangeKind = "added" | "modified" | "deleted";

export interface TurnChange {
  /** Library-relative, "/"-separated. */
  path: string;
  kind: ChangeKind;
  /** False for an attachment the snapshot could only note the size and time of: it cannot be put back. */
  restorable: boolean;
  /** Taken back since, on its own or with the whole turn. */
  reverted: boolean;
}

export class SnapshotError extends Error {
  constructor(
    readonly code: "not-found" | "conflict" | "not-kept",
    message: string,
  ) {
    super(message);
    this.name = "SnapshotError";
  }
}

const changedSince = (path: string) => new SnapshotError("conflict", `${path} 在这一轮之后又被修改过，为避免覆盖，没有撤销。`);

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
  /**
   * How attachments (anything that is not text) are kept: "clone" makes copy-on-write clones (APFS),
   * which cost no time or space until a file changes; "copy" copies them whole. The platform's by default.
   */
  attachments?: "clone" | "copy";
  /** With "copy": once a library's attachments add up to more than this, only what they were (size and time) is kept. About 10 GB by default. */
  copyLimit?: number;
}

/** Files kept as text in the content store; anything else is an attachment. */
const textExtensions = new Set(["md", "markdown", "txt", "html", "htm", "css", "js", "mjs", "json", "csv", "tsv", "yaml", "yml", "xml", "svg", "canvas"]);
const isText = (path: string) => textExtensions.has(path.slice(path.lastIndexOf(".") + 1).toLowerCase());

/** Never part of a snapshot: version control, system litter, and the operation log, which records the turns themselves. */
const skipped = (path: string) => {
  const name = path.slice(path.lastIndexOf("/") + 1);
  return name === ".git" || name === ".DS_Store" || name === "Thumbs.db" || path === logPath || path === ".留白/操作记录.json";
};

export interface TurnSnapshots {
  /** Snapshots the library before a turn; answers the turn's id. */
  begin(): Promise<string>;
  /**
   * Snapshots the library ahead of any turn (in the background, when the 助手栏 opens), so a turn's own
   * start only looks at what changed since. On Windows this is where attachments are first copied.
   */
  baseline(): Promise<void>;
  /** Snapshots it again once the turn is over; answers what the turn changed. */
  finish(id: string): Promise<Turn>;
  /**
   * Puts back what the turn changed: one file, or everything not yet taken back. Refused, with
   * nothing touched, when any of those files has changed again since the turn.
   */
  revert(id: string, path?: string): Promise<Turn>;
  /** A finished turn and what it changed. */
  turn(id: string): Promise<Turn>;
  /** How much disk the snapshots take. */
  usage(): Promise<SnapshotUsage>;
  /** Lets turns begun more than 30 days ago go, with whatever only they kept. Each turn's start does this too. */
  clean(): Promise<void>;
  /** Lets every snapshot go now (设置 › 立即清理); no turn so far can be taken back after. */
  clear(): Promise<void>;
}

export interface SnapshotUsage {
  bytes: number;
  /** False when the library's attachments were too large to copy, so only their size and time are kept. */
  attachmentsKept: boolean;
}

/** The bytes of every file under `folder`; 0 when there is none. */
async function sizeOf(folder: string): Promise<number> {
  const entries = await readdir(folder, { withFileTypes: true, recursive: true }).catch(() => []);
  let bytes = 0;
  for (const entry of entries) if (entry.isFile()) bytes += (await stat(join(entry.parentPath, entry.name))).size;
  return bytes;
}

interface FileState {
  size: number;
  mtimeMs: number;
  /** Where its bytes are kept, relative to the store; none for an attachment only noted. */
  blob?: string;
}

interface Manifest {
  id: string;
  date: string;
  files: Record<string, FileState>;
  folders: string[];
  attachmentsKept: boolean;
}

interface StoredTurn extends Turn {
  before: string;
  after?: string;
}

/**
 * Copies a file as a copy-on-write clone where the disk can (APFS: `cp -c`, since Node's copyFile
 * does not clone on macOS; elsewhere copyFile's own clone, as on ReFS or Btrfs), or whole.
 */
async function cloneFile(from: string, to: string) {
  if (process.platform === "darwin") {
    const cloned = await new Promise<boolean>((done) => execFile("/bin/cp", ["-c", from, to], (error) => done(!error)));
    if (cloned) return;
  }
  await copyFile(from, to, constants.COPYFILE_FICLONE);
}

/** Runs `work` over `items`, a few at a time. */
async function inParallel<T>(items: T[], work: (item: T) => Promise<void>, width = 8) {
  let next = 0;
  const lane = async () => {
    while (next < items.length) await work(items[next++]!);
  };
  await Promise.all(Array.from({ length: Math.min(width, items.length) }, lane));
}

/** The library's files and folders, by "/"-separated path. */
async function walk(root: string) {
  const found = new Map<string, { size: number; mtimeMs: number }>();
  const folders: string[] = [];
  const visit = async (folder: string, prefix: string) => {
    for (const entry of await readdir(folder, { withFileTypes: true })) {
      const path = prefix + entry.name;
      if (skipped(path)) continue;
      if (entry.isDirectory()) {
        folders.push(path);
        await visit(join(folder, entry.name), `${path}/`);
      }
      else if (entry.isFile()) {
        const info = await stat(join(folder, entry.name));
        found.set(path, { size: info.size, mtimeMs: info.mtimeMs });
      }
    }
  };
  await visit(root, "");
  return { files: found, folders };
}

export function turnSnapshots(store: string, root: string, options: SnapshotOptions = {}): TurnSnapshots {
  const now = () => options.now?.() ?? new Date();
  const at = (path: string) => join(root, ...path.split("/"));
  const blobAt = (blob: string) => join(store, ...blob.split("/"));
  const attachments = options.attachments ?? (process.platform === "darwin" ? "clone" : "copy");
  const copyLimit = options.copyLimit ?? 10 * 1024 ** 3;
  const manifestAt = (id: string) => join(store, "snapshots", `${id}.json`);
  const turnAt = (id: string) => join(store, "turns", `${id}.json`);
  const writeJson = async (file: string, value: unknown) => {
    await mkdir(dirname(file), { recursive: true });
    await writeFile(`${file}.tmp`, JSON.stringify(value));
    await rename(`${file}.tmp`, file);
  };
  const readJson = async <T>(file: string): Promise<T> => JSON.parse(await readFile(file, "utf8")) as T;

  let latest: Manifest | null = null;

  /** Text goes into the content store, once per content. */
  const keepText = async (path: string): Promise<string> => {
    const bytes = await readFile(at(path));
    const hash = createHash("sha256").update(bytes).digest("hex");
    const blob = `objects/${hash.slice(0, 2)}/${hash}`;
    const file = blobAt(blob);
    await mkdir(dirname(file), { recursive: true });
    await writeFile(file, bytes, { flag: "wx" }).catch((error: NodeJS.ErrnoException) => {
      if (error.code !== "EEXIST") throw error;
    });
    return blob;
  };

  /** An attachment is cloned (or copied) as it is; only a changed one is kept again. */
  const keepAttachment = async (path: string): Promise<string> => {
    const blob = `files/${randomUUID()}`;
    await mkdir(join(store, "files"), { recursive: true });
    await (attachments === "clone" ? cloneFile(at(path), blobAt(blob)) : copyFile(at(path), blobAt(blob)));
    return blob;
  };

  const snapshot = async (): Promise<Manifest> => {
    latest ??= await newestManifest();
    const files: Record<string, FileState> = {};
    const found = await walk(root);
    let attachmentBytes = 0;
    for (const [path, { size }] of found.files) if (!isText(path)) attachmentBytes += size;
    const attachmentsKept = attachments === "clone" || attachmentBytes <= copyLimit;
    await inParallel([...found.files], async ([path, { size, mtimeMs }]) => {
      const known = latest?.files[path];
      const text = isText(path);
      const reuse = known && known.size === size && known.mtimeMs === mtimeMs && (known.blob !== undefined || !attachmentsKept);
      const blob = reuse ? known.blob : text ? await keepText(path) : attachmentsKept ? await keepAttachment(path) : undefined;
      files[path] = blob === undefined ? { size, mtimeMs } : { size, mtimeMs, blob };
    });
    const manifest: Manifest = { id: randomUUID(), date: now().toISOString(), files, folders: found.folders, attachmentsKept };
    await writeJson(manifestAt(manifest.id), manifest);
    latest = manifest;
    return manifest;
  };

  /** The last snapshot taken, from an earlier run: what the next one compares sizes and times with. */
  const newestManifest = async (): Promise<Manifest | null> => {
    const names = await readdir(join(store, "snapshots")).catch(() => []);
    let newest: Manifest | null = null;
    for (const name of names.filter((n) => n.endsWith(".json"))) {
      const manifest = await readJson<Manifest>(join(store, "snapshots", name)).catch(() => null);
      if (manifest && (!newest || manifest.date > newest.date)) newest = manifest;
    }
    return newest;
  };

  const restore = async (path: string, state: FileState) => {
    const target = at(path);
    await mkdir(dirname(target), { recursive: true });
    const temp = join(dirname(target), `.${randomUUID()}.restoring`);
    try {
      await cloneFile(blobAt(state.blob!), temp);
      await utimes(temp, new Date(), new Date(state.mtimeMs));
      await rename(temp, target);
    } catch (error) {
      await rm(temp, { force: true });
      throw error;
    }
  };

  const begin = async () => {
    await expire();
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
      if (!old) changes.push({ path, kind: "added", restorable: true, reverted: false });
      else if (isText(path) ? old.blob !== state.blob : old.size !== state.size || old.mtimeMs !== state.mtimeMs)
        changes.push({ path, kind: "modified", restorable: old.blob !== undefined, reverted: false });
    }
    for (const [path, old] of Object.entries(before.files))
      if (!after.files[path]) changes.push({ path, kind: "deleted", restorable: old.blob !== undefined, reverted: false });
    changes.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
    const done: StoredTurn = { ...turn, after: after.id, changes };
    await writeJson(turnAt(id), done);
    return { id, date: done.date, changes };
  };

  const loadTurn = async (id: string) => {
    const turn = await readJson<StoredTurn>(turnAt(id)).catch(() => null);
    if (!turn?.after) throw new SnapshotError("not-found", "找不到这一轮的快照，它可能已超过 30 天被清理。");
    const [before, after] = await Promise.all([readJson<Manifest>(manifestAt(turn.before)), readJson<Manifest>(manifestAt(turn.after))]).catch(() => {
      throw new SnapshotError("not-found", "找不到这一轮的快照，它可能已超过 30 天被清理。");
    });
    return { turn, before, after };
  };

  /** Whether a file is still as the turn left it. */
  const asLeft = async (change: TurnChange, after: Manifest) => {
    const now = await stat(at(change.path)).catch(() => null);
    if (change.kind === "deleted") return now === null;
    const left = after.files[change.path]!;
    return now !== null && now.isFile() && now.size === left.size && now.mtimeMs === left.mtimeMs;
  };

  const revert = async (id: string, path?: string): Promise<Turn> => {
    const { turn, before, after } = await loadTurn(id);
    const chosen = turn.changes.filter((change) => !change.reverted && change.restorable && (path === undefined || change.path === path));
    if (path !== undefined) {
      const change = turn.changes.find((c) => c.path === path);
      if (!change) throw new SnapshotError("not-found", `这一轮没有改动 ${path}。`);
      if (!change.restorable) throw new SnapshotError("not-kept", `${path} 只记录了大小和时间，无法撤回。`);
    }
    for (const change of chosen) if (!(await asLeft(change, after))) throw changedSince(change.path);
    for (const change of chosen) {
      if (change.kind === "added") {
        if (options.trash) await options.trash(at(change.path));
        else await rm(at(change.path));
      } else await restore(change.path, before.files[change.path]!);
      change.reverted = true;
      await writeJson(turnAt(id), turn);
    }
    if (path === undefined) {
      // Folders the turn made go once empty, deepest first; folders it removed come back.
      const had = new Set(before.folders);
      for (const folder of after.folders.filter((f) => !had.has(f)).reverse()) await rmdir(at(folder)).catch(() => undefined);
      for (const folder of before.folders) await mkdir(at(folder), { recursive: true });
    }
    return { id, date: turn.date, changes: turn.changes };
  };

  const usage = async (): Promise<SnapshotUsage> => {
    latest ??= await newestManifest();
    return { bytes: await sizeOf(store), attachmentsKept: latest?.attachmentsKept ?? true };
  };

  const turn = async (id: string): Promise<Turn> => {
    const { turn: found } = await loadTurn(id);
    return { id, date: found.date, changes: found.changes };
  };

  /** Drops expired turns, every snapshot but the newest that no turn left needs, and what nothing refers to any more. */
  const expire = async () => {
    const cutoff = now().getTime() - retention;
    const needed = new Set<string>();
    for (const name of await readdir(join(store, "turns")).catch(() => [])) {
      if (!name.endsWith(".json")) continue;
      const found = await readJson<StoredTurn>(join(store, "turns", name)).catch(() => null);
      if (found && Date.parse(found.date) >= cutoff) {
        needed.add(found.before);
        if (found.after) needed.add(found.after);
      } else await rm(join(store, "turns", name), { force: true });
    }
    latest ??= await newestManifest();
    if (latest) needed.add(latest.id);
    const blobs = new Set<string>();
    for (const name of await readdir(join(store, "snapshots")).catch(() => [])) {
      const id = name.replace(/\.json$/, "");
      if (!needed.has(id)) {
        await rm(join(store, "snapshots", name), { force: true });
        continue;
      }
      const manifest = await readJson<Manifest>(join(store, "snapshots", name)).catch(() => null);
      for (const state of Object.values(manifest?.files ?? {})) if (state.blob) blobs.add(state.blob);
    }
    for (const kind of ["objects", "files"])
      for (const entry of await readdir(join(store, kind), { recursive: true, withFileTypes: true }).catch(() => [])) {
        if (!entry.isFile()) continue;
        const file = join(entry.parentPath, entry.name);
        const blob = relative(store, file).split(sep).join("/");
        if (!blobs.has(blob)) await rm(file, { force: true });
      }
  };

  const clear = async () => {
    latest = null;
    await rm(store, { recursive: true, force: true });
  };

  // One library's snapshots change one step at a time.
  const queued = <A extends unknown[], T>(run: (...args: A) => Promise<T>) => (...args: A) => serialized(`snapshots:${store}`, () => run(...args));

  return {
    begin: queued(begin),
    baseline: queued(async () => void (await snapshot())),
    finish: queued(finish),
    revert: queued(revert),
    turn: queued(turn),
    usage: queued(usage),
    clean: queued(expire),
    clear: queued(clear),
  };
}

export interface SnapshotStore {
  /** The snapshots of the library at `root`, kept in a folder of their own. */
  library(root: string): TurnSnapshots;
  /** All libraries' snapshots together, for 设置. */
  usage(): Promise<SnapshotUsage>;
  /** Lets every library's turns go after 30 days, however long since the library was opened. */
  clean(): Promise<void>;
  /** Lets every snapshot of every library go now. */
  clear(): Promise<void>;
}

/** Every library's snapshots, under `base` in the app's own data folder: never inside a library. */
export function snapshotStore(base: string, options: SnapshotOptions = {}): SnapshotStore {
  const opened = new Map<string, TurnSnapshots>();
  const folderOf = (root: string) => join(base, createHash("sha256").update(resolve(root)).digest("hex").slice(0, 16));
  const nameFile = "library.txt";

  const library = (root: string) => {
    const folder = folderOf(root);
    let snapshots = opened.get(folder);
    if (!snapshots) {
      const inner = turnSnapshots(folder, root, options);
      // The folder says which library it belongs to, so it can be cleaned while another is open.
      const named = () => mkdir(folder, { recursive: true }).then(() => writeFile(join(folder, nameFile), root));
      snapshots = { ...inner, begin: () => named().then(inner.begin), baseline: () => named().then(inner.baseline) };
      opened.set(folder, snapshots);
    }
    return snapshots;
  };

  const all = async () => {
    const found: TurnSnapshots[] = [];
    for (const entry of await readdir(base, { withFileTypes: true }).catch(() => [])) {
      if (!entry.isDirectory()) continue;
      const root = await readFile(join(base, entry.name, nameFile), "utf8").catch(() => null);
      if (root !== null) found.push(library(root));
    }
    return found;
  };

  return {
    library,
    usage: async () => {
      const each = await Promise.all((await all()).map((snapshots) => snapshots.usage()));
      return { bytes: each.reduce((sum, u) => sum + u.bytes, 0), attachmentsKept: each.every((u) => u.attachmentsKept) };
    },
    clean: async () => {
      for (const snapshots of await all()) await snapshots.clean();
    },
    clear: async () => {
      for (const snapshots of await all()) await snapshots.clear();
    },
  };
}
