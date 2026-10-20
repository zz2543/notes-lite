import { access, mkdir, readdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { collator } from "./library";
import { addressableTables } from "./recordTables";
import { spaceGuide } from "./spaceGuide";

/** The app's own folder inside a note library (spaces, guide, order, operation log). */
export const notesFolder = ".notes";
/** Where the space files live, library-relative. */
export const spacesFolder = `${notesFolder}/空间`;
export const spaceGuideName = "编写说明.md";
const orderName = "顺序.json";

/**
 * The folders a space looks at, which is also everything its homepage may read and write:
 * the whole library, or some folders ("" is the library root).
 */
export type SpaceScope = { library: true } | { library: false; folders: string[] };

export interface Space {
  name: string;
  /** An emoji; "" when none was chosen. */
  icon: string;
  scope: SpaceScope;
  /** The whole space file, meta included. */
  html: string;
  /** Library-relative, `.notes/空间/<名称>.html`. */
  path: string;
  /** False while the file holds nothing but its meta, comments and whitespace. */
  hasPage: boolean;
}

export interface SpaceDraft {
  name: string;
  icon: string;
  scope: SpaceScope;
}

export type SpaceErrorCode = "invalid-name" | "exists" | "not-found" | "empty-scope" | "scope-name" | "write-failed";

export class SpaceError extends Error {
  constructor(
    readonly code: SpaceErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "SpaceError";
  }
}

// --- scope ---------------------------------------------------------------------------------

/** `*` for the whole library, otherwise folder paths separated by commas. */
export function scopeFromMeta(meta: string): SpaceScope {
  const parts = meta.split(",").map((part) => part.trim().replace(/^\/+|\/+$/g, ""));
  return parts.includes("*") ? { library: true } : { library: false, folders: parts.filter((part) => part !== "") };
}

export function scopeMeta(scope: SpaceScope): string {
  return scope.library ? "*" : scope.folders.join(", ");
}

/** Whether a library-relative path lies inside the scope. */
export function scopeContains(scope: SpaceScope, path: string): boolean {
  return scope.library || scope.folders.some((folder) => folder === "" || path === folder || path.startsWith(`${folder}/`));
}

/** The scope in words, for the prompt and the space form. */
export function scopeLabel(scope: SpaceScope): string {
  return scope.library ? "整个笔记库" : scope.folders.map((folder) => folder || "笔记库根目录").join("、");
}

/**
 * Of the paths the library watcher reported, those a homepage hears of through `space.on("change")`:
 * visible ones inside its scope. "" (something changed, the system can't say what) always passes.
 */
export function spaceChanges(scope: SpaceScope, paths: readonly string[]): string[] {
  return paths.filter((path) => path === "" || (!path.split("/").some((part) => part.startsWith(".")) && scopeContains(scope, path)));
}

/** What went wrong on a homepage: the message, where in the space file (if known), and the stack. */
export interface SpacePageProblem {
  message: string;
  location: string;
  stack: string;
}

/** 复制错误给 agent: the error with what an agent needs to fix it, the space file and the guide. */
export function spaceErrorReport({ space, file, guide, error }: { space: string; file: string; guide: string; error: SpacePageProblem }): string {
  const lines = [`空间“${space}”的主页出错了。`, "", `空间文件：${file}`, `错误：${error.message}`];
  if (error.location) lines.push(`位置：${error.location}`);
  if (error.stack) lines.push("堆栈：", error.stack);
  lines.push("", `请先阅读编写说明（${guide}），再修复空间文件里的问题。`);
  return lines.join("\n");
}

// --- the space file's meta -----------------------------------------------------------------

const metaRe = /<meta\b[^>]*>/gi;
const attributeRe = /([A-Za-z-]+)\s*=\s*"([^"]*)"/g;

const escapeAttribute = (s: string) => s.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;");
const unescapeAttribute = (s: string) =>
  s.replaceAll("&quot;", '"').replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&amp;", "&");

function metaAttributes(tag: string): Record<string, string> {
  const attributes: Record<string, string> = {};
  for (const [, key, value] of tag.matchAll(attributeRe)) attributes[key!.toLowerCase()] = unescapeAttribute(value!);
  return attributes;
}

/**
 * The meta a space file declares itself with, current name first: `space-*` since ticket 20, and the
 * old app's `lb-*`, which stays readable for good so its homepages run unchanged.
 */
export const spaceMeta = {
  scope: ["space-scope", "lb-scope"],
  icon: ["space-icon", "lb-icon"],
} as const;

