// 空间请求: the core side of the page interface. Everything a space homepage does to the library
// arrives here as one structured request (`{method, args}`) and leaves as one JSON-ready reply.
// Scope checks, record and note operations and the operation log all live here; the app only
// carries requests from the page's sandbox to `handle` and back (ADR 0003).
import { mkdir, readFile, realpath, stat } from "node:fs/promises";
import { join, sep } from "node:path";
import { collator, LibraryError, openLibrary, type Library } from "./library";
import { operationLog, OperationLogError, writeWhole, type LogEntry, type LogKind, type NewLogEntry } from "./operationLog";
import type { VetRelocation } from "./organize";
import { addressableTables, appendRecords, cellNumber, fieldTypes, findTable, normalizedCell, RecordError, rewriteRows, unknownField, type FieldType } from "./recordTables";
import { serialized } from "./serialized";
import { notesInScope, scopeContains, scopeMeta, spaceLibrary, spaceScopeOf, type SpaceScope } from "./spaces";
import { isHidden, noteTitle } from "../shared/paths";


export type SpaceRequestErrorCode = "outside-scope" | "invalid" | "not-found" | "exists" | "unknown-field" | "scope-change" | "conflict" | "failed";

/** A refusal or failure, reported back to the page as `{code, message}`. */
export class SpaceRequestError extends Error {
  constructor(
    readonly code: SpaceRequestErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "SpaceRequestError";
  }
}

export const outsideScope = (path: string) => new SpaceRequestError("outside-scope", `“${path}”不在这个空间的范围内，或者是不允许访问的路径。`);
const invalid = (message: string) => new SpaceRequestError("invalid", message);
const notFound = (path: string) => new SpaceRequestError("not-found", `找不到“${path}”。`);

/**
 * What the page gets back. `changes` counts the operation-log entries the request wrote (for the
 * write notice); `recordChanges` how many of them were records.
 */
export type SpaceReply =
  | { ok: true; result: unknown; changes: number; recordChanges: number }
  | { ok: false; error: { code: SpaceRequestErrorCode; message: string } };

export interface SpaceRequestOptions {
  /** The clock placeholders and the operation log read; tests pass a fixed one. */
  now?(): Date;
  /** Moves a file, by real location, to the system trash. The app passes Electron's `shell.trashItem`. */
  trash?(path: string): Promise<void>;
  /** Told, once a request wrote, every library path it wrote, created, renamed or removed (an assistant turn leaves them out). */
  wrote?(paths: string[]): void | Promise<void>;
}

const pad = (n: number) => String(n).padStart(2, "0");

/** `{今天}` `{年}` `{月}` `{周}` in record table paths and written values, in local time. */
export function expandPlaceholders(text: string, now: Date): string {
  if (!text.includes("{")) return text;
  const year = now.getFullYear();
  const month = `${year}-${pad(now.getMonth() + 1)}`;
  // ISO 8601 week: a week belongs to the year its Thursday falls in.
  const thursday = new Date(Date.UTC(year, now.getMonth(), now.getDate() + 4 - (now.getDay() || 7)));
  const week = Math.ceil(((thursday.getTime() - Date.UTC(thursday.getUTCFullYear(), 0, 1)) / 86_400_000 + 1) / 7);
  return text
    .replaceAll("{今天}", `${month}-${pad(now.getDate())}`)
    .replaceAll("{年}", String(year))
    .replaceAll("{月}", month)
    .replaceAll("{周}", `${thursday.getUTCFullYear()}-W${pad(week)}`);
}

const utf8 = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

/** A cell as the page sees it: a number for number fields, null when empty, otherwise its text. */
function cellValue(cell: string, type: FieldType): number | string | null {
  const t = cell.trim();
  if (t === "") return null;
  return type === "number" ? (cellNumber(t) ?? t) : t;
}

/** Any value the page sends, as the text a cell stores. */
export function cellText(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "number") return String(value);
  if (typeof value === "string") return value;
  if (typeof value === "boolean") return value ? "true" : "false";
  return JSON.stringify(value);
}

function matches(cell: unknown, wanted: unknown): boolean {
  if (typeof cell === "number" && typeof wanted === "number") return cell === wanted;
  return cellText(cell) === cellText(wanted);
}

function compare(a: unknown, b: unknown): number {
  if (typeof a === "number" && typeof b === "number") return a - b;
  const aEmpty = a === null || a === undefined;
  const bEmpty = b === null || b === undefined;
  if (aEmpty || bEmpty) return aEmpty && bEmpty ? 0 : aEmpty ? -1 : 1;
  return collator.compare(cellText(a), cellText(b));
}

