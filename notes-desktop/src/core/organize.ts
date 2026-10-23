import { constants } from "node:fs";
import { chmod, cp, lstat, mkdir, mkdtemp, readdir, readFile, realpath, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative as pathFrom, sep } from "node:path";
import { attachmentName, defaultAttachmentFolder, defaultAttachmentSettings, type AttachmentSettings } from "../shared/attachments";
import { imageName, linkPath, type Link } from "../shared/markdown";
import { collator, LibraryError, writeFailures } from "./library";
import { linkTargets, replaceTargets, type LinkTarget } from "./references";
import { spaceLibrary } from "./spaces";

/** Where a renamed or moved item went, and which notes had their links to it rewritten. */
export interface Relocation {
  path: string;
  /** Library-relative paths, after the move, of the notes whose links changed. */
  updated: string[];
}

/** 整理: creating, renaming, moving and deleting notes and folders. */
export interface Organizer {
  /** Creates a note in `folder`, numbering the title ("未命名笔记 2") when it is taken; returns its path. */
  createNote(folder: string, title?: string): Promise<string>;
  /** Creates a folder named `name` in `parent`; returns its path. */
  createFolder(parent: string, name: string): Promise<string>;
  /** Renames a note (`name` is its title) or folder; links to it elsewhere follow, all or nothing. */
  rename(path: string, name: string, vet?: VetRelocation): Promise<Relocation>;
  /** Moves a note or folder into `folder`, keeping its name; links to and from it follow, all or nothing. */
  move(path: string, folder: string, vet?: VetRelocation): Promise<Relocation>;
  /** Moves a note or folder to the system trash; the last one can be restored while the library stays open. */
  trash(path: string): Promise<void>;
  /** Puts the last item moved to the trash back where it was; returns its path. */
  restoreLastDeleted(): Promise<string>;
  /** Every folder in the library except the root, in folder-tree order: where things can move to. */
  listFolders(): Promise<string[]>;
  /**
   * Where a link in `note` leads, found the way renames find it (its target as written, an anchor or
   * alias after it allowed); refuses one that leads nowhere in the library, or to one of several notes.
   */
  followLink(note: string, link: Link): Promise<FollowedLink>;
  /** The image a link in `note` shows, as a data: URL the page can draw; refuses a file it can't show. */
  readImage(note: string, link: Link): Promise<string>;
  /**
   * Copies a file into the attachment folder (附件 at the library root unless the settings say otherwise),
   * named as the settings say and numbered when the name is taken, and returns the
   * Markdown that links to it from `note`: an image's shown in place (`![…](…)`), anything else's a link.
   */
  importAttachment(note: string, name: string, data: Uint8Array): Promise<string>;
}

/** What a link leads to: a note to open, or another file (an attachment, an image) to show or open. */
export type FollowedLink = { kind: "note" | "file"; path: string };

/** Where imported images and attachments go by default, at the library root, as in the old app. */
export const attachmentFolder = defaultAttachmentFolder;
/** The images the page can draw, by extension (the rest of `imageName` are opened, not shown). */
const shownImages: Record<string, string> = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  svg: "image/svg+xml",
  bmp: "image/bmp",
  avif: "image/avif",
};
/** Larger images are not shown in the note (they can still be opened). */
const largestImage = 64 * 1024 * 1024;

/** A note whose links a rename or move rewrites: library paths before and after, and its text. */
export interface LinkRewrite {
  from: string;
  to: string;
  before: string;
  after: string;
}

/**
 * Sees a rename or move before anything is written: where the item goes and which notes' links
 * change. Throwing stops it with nothing written.
 */
export type VetRelocation = (destination: string, rewrites: LinkRewrite[]) => Promise<void>;

