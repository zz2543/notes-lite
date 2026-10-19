import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { LibraryError } from "./library";

/** 整理: creating, renaming, moving and deleting notes and folders. */
export interface Organizer {
  /** Creates a note in `folder`, numbering the title ("未命名笔记 2") when it is taken; returns its path. */
  createNote(folder: string, title?: string): Promise<string>;
  /** Creates a folder named `name` in `parent`; returns its path. */
  createFolder(parent: string, name: string): Promise<string>;
}

/** What organizing needs from the library it works in. */
export interface LibraryAccess {
  /** A library-relative path checked to exist inside the library, and its real location. */
  resolve(path: string): Promise<{ real: string; relative: string }>;
}

const untitled = "未命名笔记";

const childPath = (folder: string, name: string) => (folder ? `${folder}/${name}` : name);

// A library syncs between macOS and Windows, so a name must work on both.
const forbidden = /[\\/:*?"<>|\u0000-\u001f]/;
const reserved = /^(?:con|prn|aux|nul|com\d|lpt\d)(?:\..*)?$/i;

function checkName(name: string) {
  if (!name.trim() || name.startsWith(".") || forbidden.test(name)) {
    throw new LibraryError("invalid-name", "名称不能为空，不能以“.”开头，也不能包含 \\ / : * ? \" < > | 这些字符。");
  }
  if (/[. ]$/.test(name) || reserved.test(name)) throw new LibraryError("invalid-name", `“${name}”在 Windows 上不能用作名称，请换一个。`);
}

const taken = (name: string) => new LibraryError("exists", `已经存在“${name}”，请换一个名称。`);

export function organizer({ resolve }: LibraryAccess): Organizer {
  const createNote = async (folder: string, title = untitled) => {
    const { real: dir, relative } = await resolve(folder);
    for (let number = 1; ; number += 1) {
      const name = number === 1 ? title : `${title} ${number}`;
      try {
        // "wx" never replaces a note, even one that appears between choosing the name and writing.
        await writeFile(join(dir, `${name}.md`), `# ${name}\n\n`, { flag: "wx" });
        return childPath(relative, `${name}.md`);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw new LibraryError("write-failed", `无法新建笔记：${(error as Error).message}`);
      }
    }
  };

  const createFolder = async (parent: string, name: string) => {
    checkName(name);
    const { real: dir, relative } = await resolve(parent);
    try {
      await mkdir(join(dir, name));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "EEXIST") throw taken(name);
      throw new LibraryError("write-failed", `无法新建文件夹：${(error as Error).message}`);
    }
    return childPath(relative, name);
  };

  return { createNote, createFolder };
}