const isObject = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);

/** The code a failure reaches the page with; the library's own codes in the page interface's terms. */
function replyCode(error: unknown): SpaceRequestErrorCode {
  if (error instanceof SpaceRequestError || error instanceof RecordError || error instanceof OperationLogError) return error.code;
  if (error instanceof LibraryError) {
    const codes: Partial<Record<LibraryError["code"], SpaceRequestErrorCode>> = {
      "invalid-name": "invalid",
      "not-allowed": "invalid",
      "not-utf8": "invalid",
      exists: "exists",
      "not-found": "not-found",
      conflict: "conflict",
      "outside-library": "outside-scope",
    };
    return codes[error.code] ?? "failed";
  }
  return "failed";
}

export interface SpaceRequests {
  handle(request: unknown): Promise<SpaceReply>;
}

/** The request handler for the homepage of the space `space` in the library at `root`. */
export function spaceRequests(root: string, space: string, options: SpaceRequestOptions = {}): SpaceRequests {
  const now = () => options.now?.() ?? new Date();
  const spaces = spaceLibrary(root, options);
  const log = operationLog(root, options);
  let realRoot: string | undefined;
  const rootReal = async () => (realRoot ??= await realpath(root));

  /** Read from the space file on every request, so it always matches what the user set. */
  const scope = async (): Promise<SpaceScope> => (await spaces.space(space).catch(() => Promise.reject(notFound(space)))).scope;

  /**
   * A library-relative path inside the scope, with `..`, hidden segments (the app's `.notes/`
   * among them), absolute paths and link escapes refused.
   */
  const resolve = async (raw: string, { note = true } = {}): Promise<{ path: string; real: string }> => {
    const trimmed = raw.trim();
    const parts = trimmed.split("/");
    if (trimmed === "" || parts.some((part) => part === "" || part.startsWith(".") || part.includes("\\") || part.includes(":"))) throw outsideScope(raw);
    const path = parts.join("/");
    const within = await scope();
    if (!scopeContains(within, path)) throw outsideScope(raw);
    if (note && !path.toLowerCase().endsWith(".md")) throw invalid(`“${raw}”不是笔记（.md）。`);
    // Links are followed through the deepest part that exists; where they lead must be in scope too.
    const base = await rootReal();
    let existing = parts.length;
    let real: string | null = null;
    while (existing > 0 && real === null) {
      real = await realpath(join(base, ...parts.slice(0, existing))).catch(() => null);
      if (real === null) existing--;
    }
    const full = join(real ?? base, ...parts.slice(existing));
    if (!full.startsWith(base + sep)) throw outsideScope(raw);
    const realPath = full.slice(base.length + 1).split(sep).join("/");
    if (isHidden(realPath) || !scopeContains(within, realPath)) throw outsideScope(raw);
    return { path, real: join(base, ...parts) };
  };

  const textAt = async (real: string): Promise<string | null> => {
    let bytes: Buffer;
    try {
      bytes = await readFile(real);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw error;
    }
    try {
      return utf8.decode(bytes);
    } catch {
      throw invalid("笔记不是 UTF-8 文本。");
    }
  };

  /** `路径#标题` with placeholders expanded; `.md` is implied. */
  const source = async (raw: string) => {
    const expanded = expandPlaceholders(raw, now());
    const hash = expanded.indexOf("#");
    let path = (hash < 0 ? expanded : expanded.slice(0, hash)).trim();
    if (!path.toLowerCase().endsWith(".md")) path += ".md";
    const heading = hash < 0 ? null : expanded.slice(hash + 1).trim() || null;
    return { ...(await resolve(path)), heading };
  };

  const stringArg = (args: unknown[], i: number, name: string) => {
    const value = args[i];
    if (typeof value !== "string" || value === "") throw invalid(`缺少参数 ${name}。`);
    return value;
  };
  const objectArg = (args: unknown[], i: number) => (isObject(args[i]) ? args[i] : {});

  // --- reads ---------------------------------------------------------------------------------

  const notes = async (folder: unknown) => {
    const only = typeof folder === "string" && folder.replace(/^[/ ]+|[/ ]+$/g, "") !== "" ? (await resolve(folder.replace(/^[/ ]+|[/ ]+$/g, ""), { note: false })).path : null;
    const base = await rootReal();
    const paths = (await notesInScope(base, await scope())).filter((path) => only === null || path.startsWith(`${only}/`));
    return Promise.all(
      paths.map(async (path) => ({
        path,
        title: noteTitle(path),
        modified: new Date((await stat(join(base, ...path.split("/")))).mtimeMs).toISOString(),
      })),
    );
  };

  const read = async (raw: string) => {
    const { real } = await resolve(raw);
    const text = await textAt(real);
    if (text === null) throw notFound(raw);
    return text;
  };

  /** space.open: only a note in scope that is there; the app opens it. */
  const open = async (raw: string) => {
    const { path, real } = await resolve(raw);
    if ((await textAt(real)) === null) throw notFound(raw);
    return { path };
  };

  // One note's tables are read from that note alone; the whole scope only when no note is named.
  const tables = async (raw: unknown) => {
    const found =
      typeof raw === "string" && raw !== ""
        ? await (async () => {
            const { path, real } = await resolve(raw);
            const text = await textAt(real);
            return text === null ? [] : addressableTables(path, text);
          })()
        : await spaces.recordTables(await scope());
    return found.map(({ source, header }) => ({ source, header }));
  };

  const query = async (raw: string, options: Record<string, unknown>) => {
    const { real, heading } = await source(raw);
    const text = await textAt(real);
    const table = text === null ? undefined : findTable(text, heading);
    if (!table) return { records: [], fields: [] };
    const types = fieldTypes(table);
    let records = table.rows.map((row, index) => {
      const record: Record<string, unknown> = { _row: index };
      table.header.forEach((name, c) => {
        if (name !== "") record[name] = cellValue(row[c] ?? "", types[c]!);
      });
      return record;
    });
    const filter = options.filter;
    if (isObject(filter)) records = records.filter((record) => Object.entries(filter).every(([key, wanted]) => matches(record[key], wanted)));
    if (typeof options.sort === "string" && options.sort !== "") {
      const descending = options.sort.startsWith("-");
      const field = descending ? options.sort.slice(1) : options.sort;
      // Stable: records that compare equal keep the table's order.
      records = records
        .map((record, i) => ({ record, i }))
        .sort((a, b) => (descending ? -1 : 1) * compare(a.record[field], b.record[field]) || a.i - b.i)
        .map(({ record }) => record);
    }
    if (typeof options.limit === "number" && options.limit >= 0) records = records.slice(0, options.limit);
    return { records, fields: table.header.map((name, c) => ({ name, type: types[c] })) };
  };

  // --- writes --------------------------------------------------------------------------------

  /** Entries this request logged, for the write notice. */
  interface Tally {
    changes: number;
    records: number;
  }

  const entry = (kind: LogKind, path: string, rest: Partial<NewLogEntry> = {}): NewLogEntry => ({ space, kind, path, ...rest });

  /** Logs first and writes second, so nothing reaches the disk that the operation log can't undo. */
  const commit = async (text: string, real: string, entries: NewLogEntry[], tally: Tally) => {
    const logged = await log.record(entries);
    try {
      await writeWhole(real, text);
    } catch (error) {
      await log.discard(logged.map((e) => e.id)).catch(() => undefined);
      throw error;
    }
    await counted(entries, tally);
  };

  const counted = async (entries: NewLogEntry[], tally: Tally) => {
    tally.changes += entries.length;
    tally.records += entries.filter((e) => e.kind.startsWith("record")).length;
    const paths = entries.flatMap((e) => [e.path, ...(e.newPath ? [e.newPath] : []), ...(e.related ?? []).map((r) => r.path)]);
    if (paths.length > 0) await options.wrote?.([...new Set(paths)]);
  };

  /** A record's values as cell text; strings may use placeholders. */
  const cellsFrom = (record: Record<string, unknown>) =>
    Object.fromEntries(
      Object.entries(record)
        .filter(([key]) => key !== "_row")
        .map(([key, value]) => [key, typeof value === "string" ? expandPlaceholders(value, now()) : cellText(value)]),
    );

  const append = async (target: string, value: unknown, options: Record<string, unknown>, tally: Tally) => {
    const { path, real, heading } = await source(target);
    const records = isObject(value) ? [value] : Array.isArray(value) && value.every(isObject) ? value : null;
    if (!records) throw invalid("space.append 需要一条记录（对象）或记录数组。");
    if (records.length === 0) return { count: 0 };
    // The page sends the fields in the order it wrote them; that order heads a new table.
    let header = Array.isArray(options.header) ? options.header.map(cellText).filter((field) => field !== "") : [];
    if (header.length === 0) header = [...new Set(records.flatMap((record) => Object.keys(record).filter((key) => key !== "_row")))];
    const title = noteTitle(path);
    const written = appendRecords(await textAt(real), title, heading, header, records.map(cellsFrom));
    const entries = written.rows.map((row) => entry("recordAppend", path, { heading, header: written.header, after: row }));
    await commit(written.text, real, entries, tally);
    return { count: entries.length };
  };

  /** `changes` null removes the matching records. */
  const update = async (target: string, match: Record<string, unknown>, changes: Record<string, unknown> | null, tally: Tally) => {
    const { path, real, heading } = await source(target);
    if (Object.keys(match).length === 0) throw invalid('需要用 match 指定要修改的记录，例如 { 日期: "2026-10-18" } 或 { _row: 0 }。');
    const text = await textAt(real);
    const table = text === null ? undefined : findTable(text, heading);
    if (text === null || !table) throw notFound(target);
    const types = fieldTypes(table);
    const updates = changes && cellsFrom(changes);
    const unknown = [...Object.keys(updates ?? {}), ...Object.keys(match).filter((key) => key !== "_row")].sort().find((key) => !table.header.includes(key));
    if (unknown !== undefined) throw unknownField(unknown);
    const indices = table.rows.flatMap((row, i) => {
      if (typeof match._row === "number" && match._row !== i) return [];
      const fits = Object.entries(match).every(([key, wanted]) => {
        if (key === "_row") return true;
        const c = table.header.indexOf(key);
        return matches(cellValue(row[c] ?? "", types[c]!), wanted);
      });
      return fits ? [i] : [];
    });
    if (indices.length === 0) return { count: 0 };
    const entries: NewLogEntry[] = [];
    const rewritten = rewriteRows(text, table, indices, (index, before) => {
      const logged = entry(updates ? "recordUpdate" : "recordRemove", path, { heading, header: table.header, before, row: index });
      if (!updates) {
        entries.push(logged);
        return null;
      }
      const after = before.map((cell, c) => (table.header[c]! in updates ? normalizedCell(updates[table.header[c]!]!) : cell));
      entries.push({ ...logged, after });
      return after;
    });
    // Rows were visited last first; the log keeps them in table order, and only real changes.
    await commit(rewritten, real, entries.reverse().filter((e) => e.after?.join("\u0000") !== e.before?.join("\u0000")), tally);
    return { count: indices.length };
  };

  const writeNote = async (raw: string, content: string, create: boolean, tally: Tally) => {
    const { path, real } = await resolve(raw);
    const before = await textAt(real);
    if (create && before !== null) throw new SpaceRequestError("exists", `“${raw}”已经存在。`);
    await commit(content, real, [entry(before === null ? "noteCreate" : "noteWrite", path, { ...(before === null ? {} : { before: [before] }), after: [content] })], tally);
    return { path };
  };

  let opened: Promise<Library> | undefined;
  const notesLibrary = () => (opened ??= openLibrary(root, options));

  /** Renames or moves a note; links to it follow, but never inside a note outside the scope. */
  const relocate = async (raw: string, kind: "noteRename" | "noteMove", destination: string, tally: Tally) => {
    const { path } = await resolve(raw);
    const target = await resolve(destination);
    if ((await textAt((await resolve(raw)).real)) === null) throw notFound(raw);
    if (target.path === path) return { path };
    const within = await scope();
    let logged: LogEntry[] = [];
    const vet: VetRelocation = async (to, rewrites) => {
      const outside = rewrites.find((rewrite) => rewrite.to !== to && !scopeContains(within, rewrite.to));
      if (outside) {
        throw new SpaceRequestError("outside-scope", `范围外的笔记“${outside.from}”链接到“${path}”。为了不改动范围外的笔记，不能改名或移动它。`);
      }
      logged = await log.record([entry(kind, path, { newPath: to, related: rewrites.map(({ to: at, before, after }) => ({ path: at, before, after })) })]);
    };
    const lib = await notesLibrary();
    const name = target.path.split("/").pop()!;
    const folder = target.path.split("/").slice(0, -1).join("/");
    try {
      if (kind === "noteMove") await mkdir(join(await rootReal(), ...folder.split("/").filter(Boolean)), { recursive: true });
      const moved = kind === "noteRename" ? await lib.rename(path, name, vet) : await lib.move(path, folder, vet);
      await counted(logged, tally);
      return { path: moved.path };
    } catch (error) {
      if (logged.length > 0) await log.discard(logged.map((e) => e.id)).catch(() => undefined);
      throw error;
    }
  };

  const rename = async (raw: string, title: string, tally: Tally) => {
    let name = title.trim();
    if (name.toLowerCase().endsWith(".md")) name = name.slice(0, -3);
    if (name === "" || name.startsWith(".") || /[\\/:\n\r]/.test(name)) throw invalid("新名称不能为空，不能包含斜杠、冒号或以点开头。");
    const { path } = await resolve(raw);
    const folder = path.split("/").slice(0, -1);
    return relocate(raw, "noteRename", [...folder, `${name}.md`].join("/"), tally);
  };

  const move = async (raw: string, folder: unknown, tally: Tally) => {
    const destination = (typeof folder === "string" ? folder : "").replace(/^[/ ]+|[/ ]+$/g, "");
    const { path } = await resolve(raw);
    return relocate(raw, "noteMove", [destination, path.split("/").pop()!].filter(Boolean).join("/"), tally);
  };

  const trash = async (raw: string, tally: Tally) => {
    const { path, real } = await resolve(raw);
    const before = await textAt(real);
    if (before === null) throw notFound(raw);
    // The note's text stays in the log, so undo can bring it back whatever the system trash does.
    const logged = await log.record([entry("noteTrash", path, { before: [before] })]);
    try {
      if (!options.trash) throw new Error("没有可用的废纸篓");
      await options.trash(real);
    } catch (error) {
      await log.discard(logged.map((e) => e.id)).catch(() => undefined);
      throw new SpaceRequestError("failed", `无法把“${raw}”移到废纸篓：${(error as Error).message}。`);
    }
    await counted(logged, tally);
    return { path };
  };

  /** The homepage may rewrite its own file, but its scope stays what the user set. */
  const writePage = async (html: string, tally: Tally) => {
    const current = await spaces.space(space).catch(() => Promise.reject(notFound(space)));
    if (scopeMeta(spaceScopeOf(html)) !== scopeMeta(current.scope) || spaceScopeOf(html).library !== current.scope.library) {
      throw new SpaceRequestError("scope-change", "空间主页不能修改自己的范围（space-scope）。请在笔记应用里编辑空间。");
    }
    await commit(html, join(spaces.folder, `${space}.html`), [entry("pageWrite", current.path, { before: [current.html], after: [html] })], tally);
    return { path: current.path };
  };

  const dispatch = async (method: string, args: unknown[], tally: Tally): Promise<unknown> => {
    switch (method) {
      case "scope":
        return scope();
      case "notes":
        return notes(args[0]);
      case "read":
        return read(stringArg(args, 0, "path"));
      case "tables":
        return tables(args[0]);
      case "query":
        return query(stringArg(args, 0, "source"), objectArg(args, 1));
      case "page":
        return (await spaces.space(space).catch(() => Promise.reject(notFound(space)))).html;
      case "append":
        return append(stringArg(args, 0, "target"), args[1], objectArg(args, 2), tally);
      case "update":
        return update(stringArg(args, 0, "target"), objectArg(args, 1), objectArg(args, 2), tally);
      case "remove":
        return update(stringArg(args, 0, "target"), objectArg(args, 1), null, tally);
      case "create":
      case "write":
        return writeNote(stringArg(args, 0, "path"), typeof args[1] === "string" ? args[1] : "", method === "create", tally);
      case "rename":
        return rename(stringArg(args, 0, "path"), stringArg(args, 1, "newTitle"), tally);
      case "move":
        return move(stringArg(args, 0, "path"), args[1], tally);
      case "trash":
        return trash(stringArg(args, 0, "path"), tally);
      case "open":
        return open(stringArg(args, 0, "path"));
      case "writePage":
        return writePage(typeof args[0] === "string" ? args[0] : "", tally);
      default:
        throw invalid(`没有方法 space.${method}。`);
    }
  };

  const handle = async (request: unknown): Promise<SpaceReply> => {
    if (!isObject(request) || typeof request.method !== "string") return { ok: false, error: { code: "invalid", message: "请求格式不正确。" } };
    const { method } = request;
    const args = Array.isArray(request.args) ? request.args : [];
    const tally: Tally = { changes: 0, records: 0 };
    try {
      const result = await serialized(root, () => dispatch(method, args, tally));
      return { ok: true, result, changes: tally.changes, recordChanges: tally.records };
    } catch (error) {
      return { ok: false, error: { code: replyCode(error), message: (error as Error).message } };
    }
  };

  return { handle };
}
