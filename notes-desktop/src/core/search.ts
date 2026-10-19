import { lstat, readdir, readFile, stat } from "node:fs/promises";
import { join } from "node:path";
import { blockPrefixLength } from "./markdown";

export interface Snippet {
  text: string;
  /** Where the query matched within `text`, in UTF-16 offsets. */
  match?: { start: number; end: number };
}

export interface SearchHit {
  /** Library-relative, "/"-separated. */
  path: string;
  title: string;
  /** The folder holding the note; "" for the library root. */
  folder: string;
  snippet: Snippet;
}

export interface SearchResults {
  /** Most recently modified first, at most `limit` of them. */
  hits: SearchHit[];
  /** How many notes matched in all. */
  total: number;
}

export interface SearchOptions {
  /** Only this folder and its subfolders; the whole library when omitted or "". */
  folder?: string;
  /** At most this many hits. */
  limit?: number;
}

export interface SearchIndex {
  search(query: string, options?: SearchOptions): Promise<SearchResults>;
  /**
   * Reads again whatever is at `path` now — a note, a folder of notes, or nothing any more — after
   * the app saved it or something else changed it.
   */
  update(path: string): Promise<void>;
}

interface Entry {
  path: string;
  title: string;
  folder: string;
  /** Milliseconds since the epoch. */
  modified: number;
  body: string;
}

const utf8 = new TextDecoder("utf-8", { fatal: true });

/** A note's text as searched; one that isn't UTF-8 (and so won't open) is still found by title. */
function decode(bytes: Uint8Array): string {
  try {
    return utf8.decode(bytes).normalize("NFC");
  } catch {
    return "";
  }
}

/** A library path as the index keys it: "/"-separated, whichever separator it came with. */
const relativePath = (path: string) => path.split(/[\\/]/).filter((part) => part !== "" && part !== ".").join("/");

const isNote = (name: string) => name.toLowerCase().endsWith(".md");

async function readEntry(root: string, path: string): Promise<Entry> {
  const file = join(root, path);
  const [{ mtimeMs }, bytes] = await Promise.all([stat(file), readFile(file)]);
  const slash = path.lastIndexOf("/");
  const title = path.slice(slash + 1, -3).normalize("NFC");
  return { path, title, folder: path.slice(0, Math.max(slash, 0)), modified: mtimeMs, body: decode(bytes) };
}

/**
 * Every visible note under `folder`. Links are not followed, as in 当前目录内容; what can't be read
 * is left out rather than stopping the rest.
 */
async function scan(root: string, folder: string, into: Map<string, Entry>) {
  const entries = await readdir(join(root, folder), { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    if (entry.name.startsWith(".")) continue;
    const path = folder ? `${folder}/${entry.name}` : entry.name;
    if (entry.isDirectory()) await scan(root, path, into);
    else if (entry.isFile() && isNote(entry.name)) {
      const note = await readEntry(root, path).catch(() => null);
      if (note) into.set(path, note);
    }
  }
}

/** How the note begins: its first line with text, without the block marker. */
function opening(body: string): Snippet {
  const line = body.split("\n").find((l) => l.trim() !== "") ?? "";
  return { text: line.slice(blockPrefixLength(line)).trim() };
}

// A list row shows one line of snippet (about 18 CJK characters): a match within the first
// `inView` characters shows the line from its start; one further along keeps `contextBefore`.
const inView = 16;
const contextBefore = 10;
const contextAfter = 80;

/** Moves `at` off the second half of a surrogate pair, so a cut never splits a character. */
const charBoundary = (text: string, at: number) => (/[\udc00-\udfff]/.test(text[at] ?? "") ? at - 1 : at);

/** The line holding the match, without its block marker or line ending, cut to keep the match in view. */
function snippetAt(body: string, at: number, length: number): Snippet {
  const lineStart = body.lastIndexOf("\n", at - 1) + 1;
  const lineEnd = body.indexOf("\n", at + length);
  const line = body.slice(lineStart, lineEnd === -1 ? undefined : lineEnd).replace(/\r$/, "");
  const prefix = blockPrefixLength(line);
  const matchStart = at - lineStart;
  const cut = matchStart - prefix > inView;
  const textStart = cut ? charBoundary(line, matchStart - contextBefore) : prefix;
  const textEnd = Math.min(line.length, charBoundary(line, matchStart + length + contextAfter));
  const lead = cut ? "…" : "";
  const text = lead + line.slice(textStart, textEnd) + (textEnd < line.length ? "…" : "");
  const start = matchStart - textStart + lead.length;
  return { text, match: { start, end: start + length } };
}

/**
 * Matches like the old app's localizedCaseInsensitiveContains: any case, and composed or decomposed
 * accents alike (text is kept in NFC). CJK needs no word splitting: the query is one substring.
 */
function matcher(query: string): RegExp {
  return new RegExp(query.normalize("NFC").replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "iu");
}

export function createSearchIndex(root: string): SearchIndex {
  const entries = new Map<string, Entry>();
  // The first pass, then each update in turn; a search sees all of them that came before it.
  let settled: Promise<void> = scan(root, "", entries);

  // Whatever is at `path` now replaces what the index held there: a note, a folder's notes, or nothing.
  const reread = async (path: string) => {
    if (path.split("/").some((part) => part.startsWith("."))) return;
    for (const key of entries.keys()) if (path === "" || key === path || key.startsWith(`${path}/`)) entries.delete(key);
    const found = await lstat(join(root, path)).catch(() => null);
    if (found?.isDirectory()) await scan(root, path, entries);
    else if (found?.isFile() && isNote(path)) entries.set(path, await readEntry(root, path));
  };
  const update = (path: string) => {
    settled = settled.then(() => reread(relativePath(path))).catch(() => {});
    return settled;
  };

  const search = async (query: string, options: SearchOptions = {}): Promise<SearchResults> => {
    await settled;
    const pattern = matcher(query);
    const scope = relativePath(options.folder ?? "");
    const inScope = (entry: Entry) => scope === "" || entry.folder === scope || entry.folder.startsWith(`${scope}/`);
    const matches: { entry: Entry; found: RegExpExecArray | null }[] = [];
    for (const entry of entries.values()) {
      if (!inScope(entry)) continue;
      const found = pattern.exec(entry.body);
      if (found || pattern.test(entry.title)) matches.push({ entry, found });
    }
    matches.sort((a, b) => b.entry.modified - a.entry.modified);
    const hits = matches.slice(0, options.limit).map(({ entry, found }): SearchHit => {
      const snippet = found ? snippetAt(entry.body, found.index, found[0].length) : opening(entry.body);
      return { path: entry.path, title: entry.title, folder: entry.folder, snippet };
    });
    return { hits, total: matches.length };
  };
  return { search, update };
}
