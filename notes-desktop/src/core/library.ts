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

  // Every path the library hands out or accepts is relative to the root, never hidden, and stays
  // inside the root even after links are followed.
  const resolve = async (path: string): Promise<string> => {
    const parts = path.split(/[\\/]/).filter((part) => part !== "" && part !== ".");
    const outside = new LibraryError("outside-library", `该位置不在当前笔记库内：${path}`);
    if (isAbsolute(path) || parts.some((part) => part.startsWith("."))) throw outside;
    const real = await realpath(join(realRoot, ...parts));
    if (real !== realRoot && !real.startsWith(realRoot + sep)) throw outside;
    return real;
  };

  const readFolder = async (path = ""): Promise<FolderContents> => {
    const dir = await resolve(path);
    const entries = await readdir(dir, { withFileTypes: true });
    const folders: FolderEntry[] = [];
    const notes: NoteEntry[] = [];
    for (const entry of entries) {
      if (entry.name.startsWith(".")) continue;
      const child = path ? `${path}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        const inner = await readdir(join(dir, entry.name), { withFileTypes: true }).catch(() => []);
        const hasSubfolders = inner.some((e) => e.isDirectory() && !e.name.startsWith("."));
        folders.push({ path: child, name: entry.name, hasSubfolders });
      }
      if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) {
        const info = await stat(join(dir, entry.name));
        notes.push({ path: child, title: entry.name.slice(0, -3), modified: info.mtimeMs });
      }
    }
    folders.sort((a, b) => collator.compare(a.name, b.name));
    notes.sort((a, b) => b.modified - a.modified);
    return { folders, notes };
  };
  const readNote = async (path: string) => readFile(await resolve(path), "utf8");
  return { root, readFolder, readNote };
}