export interface OrganizeOptions {
  /** Moves a file or folder, by real location, to the system trash. The app passes Electron's `shell.trashItem`. */
  trash?(path: string): Promise<void>;
  /** 附件设置, looked up on each import (the app passes the current preferences); 附件, original names by default. */
  attachments?(): AttachmentSettings;
  /** Today, for names that carry the date (tests stand in for the clock). */
  now?(): Date;
}

/** What organizing needs from the library it works in. */
export interface LibraryAccess extends OrganizeOptions {
  /** The library folder's real location. */
  root: string;
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

const isNoteFile = (name: string) => /\.md$/i.test(name);
const titleOf = (name: string) => name.replace(/\.md$/i, "");
const reasonOf = (error: unknown) => writeFailures[(error as NodeJS.ErrnoException).code ?? ""] ?? (error as Error).message;

const utf8 = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

/** Replaces a file's contents through a temporary file beside it, keeping its permissions. */
async function replaceFile(path: string, data: string | Buffer) {
  const temp = join(dirname(path), `.${basename(path)}.${process.pid}.saving`);
  try {
    const { mode } = await stat(path);
    await writeFile(temp, data);
    await chmod(temp, mode);
    await rename(temp, path);
  } catch (error) {
    await rm(temp, { force: true });
    throw error;
  }
}

/** Every visible note under `folder`, by real location. */
async function notesUnder(folder: string): Promise<string[]> {
  const entries = await readdir(folder, { withFileTypes: true }).catch(() => []);
  const visible = entries.filter((entry) => !entry.name.startsWith("."));
  const nested = await Promise.all(visible.filter((e) => e.isDirectory()).map((e) => notesUnder(join(folder, e.name))));
  return [...visible.filter((e) => e.isFile() && isNoteFile(e.name)).map((e) => join(folder, e.name)), ...nested.flat()];
}

/** Every file under `folder` but hidden ones (and what hidden folders hold), as real paths. */
async function filesUnder(folder: string): Promise<string[]> {
  const entries = await readdir(folder, { withFileTypes: true }).catch(() => []);
  const visible = entries.filter((entry) => !entry.name.startsWith("."));
  const nested = await Promise.all(visible.filter((e) => e.isDirectory()).map((e) => filesUnder(join(folder, e.name))));
  return [...visible.filter((e) => e.isFile()).map((e) => join(folder, e.name)), ...nested.flat()];
}

const decode = (target: string) => {
  try {
    return decodeURIComponent(target);
  } catch {
    return target;
  }
};

// Characters a Markdown link target can't hold as they are. A note written with percent-encoding
// (e.g. by the old app) keeps it for everything outside the URL path set.
const breaksLink = /[%\s()[\]#?<>]/g;
const outsidePath = /[^A-Za-z0-9\-._~!$&'*+,;=:@/]/gu;
const percentEncode = (char: string) => [...new TextEncoder().encode(char)].map((b) => `%${b.toString(16).toUpperCase().padStart(2, "0")}`).join("");

// Copies keep times (so a restored note sorts where it did), links as written, and share storage
// with the original where the disk can clone.
const copying = { recursive: true, preserveTimestamps: true, verbatimSymlinks: true, errorOnExist: true, force: false, mode: constants.COPYFILE_FICLONE };

/** Moves `from` to `to`, copying when they are on different disks. */
async function moveAcross(from: string, to: string) {
  try {
    await rename(from, to);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EXDEV") throw error;
    await cp(from, to, copying);
    await rm(from, { recursive: true, force: true });
  }
}

/** One note whose links change when an item moves. */
interface Change {
  /** The note's real location before and after the move. */
  from: string;
  to: string;
  before: Buffer;
  after: string;
}

export function organizer({ root, resolve, trash: sendToTrash, attachments = () => defaultAttachmentSettings, now = () => new Date() }: LibraryAccess): Organizer {
  const relativeOf = (real: string) => pathFrom(root, real).split(sep).join("/");
  const inside = (real: string) => real.startsWith(root + sep);
  const realOrNull = (path: string) => realpath(path).catch(() => null);

  const followLink = async (note: string, { target: written, wiki }: Link): Promise<FollowedLink> => {
    const target = linkPath(written);
    const { real } = await resolve(note);
    const named = decode(target);
    const hasExtension = /\.[^./]+$/.test(named);
    const kind = (wiki && !hasExtension) || isNoteFile(named) ? "笔记" : "附件";
    const missing = new LibraryError("not-found", `找不到${kind}“${target}”。`);
    if (!target) throw missing;
    const titles = new Map<string, string[]>();
    if (wiki && !named.includes("/")) {
      for (const path of await notesUnder(root)) {
        const key = titleOf(basename(path)).toLowerCase();
        titles.set(key, [...(titles.get(key) ?? []), path]);
      }
    }
    // `[[报告.pdf]]`, `![[图.png]]`: a file other than a note, by path, or by name in the attachment folder
    // where imports go (or 附件, where they went before it was changed).
    const fileLike = wiki && hasExtension && !isNoteFile(named);
    const link = (path: string, byTitle: boolean): LinkTarget => ({ from: 0, to: path.length, target: path, wiki: byTitle });
    const inAttachments = async () => {
      for (const folder of new Set([attachments().folder, attachmentFolder])) {
        const found = await follow(link(`${folder}/${target}`, false), real, titles);
        if (found) return found;
      }
      return null;
    };
    // Obsidian's way: `![[图.png]]` names the file wherever it is in the library, `[[文件夹/笔记]]` by the
    // end of its path. Of several, the nearest the note: sharing most of its folders, then the shortest path.
    const anywhere = async () => {
      if (!fileLike && !named.includes("/")) return null;
      const wanted = (wiki && !fileLike && !isNoteFile(named) ? `${named}.md` : named).toLowerCase();
      const from = relativeOf(dirname(real)).split("/");
      const shared = (path: string) => {
        const parts = path.split("/");
        let n = 0;
        while (n < from.length && n < parts.length - 1 && parts[n] === from[n]) n++;
        return n;
      };
      const candidates = (await filesUnder(root))
        .map((file) => relativeOf(file))
        .filter((path) => path.toLowerCase() === wanted || path.toLowerCase().endsWith(`/${wanted}`))
        .sort((a, b) => shared(b) - shared(a) || a.split("/").length - b.split("/").length || collator.compare(a, b));
      return candidates[0] ? { real: join(root, ...candidates[0].split("/")) } : null;
    };
    const found =
      (await follow(link(target, wiki && !fileLike), real, titles)) ??
      (fileLike ? await inAttachments() : null) ??
      (wiki ? await anywhere() : null) ??
      // `[摘记](阅读/摘记)`: a Markdown link may leave out .md, as the old app let it.
      (!wiki && !hasExtension ? await follow(link(`${target}.md`, false), real, titles) : null);
    if (found && (await stat(found.real)).isFile()) return { kind: isNoteFile(found.real) ? "note" : "file", path: relativeOf(found.real) };
    const same = titles.get(titleOf(named).toLowerCase()) ?? [];
    if (!found && same.length > 1) {
      const example = titleOf(relativeOf(same[0]!));
      throw new LibraryError("not-found", `有多篇笔记叫“${titleOf(named)}”，请在链接里写上文件夹，例如 [[${example}]]。`);
    }
    throw missing;
  };

  const readImage = async (note: string, link: Link) => {
    const { kind, path } = await followLink(note, link);
    const name = basename(path);
    const type = shownImages[name.slice(name.lastIndexOf(".") + 1).toLowerCase()];
    if (kind !== "file" || !type) throw new LibraryError("not-allowed", `无法在笔记里显示“${name}”，双击可用其他应用打开。`);
    const file = join(root, ...path.split("/"));
    try {
      if ((await stat(file)).size > largestImage) throw new LibraryError("not-allowed", `无法在笔记里显示“${name}”：图片太大，双击可用其他应用打开。`);
      return `data:${type};base64,${(await readFile(file)).toString("base64")}`;
    } catch (error) {
      if (error instanceof LibraryError) throw error;
      throw new LibraryError("not-found", `无法读取“${name}”：${reasonOf(error)}。`);
    }
  };

  const importAttachment = async (note: string, name: string, data: Uint8Array) => {
    checkName(name);
    const { real } = await resolve(note);
    const { folder: within, naming } = attachments();
    const title = titleOf(basename(real));
    const today = now();
    try {
      const folder = join(root, ...within.split("/"));
      await mkdir(folder, { recursive: true });
      // A folder (or a link on the way to it) leading out of the library is refused, as everywhere else.
      const realFolder = await realpath(folder);
      if (realFolder !== root && !inside(realFolder)) throw new LibraryError("not-allowed", `附件文件夹“${within}”不在笔记库里，请在设置里换一个。`);
      // A note's numbers run on across kinds of file: 周一-1.png, then 周一-2.pdf, not 周一-1.pdf.
      const stem = (file: string) => (file.lastIndexOf(".") > 0 ? file.slice(0, file.lastIndexOf(".")) : file).toLowerCase();
      const numbered = naming === "note-number" || naming === "note-date-number";
      const stems = numbered ? new Set((await readdir(realFolder)).map(stem)) : new Set<string>();
      for (let number = 1; ; number += 1) {
        const file = attachmentName(naming, name, title, today, number);
        if (stems.has(stem(file))) continue;
        try {
          // "wx" never replaces a file, even one that appears between choosing the name and writing.
          await writeFile(join(realFolder, file), data, { flag: "wx" });
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code === "EEXIST") continue;
          throw error;
        }
        const path = pathFrom(dirname(real), join(realFolder, file)).split(sep).join("/").replace(breaksLink, percentEncode);
        return `${imageName.test(file) ? "!" : ""}[${file.replace(/[[\]]/g, "")}](${path})`;
      }
    } catch (error) {
      if (error instanceof LibraryError) throw error;
      throw new LibraryError("write-failed", `无法导入“${name}”：${reasonOf(error)}。`);
    }
  };

  const createNote = async (folder: string, title = untitled) => {
    checkName(title);
    const { real: dir, relative } = await resolve(folder);
    for (let number = 1; ; number += 1) {
      const name = number === 1 ? title : `${title} ${number}`;
      try {
        // "wx" never replaces a note, even one that appears between choosing the name and writing.
        // A new note starts empty: its name is the title shown above it, not a heading written into it.
        await writeFile(join(dir, `${name}.md`), "", { flag: "wx" });
        return childPath(relative, `${name}.md`);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw new LibraryError("write-failed", `无法新建笔记：${reasonOf(error)}。`);
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
      throw new LibraryError("write-failed", `无法新建文件夹：${reasonOf(error)}。`);
    }
    return childPath(relative, name);
  };

  /**
   * Where a link points, the way the old app follows it: beside the note, then from the library
   * root, then (for a bare `[[标题]]`) the one note with that title.
   */
  const follow = async (link: LinkTarget, note: string, titles: Map<string, string[]>) => {
    const decoded = decode(link.target);
    const named = link.wiki && !isNoteFile(decoded) ? `${decoded}.md` : decoded;
    const local = await realOrNull(join(dirname(note), named));
    if (local) return inside(local) ? { real: local, beside: named } : null;
    const rooted = await realOrNull(join(root, named));
    if (rooted) return inside(rooted) ? { real: rooted } : null;
    const matches = link.wiki && !decoded.includes("/") ? titles.get(titleOf(decoded).toLowerCase()) : undefined;
    return matches?.length === 1 ? { real: matches[0]! } : null;
  };

  /** The text of a link that reaches `target` from a note at `note`, written the way `link` was. */
  const rewritten = (link: LinkTarget, target: string, note: string) => {
    if (link.wiki) return titleOf(relativeOf(target));
    const path = pathFrom(dirname(note), target).split(sep).join("/");
    return /%[0-9a-f]{2}/i.test(link.target) ? path.replace(outsidePath, percentEncode) : path.replace(breaksLink, percentEncode);
  };

  /** The notes whose links must change when `source` moves to `destination`; nothing is written. */
  const plan = async (source: string, destination: string): Promise<Change[]> => {
    const moved = (real: string) =>
      real === source ? destination : real.startsWith(source + sep) ? destination + real.slice(source.length) : undefined;
    const notes = await notesUnder(root);
    const titles = new Map<string, string[]>();
    for (const note of notes) {
      const key = titleOf(basename(note)).toLowerCase();
      titles.set(key, [...(titles.get(key) ?? []), note]);
    }
    const changes = await Promise.all(
      notes.map(async (note): Promise<Change | null> => {
        const before = await readFile(note);
        let text: string;
        try {
          text = utf8.decode(before);
        } catch {
          return null; // Not UTF-8: never rewritten, as it is never opened.
        }
        const to = moved(note) ?? note;
        const replacements: Array<{ link: LinkTarget; target: string }> = [];
        for (const link of linkTargets(text)) {
          const found = await follow(link, note, titles);
          if (!found) continue;
          const target = moved(found.real);
          // Links to what stays put only change in a note that moves, and only if written relative to it.
          if (!target && !(to !== note && found.beside)) continue;
          // Written relative to the note and still reaching it from where the note ends up: left as written.
          if (found.beside && join(dirname(to), found.beside) === (target ?? found.real)) continue;
          replacements.push({ link, target: rewritten(link, target ?? found.real, to) });
        }
        return replacements.length ? { from: note, to, before, after: replaceTargets(text, replacements) } : null;
      }),
    );
    // In a fixed order, so a failure part way is undone the same way everywhere.
    return changes.filter((change) => change !== null).sort((a, b) => (a.from < b.from ? -1 : 1));
  };

  /** Moves `source` to `destination` and rewrites the links that point at it, undoing everything on failure. */
  const relocate = async (source: string, destination: string, display: string, vet?: VetRelocation): Promise<Relocation> => {
    if (destination === source) return { path: relativeOf(source), updated: [] };
    // Whatever is there already stays; only a change of letter case finds the item itself.
    const existing = await lstat(destination).catch(() => null);
    if (existing) {
      const self = await lstat(source);
      if (existing.ino !== self.ino || existing.dev !== self.dev) throw taken(display);
    }
    const changes = await plan(source, destination);
    await vet?.(
      relativeOf(destination),
      changes.map((change) => ({ from: relativeOf(change.from), to: relativeOf(change.to), before: utf8.decode(change.before), after: change.after })),
    );
    try {
      await rename(source, destination);
    } catch (error) {
      throw new LibraryError("write-failed", `无法移动“${titleOf(basename(source))}”：${reasonOf(error)}。`);
    }
    const written: Change[] = [];
    try {
      for (const change of changes) {
        if (!(await readFile(change.to)).equals(change.before)) {
          throw new LibraryError("conflict", `“${titleOf(basename(change.to))}”刚在别处修改，为避免覆盖，没有改动任何笔记。`);
        }
        await replaceFile(change.to, change.after);
        written.push(change);
      }
    } catch (error) {
      for (const change of written.reverse()) await replaceFile(change.to, change.before).catch(() => {});
      await rename(destination, source).catch(() => {});
      if (error instanceof LibraryError) throw error;
      throw new LibraryError("write-failed", `无法更新指向“${titleOf(basename(source))}”的链接：${reasonOf(error)}。没有改动任何笔记。`);
    }
    // Space scopes and component paths follow too. The move itself stands even if a space file
    // can't be written: that space shows its error, the notes are where the user put them.
    await spaceLibrary(root).syncPaths(relativeOf(source), relativeOf(destination)).catch(() => undefined);
    return { path: relativeOf(destination), updated: changes.map((change) => relativeOf(change.to)).sort() };
  };

  const notAllowed = () => new LibraryError("not-allowed", "不能改名、移动或删除笔记库文件夹本身。");

  const rename_ = async (path: string, name: string, vet?: VetRelocation): Promise<Relocation> => {
    const { real, relative } = await resolve(path);
    if (!relative) throw notAllowed();
    const folder = (await stat(real)).isDirectory();
    const title = folder ? name : titleOf(name);
    checkName(title);
    // A note keeps its own extension, whatever its case.
    const fileName = folder ? title : title + real.slice(-3);
    return relocate(real, join(dirname(real), fileName), title, vet);
  };

  const move = async (path: string, folder: string, vet?: VetRelocation): Promise<Relocation> => {
    const { real, relative } = await resolve(path);
    if (!relative) throw notAllowed();
    const { real: into } = await resolve(folder);
    if (into === real || into.startsWith(real + sep)) throw new LibraryError("not-allowed", "不能把文件夹移到它自己里面。");
    return relocate(real, join(into, basename(real)), titleOf(basename(real)), vet);
  };

  // The system trash can't be asked for an item back the same way on every platform, so what gets
  // restored is a copy taken just before the item went to the trash. The trash keeps its own.
  let lastDeleted: { path: string; copy: string } | null = null;
  const forget = async (deleted: typeof lastDeleted) => {
    if (deleted) await rm(dirname(deleted.copy), { recursive: true, force: true });
  };

  const trash = async (path: string) => {
    const { real, relative } = await resolve(path);
    if (!relative) throw notAllowed();
    const keep = await mkdtemp(join(tmpdir(), "notes-desktop-deleted-"));
    const copy = join(keep, basename(real));
    try {
      if (!sendToTrash) throw new Error("没有可用的废纸篓");
      await cp(real, copy, copying);
      await sendToTrash(real);
    } catch (error) {
      await rm(keep, { recursive: true, force: true });
      throw new LibraryError("write-failed", `无法移到废纸篓：${reasonOf(error)}。`);
    }
    const previous = lastDeleted;
    lastDeleted = { path: relative, copy };
    await forget(previous);
  };

  const restoreLastDeleted = async () => {
    if (!lastDeleted) throw new LibraryError("nothing-to-restore", "没有可以恢复的删除。");
    const { path, copy } = lastDeleted;
    const parts = path.split("/");
    const name = parts.pop()!;
    try {
      // Its folder may have gone since; then that comes back too.
      await mkdir(join(root, ...parts), { recursive: true });
      const { real: folder } = await resolve(parts.join("/"));
      const destination = join(folder, name);
      if (await lstat(destination).catch(() => null)) {
        throw new LibraryError("exists", `已经存在“${titleOf(name)}”，请先把它改名或移走，再恢复。`);
      }
      await moveAcross(copy, destination);
    } catch (error) {
      if (error instanceof LibraryError) throw error;
      throw new LibraryError("write-failed", `无法恢复“${titleOf(name)}”：${reasonOf(error)}。`);
    }
    await forget(lastDeleted);
    lastDeleted = null;
    return path;
  };

  const listFolders = async (folder = root): Promise<string[]> => {
    const entries = await readdir(folder, { withFileTypes: true }).catch(() => []);
    const names = entries.filter((e) => e.isDirectory() && !e.name.startsWith(".")).map((e) => e.name);
    const nested = await Promise.all(
      names.sort(collator.compare).map(async (name) => [relativeOf(join(folder, name)), ...(await listFolders(join(folder, name)))]),
    );
    return nested.flat();
  };

  return { createNote, createFolder, rename: rename_, move, trash, restoreLastDeleted, listFolders: () => listFolders(), followLink, readImage, importAttachment };
}