type MetaNames = (typeof spaceMeta)[keyof typeof spaceMeta];

function readMeta(html: string, names: MetaNames): string | undefined {
  const found = new Map<string, string | undefined>();
  for (const [tag] of html.matchAll(metaRe)) {
    const { name, content } = metaAttributes(tag);
    if (name !== undefined && !found.has(name)) found.set(name, content);
  }
  for (const name of names) if (found.has(name)) return found.get(name);
  return undefined;
}

/**
 * Replaces one meta (or inserts it under its current name at the top), leaving the page untouched. A
 * file using the old name keeps it, so it never ends up declaring a second, different scope.
 */
function settingMeta(html: string, names: MetaNames, value: string): string {
  const matches = [...html.matchAll(metaRe)];
  for (const name of names) {
    const match = matches.find((m) => metaAttributes(m[0]).name === name);
    if (match) return html.slice(0, match.index) + `<meta name="${name}" content="${escapeAttribute(value)}">` + html.slice(match.index + match[0].length);
  }
  return `<meta name="${names[0]}" content="${escapeAttribute(value)}">\n${html}`;
}

function pageBody(html: string): string {
  return html.replace(metaRe, "").replace(/<!--[\s\S]*?-->/g, "").trim();
}

function parseSpace(name: string, html: string): Space {
  return {
    name,
    icon: readMeta(html, spaceMeta.icon) ?? "",
    scope: scopeFromMeta(readMeta(html, spaceMeta.scope) ?? ""),
    html,
    path: `${spacesFolder}/${name}.html`,
    hasPage: pageBody(html) !== "",
  };
}

/** The visible notes inside the scope, by library path; hidden folders such as `.notes/` are never entered. */
export async function notesInScope(root: string, scope: SpaceScope): Promise<string[]> {
  const found: string[] = [];
  const walk = async (relative: string) => {
    const entries = await readdir(join(root, ...relative.split("/").filter(Boolean)), { withFileTypes: true }).catch(() => []);
    for (const entry of entries) {
      if (entry.name.startsWith(".")) continue;
      const path = relative ? `${relative}/${entry.name}` : entry.name;
      if (entry.isDirectory()) await walk(path);
      else if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) found.push(path);
    }
  };
  const starts = scope.library ? [""] : scope.folders.filter((f) => !f.split("/").some((part) => part.startsWith(".") || part === ".."));
  // A folder inside another one in the scope is walked once.
  for (const start of starts.filter((f) => !starts.some((other) => other !== f && (other === "" || f.startsWith(`${other}/`))))) {
    await walk(start);
  }
  return [...new Set(found)].sort((a, b) => collator.compare(a, b));
}

/** The scope a space file's `space-scope` (or old `lb-scope`) meta declares; none declared is an empty scope. */
export function spaceScopeOf(html: string): SpaceScope {
  return scopeFromMeta(readMeta(html, spaceMeta.scope) ?? "");
}

