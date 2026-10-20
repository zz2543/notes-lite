import { chmod, open, readFile, readdir, realpath, rename, rm, stat, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, sep } from "node:path";
import { noteSummary } from "./markdown";
import { organizer, type OrganizeOptions, type Organizer } from "./organize";

export type LibraryErrorCode =
  | "not-a-folder"
  | "outside-library"
  | "not-found"
  | "not-utf8"
  | "conflict"
  | "write-failed"
  // 整理笔记与文件夹
  | "invalid-name"
  | "exists"
  | "not-allowed"
  | "nothing-to-restore";

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

export interface Library extends Organizer {
  readonly root: string;
  readFolder(path?: string): Promise<FolderContents>;
  /** 摘要 of the folder's direct notes, by path; "" for a note with no prose or that cannot be read. */
  readSummaries(path?: string): Promise<Record<string, string>>;
  /** The note's Markdown source, verbatim. */
  readNote(path: string): Promise<string>;
  /**
   * Writes `text` exactly. `expected` is the source the caller last read or saved; if the file on
   * disk no longer matches it, nothing is written.
   */
  saveNote(path: string, text: string, expected: string): Promise<void>;
  /**
   * Writes `text` as a new note “<title> 副本” beside the note at `path`, which is left as it is,
   * and returns the new note's path.
   */
  saveCopy(path: string, text: string): Promise<string>;
}

/** Why the disk refused a write, in the words shown to the user. */
export const writeFailures: Record<string, string> = {
  EACCES: "没有写入权限",
  EPERM: "没有写入权限",
  EROFS: "所在磁盘是只读的",
  ENOSPC: "磁盘空间不足",
  ENOENT: "找不到这篇笔记或它所在的文件夹",
  EBUSY: "文件正被其他程序占用",
};

// Strict, and keeping a byte-order mark as text, so that decoding and re-encoding is lossless.
const utf8 = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
// 摘要 reads only this much of each note.
const summaryBytes = 8192;

export const collator = new Intl.Collator("zh-Hans-CN", { numeric: true, sensitivity: "base" });

export async function openLibrary(root: string, options: OrganizeOptions = {}): Promise<Library> {
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
    const real = await realpath(join(realRoot, ...parts)).catch((error: NodeJS.ErrnoException) => {
      // Moved, renamed or deleted by another program since it was listed.
      if (error.code !== "ENOENT" && error.code !== "ENOTDIR") throw error;
      const name = (parts.at(-1) ?? basename(realRoot)).replace(/\.md$/i, "");
      throw new LibraryError("not-found", `找不到“${name}”，它可能已在别处移动或删除。`);
    });
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
  const readNote = async (path: string) => {
    const { real } = await resolve(path);
    try {
      return utf8.decode(await readFile(real));
    } catch (error) {
      if (!(error instanceof TypeError)) throw error;
      throw new LibraryError("not-utf8", `“${basename(real, ".md")}”不是 UTF-8 编码，为避免保存时损坏内容，暂不打开。`);
    }
  };
  const saveNote = async (path: string, text: string, expected: string) => {
    const { real } = await resolve(path);
    // Write beside the note and swap it in, so a failed write never leaves half a note behind. Like
    // the old app's atomic write, the swap keeps the note's permissions but not extended attributes.
    const temp = join(dirname(real), `.${basename(real)}.${process.pid}.saving`);
    try {
      // Compared as bytes: a note that changed, or never was the UTF-8 text the caller holds, is left alone.
      const disk = await readFile(real);
      if (!disk.equals(Buffer.from(expected, "utf8"))) throw new LibraryError("conflict", "这篇笔记已在别处修改。");
      const { mode } = await stat(real);
      await writeFile(temp, text, "utf8");
      await chmod(temp, mode);
      await rename(temp, real);
    } catch (error) {
      await rm(temp, { force: true });
      if (error instanceof LibraryError) throw error;
      const reason = writeFailures[(error as NodeJS.ErrnoException).code ?? ""] ?? (error as Error).message;
      throw new LibraryError("write-failed", `无法保存“${basename(real, ".md")}”：${reason}。`);
    }
  };
  const saveCopy = async (path: string, text: string) => {
    const parts = path.split(/[\\/]/).filter((part) => part !== "" && part !== ".");
    const note = parts.pop() ?? "";
    if (isAbsolute(path) || note.startsWith(".")) throw new LibraryError("outside-library", `该位置不在当前笔记库内：${path}`);
    const title = note.replace(/\.md$/i, "");
    // A folder that went away with the note leaves the copy at the library root.
    const { real: folder, relative } = await resolve(parts.join("/")).catch((error: unknown) => {
      if (error instanceof LibraryError && error.code === "not-found") return { real: realRoot, relative: "" };
      throw error;
    });
    for (let number = 1; ; number++) {
      const name = `${title} 副本${number > 1 ? ` ${number}` : ""}.md`;
      try {
        // Created, never replaced: an earlier copy keeps what it holds.
        await writeFile(join(folder, name), text, { encoding: "utf8", flag: "wx" });
        return relative ? `${relative}/${name}` : name;
      } catch (error) {
        const code = (error as NodeJS.ErrnoException).code ?? "";
        if (code === "EEXIST") continue;
        throw new LibraryError("write-failed", `无法另存“${title}”的副本：${writeFailures[code] ?? (error as Error).message}。`);
      }
    }
  };
  const readSummaries = async (path = ""): Promise<Record<string, string>> => {
    const { real: dir } = await resolve(path);
    const { notes } = await readFolder(path);
    const summaries = await Promise.all(
      notes.map(async (note) => {
        const file = await open(join(dir, basename(note.path))).catch(() => null);
        if (!file) return [note.path, ""] as const;
        try {
          // The opening of the note is enough for one line; a character cut in half at the end is no error.
          const { buffer, bytesRead } = await file.read(Buffer.alloc(summaryBytes), 0, summaryBytes, 0);
          const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(buffer.subarray(0, bytesRead), { stream: true });
          return [note.path, noteSummary(text)] as const;
        } catch {
          return [note.path, ""] as const;
        } finally {
          await file.close();
        }
      }),
    );
    return Object.fromEntries(summaries);
  };
  return { root, readFolder, readSummaries, readNote, saveNote, saveCopy, ...organizer({ ...options, root: realRoot, resolve }) };
}
