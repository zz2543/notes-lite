import { readFile, readdir, realpath, stat } from "node:fs/promises";
import { isAbsolute, join, sep } from "node:path";

export type LibraryErrorCode = "not-a-folder" | "outside-library";

export class LibraryError extends Error {
  constructor(
    readonly code: LibraryErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "LibraryError";
  }
}

export interface FolderEntry {
  /** Library-relative, "/"-separated on every platform. */
  path: string;
  name: string;
  /** Whether it holds visible subfolders of its own, so the folder tree can offer to expand it. */
  hasSubfolders: boolean;
}

export interface NoteEntry {
  path: string;
  title: string;
  /** Milliseconds since the epoch. */
  modified: number;
}

/** 当前目录内容: direct subfolders and direct notes, never descendants. */
export interface FolderContents {
  folders: FolderEntry[];
  notes: NoteEntry[];
}

export interface Library {
  readonly root: string;
  readFolder(path?: string): Promise<FolderContents>;
  /** The note's Markdown source, verbatim. */
  readNote(path: string): Promise<string>;
}

const collator = new Intl.Collator("zh-Hans-CN", { numeric: true, sensitivity: "base" });

export async function openLibrary(root: string): Promise<Library> {
  const notFolder = new LibraryError("not-a-folder", `找不到笔记库文件夹：${root}`);
  const realRoot = await realpath(root).catch(() => {
    throw notFolder;
  });
  if (!(await stat(realRoot)).isDirectory()) throw notFolder;

  // Every path the library hands out or accepts is relative to the root, "/"-separated, never
  // hidden, and stays inside the root even after links are followed.
  const resolve = async (path: string): Promise<{ real: string; relative: string }> => {
    const parts = path.split(/[\\/]/).filter((part) => part !== "" && part !== ".");
    const outside = new LibraryError("outside-library", `该位置不在当前笔记库内：${path}`);
    if (isAbsolute(path) || parts.some((part) => part.startsWith("."))) throw outside;
    const real = await realpath(join(realRoot, ...parts));
    if (real !== realRoot && !real.startsWith(realRoot + sep)) throw outside;
    return { real, relative: parts.join("/") };
  };

  const readFolder = async (path = ""): Promise<FolderContents> => {
    const { real: dir, relative } = await resolve(path);
    const entries = (await readdir(dir, { withFileTypes: true })).filter((entry) => !entry.name.startsWith("."));
    const childPath = (name: string) => (relative ? `${relative}/${name}` : name);

    const folders = await Promise.all(
      entries
        .filter((entry) => entry.isDirectory())
        .map(async (entry): Promise<FolderEntry> => {
          const inner = await readdir(join(dir, entry.name), { withFileTypes: true }).catch(() => []);
          const hasSubfolders = inner.some((e) => e.isDirectory() && !e.name.startsWith("."));
          return { path: childPath(entry.name), name: entry.name, hasSubfolders };
        }),
    );
    const notes = await Promise.all(
      entries
        .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".md"))
        .map(async (entry): Promise<NoteEntry> => {
          const { mtimeMs } = await stat(join(dir, entry.name));
          return { path: childPath(entry.name), title: entry.name.slice(0, -3), modified: mtimeMs };
        }),
    );
    folders.sort((a, b) => collator.compare(a.name, b.name));
    notes.sort((a, b) => b.modified - a.modified);
    return { folders, notes };
  };
  const readNote = async (path: string) => readFile((await resolve(path)).real, "utf8");
  return { root, readFolder, readNote };
}