// A library syncs between macOS and Windows, so a space's file name must work on both.
const forbidden = /[\\/:*?"<>|\u0000-\u001f]/;
const reserved = /^(?:con|prn|aux|nul|com\d|lpt\d)(?:\..*)?$/i;

function checkDraft({ name, scope }: SpaceDraft) {
  if (!name.trim() || name.startsWith(".") || forbidden.test(name) || /[. ]$/.test(name) || reserved.test(name)) {
    throw new SpaceError("invalid-name", "空间名称不能为空，不能以“.”开头或以空格、“.”结尾，也不能包含 \\ / : * ? \" < > | 这些字符。");
  }
  if (scope.library) return;
  if (scope.folders.length === 0) throw new SpaceError("empty-scope", "请至少选择一个文件夹，或选择整个笔记库。");
  const bad = scope.folders.find((folder) => folder.includes(","));
  if (bad !== undefined) throw new SpaceError("scope-name", `文件夹“${bad}”的名称含有逗号，不能加入范围。`);
}

const exists = (path: string) => access(path).then(
  () => true,
  () => false,
);

const taken = (name: string) => new SpaceError("exists", `已经有名为“${name}”的空间。`);

// --- paths that follow a rename or move ---------------------------------------------------

// A quoted string that may be a path: no quotes, line breaks or tags inside.
const quotedRe = /(["'`])([^"'`\n<>]+)\1/g;

/** The space file with its scope and quoted paths following a note or folder from `from` to `to`. */
function movedPaths(space: Space, from: string, to: string): string {
  const note = /\.md$/i.test(from);
  // Record table sources may leave out `.md`; those follow the note too.
  const fromStem = note ? from.slice(0, -3) : from;
  const toStem = note && /\.md$/i.test(to) ? to.slice(0, -3) : to;
  const moved = (path: string): string | undefined => {
    if (path === from) return to;
    if (note && path === fromStem) return toStem;
    if (path.startsWith(`${from}/`)) return to + path.slice(from.length);
    return undefined;
  };
  let html = space.html;
  if (!space.scope.library) {
    const before = space.scope.folders;
    const folders = before.map((folder) => moved(folder) ?? folder);
    if (folders.some((folder, i) => folder !== before[i])) {
      html = settingMeta(html, spaceMeta.scope, scopeMeta({ library: false, folders }));
    }
  }
  return html.replace(quotedRe, (whole, quote: string, inner: string) => {
    const hash = inner.indexOf("#");
    const path = hash < 0 ? inner : inner.slice(0, hash);
    // A bare folder name is too common a string to rewrite; only paths inside it move.
    const target = note || path !== from ? moved(path) : undefined;
    return target === undefined ? whole : quote + target + (hash < 0 ? "" : inner.slice(hash)) + quote;
  });
}

// --- the library of spaces -----------------------------------------------------------------

export interface SpaceLibrary {
  /** Absolute location of `.notes/空间`. */
  readonly folder: string;
  /** Absolute location of the authoring guide. */
  readonly guidePath: string;
  /** Spaces in the user's order; spaces missing from the order follow by name. */
  spaces(): Promise<Space[]>;
  space(name: string): Promise<Space>;
  /** Writes an empty page carrying the scope and icon, adds it last and installs the guide. */
  create(draft: SpaceDraft): Promise<Space>;
  /** Writes the authoring guide when it is missing or differs from this version's. */
  installGuide(): Promise<void>;
  /** Renames, re-icons and re-scopes a space, keeping its page and its place in the order. */
  update(name: string, draft: SpaceDraft): Promise<Space>;
  /** Moves only the space file to the trash; no note is touched. */
  delete(name: string): Promise<void>;
  /** Saves the order of the spaces, by name, in the library. */
  reorder(names: string[]): Promise<void>;
  /** Record tables inside the scope, as `路径#标题` with their header. */
  recordTables(scope: SpaceScope): Promise<{ source: string; header: string[] }[]>;
  /** What the user pastes to an external agent so it can write the homepage; installs the guide. */
  prompt(space: Space): Promise<string>;
  /**
   * A note or folder moved from `from` to `to` (library paths): every space's scope and the quoted
   * paths in its page (component `source`/`target`, script literals) follow it.
   */
  syncPaths(from: string, to: string): Promise<void>;
}

export interface SpaceLibraryOptions {
  /** Moves a file, by real location, to the system trash. The app passes Electron's `shell.trashItem`. */
  trash?(path: string): Promise<void>;
}

export function spaceLibrary(root: string, options: SpaceLibraryOptions = {}): SpaceLibrary {
  const folder = join(root, ...spacesFolder.split("/"));
  const guidePath = join(folder, spaceGuideName);
  const fileOf = (name: string) => join(folder, `${name}.html`);

  // Replaced whole: a crash mid-write leaves the old file, never half of one.
  const writeAtomic = async (path: string, text: string) => {
    const temp = `${path}.${process.pid}.saving`;
    await writeFile(temp, text, "utf8");
    await rename(temp, path);
  };

  const order = async (): Promise<string[]> => {
    try {
      const names: unknown = JSON.parse(await readFile(join(folder, orderName), "utf8"));
      return Array.isArray(names) ? names.filter((n): n is string => typeof n === "string") : [];
    } catch {
      return [];
    }
  };
  const saveOrder = async (names: string[]) => {
    await mkdir(folder, { recursive: true });
    await writeAtomic(join(folder, orderName), `${JSON.stringify(names, null, 2)}\n`);
  };

  const spaces = async (): Promise<Space[]> => {
    const entries = await readdir(folder, { withFileTypes: true }).catch(() => []);
    const found: Space[] = [];
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.toLowerCase().endsWith(".html") || entry.name.startsWith(".")) continue;
      const html = await readFile(join(folder, entry.name), "utf8").catch(() => null);
      if (html !== null) found.push(parseSpace(entry.name.slice(0, -5), html));
    }
    const ranks = new Map((await order()).map((name, i) => [name, i]));
    const rank = (space: Space) => ranks.get(space.name) ?? Infinity;
    return found.sort((a, b) => rank(a) - rank(b) || collator.compare(a.name, b.name));
  };

  const space = async (name: string): Promise<Space> => {
    const html = await readFile(fileOf(name), "utf8").catch(() => {
      throw new SpaceError("not-found", `找不到空间“${name}”。`);
    });
    return parseSpace(name, html);
  };

  const installGuide = async () => {
    await mkdir(folder, { recursive: true });
    if ((await readFile(guidePath, "utf8").catch(() => null)) === spaceGuide) return;
    await writeAtomic(guidePath, spaceGuide);
  };

  const create = async (draft: SpaceDraft): Promise<Space> => {
    checkDraft(draft);
    const { name, icon, scope } = draft;
    await mkdir(folder, { recursive: true });
    const html = `<meta name="${spaceMeta.scope[0]}" content="${escapeAttribute(scopeMeta(scope))}">\n<meta name="${spaceMeta.icon[0]}" content="${escapeAttribute(icon)}">\n`;
    // Created, never replaced: a space by that name keeps its page.
    await writeFile(fileOf(name), html, { encoding: "utf8", flag: "wx" }).catch((error: NodeJS.ErrnoException) => {
      throw error.code === "EEXIST" ? taken(name) : error;
    });
    await saveOrder([...(await order()).filter((n) => n !== name), name]);
    await installGuide();
    return parseSpace(name, html);
  };

  const update = async (name: string, draft: SpaceDraft): Promise<Space> => {
    checkDraft(draft);
    const current = await space(name);
    const html = settingMeta(settingMeta(current.html, spaceMeta.icon, draft.icon), spaceMeta.scope, scopeMeta(draft.scope));
    const renamed = draft.name !== name;
    // A change of case only is the same file on a case-insensitive disk, not a clash.
    if (renamed && draft.name.toLowerCase() !== name.toLowerCase() && (await exists(fileOf(draft.name)))) throw taken(draft.name);
    await writeAtomic(fileOf(name), html);
    if (renamed) {
      await rename(fileOf(name), fileOf(draft.name));
      await saveOrder((await order()).map((n) => (n === name ? draft.name : n)));
    }
    return parseSpace(draft.name, html);
  };

  /** Moves only the space file to the trash; no note is touched. */
  const delete_ = async (name: string) => {
    if (!(await exists(fileOf(name)))) throw new SpaceError("not-found", `找不到空间“${name}”。`);
    try {
      if (!options.trash) throw new Error("没有可用的废纸篓");
      await options.trash(fileOf(name));
    } catch (error) {
      throw new SpaceError("write-failed", `无法把空间“${name}”移到废纸篓：${(error as Error).message}。`);
    }
    await saveOrder((await order()).filter((n) => n !== name));
  };

  const reorder = (names: string[]) => saveOrder(names);

  const tablesIn = async (scope: SpaceScope) => {
    const tables: { source: string; header: string[] }[] = [];
    for (const path of await notesInScope(root, scope)) {
      const text = await readFile(join(root, ...path.split("/")), "utf8").catch(() => "");
      tables.push(...addressableTables(path, text));
    }
    return tables;
  };

  const prompt = async (space: Space) => {
    await installGuide();
    const tables = await tablesIn(space.scope);
    return [
      `请为笔记应用编写“${space.name}”空间的空间主页。`,
      "",
      `- 编写说明：${guidePath}（请先完整阅读并遵守）`,
      `- 空间文件：${fileOf(space.name)}（保留开头的 meta，在其后写主页；不要修改 space-scope）`,
      `- 空间名称：${space.name}`,
      `- 范围：${scopeLabel(space.scope)}`,
      "- 范围内现有记录表：",
      ...(tables.length === 0
        ? ["  - 暂无。可以用 space-quick-add 或 space.append 指定目标笔记和表头，笔记应用会自动新建记录表。"]
        : tables.map((table) => `  - ${table.source}：${table.header.join(" | ")}`)),
      "",
      "请围绕我每天的进展设计这个主页：用美观的图表展示进展，并提供快捷录入。数据只能存进范围内的记录表。",
    ].join("\n");
  };

  const syncPaths = async (from: string, to: string) => {
    if (!from || from === to) return;
    for (const space of await spaces()) {
      const html = movedPaths(space, from, to);
      if (html !== space.html) await writeAtomic(fileOf(space.name), html);
    }
  };

  return { folder, guidePath, spaces, space, create, update, delete: delete_, reorder, installGuide, recordTables: tablesIn, prompt, syncPaths };
}
