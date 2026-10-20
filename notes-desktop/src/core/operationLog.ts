// 操作记录: every write a space homepage makes, kept in the library (`.notes/操作记录.json`) so it
// can be undone one entry at a time, even after a restart. A request that writes several records
// logs one entry per record; entries expire after 30 days. The file format is the old app's, so a
// log moved over from `.留白/` keeps working.
import { randomUUID } from "node:crypto";
import { access, chmod, mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { findTable, insertRow, paddedRow, renderRow, rewriteRows } from "./recordTables";
import { serialized } from "./serialized";
import type { ChangeKind, Turn } from "./snapshots";
import { notesFolder, spaceLibrary } from "./spaces";

export type LogKind = "recordAppend" | "recordUpdate" | "recordRemove" | "noteCreate" | "noteWrite" | "noteRename" | "noteMove" | "noteTrash" | "pageWrite" | "agentTurn";

/** Another note rewritten alongside a rename or move (its links), by its path after the move. */
export interface FileChange {
  path: string;
  before: string;
  after: string;
}

export interface LogEntry {
  id: string;
  /** ISO 8601. */
  date: string;
  /** The space whose homepage wrote it; 助手 for a turn of the assistant. */
  space: string;
  kind: LogKind;
  /** The note (or space file) written; for a rename or move, where it was before. */
  path: string;
  heading?: string | null;
  header?: string[];
  /** Record cells, or a note's whole text, before and after the write. */
  before?: string[];
  after?: string[];
  /** Where the record was among the table's rows. */
  row?: number;
  newPath?: string;
  /** The old app's record of where the system trash put a note. */
  trashed?: string;
  related?: FileChange[];
  /** An assistant turn: its id among the snapshots, and the files it changed. */
  turn?: string;
  files?: Array<{ path: string; kind: ChangeKind }>;
  undone: boolean;
}

/** The log entry for one assistant turn: the whole turn, undone through its snapshots. */
export function turnEntry(turn: Turn): NewLogEntry {
  return { space: "助手", kind: "agentTurn", path: "", turn: turn.id, files: turn.changes.map(({ path, kind }) => ({ path, kind })) };
}

const fileVerbs: Record<ChangeKind, { sign: "-" | "+"; verb: string }> = {
  added: { sign: "+", verb: "新建" },
  deleted: { sign: "-", verb: "删除" },
  modified: { sign: "+", verb: "改写" },
};

export type NewLogEntry = Omit<LogEntry, "id" | "date" | "undone">;

export class OperationLogError extends Error {
  constructor(
    readonly code: "not-found" | "conflict",
    message: string,
  ) {
    super(message);
    this.name = "OperationLogError";
  }
}

const changed = () => new OperationLogError("conflict", "目标在这次操作之后又被修改过，为避免覆盖，没有撤销。");

export const logPath = `${notesFolder}/操作记录.json`;
const retention = 30 * 86_400_000;

const exists = (path: string) => access(path).then(
  () => true,
  () => false,
);

/** Writes a whole file through a temporary one beside it, creating its folder; keeps an existing file's permissions. */
export async function writeWhole(path: string, text: string) {
  await mkdir(dirname(path), { recursive: true });
  const temp = join(dirname(path), `.${basename(path)}.${process.pid}.saving`);
  try {
    const mode = await stat(path).then(
      (found) => found.mode,
      () => null,
    );
    await writeFile(temp, text, "utf8");
    if (mode !== null) await chmod(temp, mode);
    await rename(temp, path);
  } catch (error) {
    await rm(temp, { force: true });
    throw error;
  }
}

const lines = (text: string | undefined) => (text === undefined ? [] : text.split(/\r\n|\r|\n/));

/** Lines removed (`-`) and added (`+`) going from `old` to `now`, in reading order. */
function lineDiff(old: string[], now: string[]): Array<{ sign: "-" | "+"; text: string }> {
  // Longest common subsequence, then walked from the start.
  const lcs = Array.from({ length: old.length + 1 }, () => new Array<number>(now.length + 1).fill(0));
  for (let i = old.length - 1; i >= 0; i--) {
    for (let j = now.length - 1; j >= 0; j--) lcs[i]![j] = old[i] === now[j] ? lcs[i + 1]![j + 1]! + 1 : Math.max(lcs[i + 1]![j]!, lcs[i]![j + 1]!);
  }
  const out: Array<{ sign: "-" | "+"; text: string }> = [];
  let i = 0;
  let j = 0;
  while (i < old.length || j < now.length) {
    if (i < old.length && j < now.length && old[i] === now[j]) {
      i++;
      j++;
    } else if (j >= now.length || (i < old.length && lcs[i + 1]![j]! >= lcs[i]![j + 1]!)) out.push({ sign: "-", text: old[i++]! });
    else out.push({ sign: "+", text: now[j++]! });
  }
  return out;
}

/** What an entry changed, line by line: `-` for what was there before, `+` for what the write left. */
export function entryChanges(entry: LogEntry): Array<{ sign: "-" | "+"; text: string }> {
  const row = (cells: string[] | undefined, sign: "-" | "+") => (cells ? [{ sign, text: renderRow(cells) }] : []);
  switch (entry.kind) {
    case "recordAppend":
      return row(entry.after, "+");
    case "recordRemove":
      return row(entry.before, "-");
    case "recordUpdate":
      return [...row(entry.before, "-"), ...row(entry.after, "+")];
    case "noteCreate":
      return lines(entry.after?.[0]).map((text) => ({ sign: "+", text }));
    case "noteWrite":
    case "pageWrite":
      return lineDiff(lines(entry.before?.[0]), lines(entry.after?.[0]));
    case "noteRename":
    case "noteMove":
      return [
        { sign: "-", text: entry.path },
        { sign: "+", text: entry.newPath ?? "" },
      ];
    case "noteTrash":
      return [{ sign: "-", text: entry.path }];
    case "agentTurn":
      return (entry.files ?? []).map(({ path, kind }) => ({ sign: fileVerbs[kind].sign, text: `${fileVerbs[kind].verb} ${path}` }));
  }
}

/** One line saying what an entry did. */
export function entrySummary(entry: LogEntry): string {
  const table = entry.path + (entry.heading ? `#${entry.heading}` : "");
  const cells = (row: string[] | undefined) => (row ?? []).filter((cell) => cell !== "").join(" · ");
  switch (entry.kind) {
    case "recordAppend":
      return `新增记录 ${cells(entry.after)} → ${table}`;
    case "recordUpdate":
      return `修改记录 ${cells(entry.before)} → ${cells(entry.after)}（${table}）`;
    case "recordRemove":
      return `删除记录 ${cells(entry.before)}（${table}）`;
    case "noteCreate":
      return `新建笔记 ${entry.path}`;
    case "noteWrite":
      return `改写笔记 ${entry.path}`;
    case "noteRename":
      return `改名 ${entry.path} → ${entry.newPath ?? ""}`;
    case "noteMove":
      return `移动 ${entry.path} → ${entry.newPath ?? ""}`;
    case "noteTrash":
      return `移到废纸篓 ${entry.path}`;
    case "pageWrite":
      return `重写空间主页 ${entry.path}`;
    case "agentTurn":
      return `助手一轮：改动 ${entry.files?.length ?? 0} 个文件`;
  }
}

export interface OperationLogOptions {
  now?(): Date;
  /** Moves a file, by real location, to the system trash. */
  trash?(path: string): Promise<void>;
  /** Where assistant turns are taken back from: the library's snapshots. */
  turns?: { revert(id: string): Promise<unknown> };
}

export interface OperationLog {
  /** Unexpired entries, newest first. */
  entries(): Promise<LogEntry[]>;
  /** Logs entries before their write happens; answers them with their ids. */
  record(entries: NewLogEntry[]): Promise<LogEntry[]>;
  /** Drops entries whose write never happened. */
  discard(ids: string[]): Promise<void>;
  /** Takes one entry back, unless what it wrote has changed since. */
  undo(id: string): Promise<LogEntry>;
}

export function operationLog(root: string, options: OperationLogOptions = {}): OperationLog {
  const now = () => options.now?.() ?? new Date();
  const file = join(root, ...logPath.split("/"));
  // Entries name library paths; one that leaves the library is never followed.
  const at = (path: string) => {
    const parts = path.split("/");
    if (parts.some((part) => part === "" || part === "." || part === "..") || /^[a-z]:/i.test(path)) throw changed();
    return join(root, ...parts);
  };
  const textOf = (path: string) => readFile(at(path), "utf8").catch(() => null);

  const save = (entries: LogEntry[]) => writeWhole(file, `${JSON.stringify(entries, null, 2)}\n`);

  /** Unexpired entries in the order they were written; expired ones leave the file as soon as anyone looks. */
  const stored = async (): Promise<LogEntry[]> => {
    let all: LogEntry[];
    try {
      const parsed: unknown = JSON.parse(await readFile(file, "utf8"));
      all = Array.isArray(parsed) ? (parsed as LogEntry[]) : [];
    } catch {
      return [];
    }
    const cutoff = now().getTime() - retention;
    const kept = all.filter((entry) => Date.parse(entry.date) >= cutoff);
    if (kept.length < all.length) await save(kept).catch(() => undefined);
    return kept;
  };

  const record = async (fresh: NewLogEntry[]) => {
    const date = now().toISOString();
    const entries = fresh.map((entry): LogEntry => ({ id: randomUUID().toUpperCase(), date, ...entry, undone: false }));
    if (entries.length > 0) await save([...(await stored()), ...entries]);
    return entries;
  };

  const discard = async (ids: string[]) => save((await stored()).filter((entry) => !ids.includes(entry.id)));

  const trash = async (path: string) => {
    if (!options.trash) throw new Error("没有可用的废纸篓");
    await options.trash(at(path));
  };

  const revertRecord = async (entry: LogEntry) => {
    const text = await textOf(entry.path);
    const table = text === null ? undefined : findTable(text, entry.heading ?? null);
    if (text === null || !table) throw changed();
    const width = table.header.length;
    const rows = table.rows.map((row) => renderRow(paddedRow(row, width)));
    const same = (cells: string[] | undefined) => (cells ? renderRow(paddedRow(cells, width)) : undefined);
    if (entry.kind === "recordAppend") {
      const i = rows.lastIndexOf(same(entry.after) ?? "");
      if (i < 0) throw changed();
      return writeWhole(at(entry.path), rewriteRows(text, table, [i], () => null));
    }
    if (entry.kind === "recordUpdate") {
      if (!entry.before || !entry.after) throw changed();
      const target = same(entry.after);
      const near = entry.row ?? 0;
      const i = rows.reduce((best, row, index) => (row === target && (best < 0 || Math.abs(index - near) < Math.abs(best - near)) ? index : best), -1);
      if (i < 0) throw changed();
      return writeWhole(at(entry.path), rewriteRows(text, table, [i], () => paddedRow(entry.before!, width)));
    }
    if (!entry.before) throw changed();
    return writeWhole(at(entry.path), insertRow(text, table, paddedRow(entry.before, width), entry.row ?? rows.length));
  };

  const revertMove = async (entry: LogEntry) => {
    const newPath = entry.newPath;
    if (!newPath || !(await exists(at(newPath))) || (await exists(at(entry.path)))) throw changed();
    const related = entry.related ?? [];
    for (const change of related) if ((await textOf(change.path)) !== change.after) throw changed();
    // The same all-or-nothing move as the original, in reverse.
    await mkdir(dirname(at(entry.path)), { recursive: true });
    await rename(at(newPath), at(entry.path));
    const written: FileChange[] = [];
    try {
      for (const change of related) {
        const path = change.path === newPath ? entry.path : change.path;
        await writeWhole(at(path), change.before);
        written.push({ ...change, path });
      }
    } catch (error) {
      for (const change of written.reverse()) await writeWhole(at(change.path), change.after).catch(() => undefined);
      await rename(at(entry.path), at(newPath)).catch(() => undefined);
      throw error;
    }
    // Space files follow the note back; a space file that can't be written keeps its paths.
    await spaceLibrary(root).syncPaths(newPath, entry.path).catch(() => undefined);
  };

  const revertTurn = async (entry: LogEntry) => {
    if (!options.turns || !entry.turn) throw new OperationLogError("not-found", "这一轮的快照不在这台电脑上，无法撤销。");
    try {
      await options.turns.revert(entry.turn);
    } catch (error) {
      const code = (error as { code?: unknown }).code;
      if (code === "conflict" || code === "not-found") throw new OperationLogError(code, (error as Error).message);
      throw error;
    }
  };

  const revert = async (entry: LogEntry) => {
    switch (entry.kind) {
      case "recordAppend":
      case "recordUpdate":
      case "recordRemove":
        return revertRecord(entry);
      case "noteCreate":
        if ((await textOf(entry.path)) !== entry.after?.[0]) throw changed();
        return trash(entry.path);
      case "noteWrite":
      case "pageWrite":
        if ((await textOf(entry.path)) !== entry.after?.[0]) throw changed();
        if (entry.before?.[0] !== undefined) return writeWhole(at(entry.path), entry.before[0]);
        return trash(entry.path);
      case "noteRename":
      case "noteMove":
        return revertMove(entry);
      case "agentTurn":
        return revertTurn(entry);
      case "noteTrash":
        if (await exists(at(entry.path))) throw changed();
        if (entry.trashed && (await exists(entry.trashed))) {
          await mkdir(dirname(at(entry.path)), { recursive: true });
          return rename(entry.trashed, at(entry.path));
        }
        if (entry.before?.[0] === undefined) throw changed();
        return writeWhole(at(entry.path), entry.before[0]);
    }
  };

  const undo = (id: string) => serialized(root, async () => {
    const all = await stored();
    const entry = all.find((e) => e.id === id);
    if (!entry) throw new OperationLogError("not-found", "找不到这条操作记录，它可能已超过 30 天被清理。");
    if (entry.undone) throw new OperationLogError("conflict", "这条操作已经撤销过了。");
    await revert(entry);
    entry.undone = true;
    await save(all);
    return entry;
  });

  return { entries: async () => (await stored()).reverse(), record, discard, undo };
}
