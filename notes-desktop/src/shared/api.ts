import type { FolderContents, LibraryErrorCode, Relocation, SearchOptions, SearchResults } from "../core";

export interface LibraryInfo {
  /** Absolute path of the library folder. */
  root: string;
  /** The folder's own name, shown as the root of the folder tree. */
  name: string;
}

/** The current folder and open note, library-relative; `note` is null when none is open. */
export interface Place {
  folder: string;
  note: string | null;
}

/** What the window shows at launch: the remembered library, or the welcome page. */
export type LaunchState =
  /** `place` is where the user last was in this library, when it is still there. */
  | { kind: "open"; library: LibraryInfo; place?: Place }
  /** `missing` is the remembered library's path when it can no longer be opened. */
  | { kind: "welcome"; missing?: string };

export type SaveResult = { ok: true } | { ok: false; code: LibraryErrorCode; message: string };

/** The page's answer when the window is about to close: everything saved, or why not. */
export type CloseCheck = { saved: true } | { saved: false; message: string };

/** What the renderer may ask of the main process; exposed as `window.notes`. */
export interface NotesApi {
  launchState(): Promise<LaunchState>;
  /** Lets the user pick a folder and opens it; null when they cancel. */
  chooseLibrary(): Promise<LibraryInfo | null>;
  /** Remembers the current folder and open note, to reopen them at the next launch. */
  rememberPlace(place: Place): void;
  /** The page shows where the user left off (or the welcome page); background work may start. */
  shown(): void;
  /** File > 打开笔记库… asks the page, which saves first and then lets the user choose. */
  onOpenLibraryRequest(listener: () => void): () => void;
  readFolder(path: string): Promise<FolderContents>;
  readNote(path: string): Promise<string>;
  /** `expected` is the source last read or saved; a note changed on disk since then is not overwritten. */
  saveNote(path: string, text: string, expected: string): Promise<SaveResult>;
  /** Before the window closes or the app quits, the main process asks the page to save. */
  onBeforeClose(check: () => Promise<CloseCheck>): () => void;

  // 整理笔记与文件夹 (ticket 04). Each answers with a result, so the page can show why it failed.
  /** File > 新建笔记 (⌘N / Ctrl+N): the page creates a note in the current folder. */
  onNewNoteRequest(listener: () => void): () => void;
  createNote(folder: string): Promise<Organized<string>>;
  createFolder(parent: string, name: string): Promise<Organized<string>>;
  rename(path: string, name: string): Promise<Organized<Relocation>>;
  move(path: string, folder: string): Promise<Organized<Relocation>>;
  trash(path: string): Promise<Organized<null>>;
  restoreLastDeleted(): Promise<Organized<string>>;
  listFolders(): Promise<string[]>;
  /** Titles and bodies of the open library; waits for the index the first time. */
  search(query: string, options: SearchOptions): Promise<SearchResults>;
}

/** The outcome of creating, renaming, moving, deleting or restoring. */
export type Organized<T> = { ok: true; value: T } | { ok: false; code: LibraryErrorCode; message: string };

export const channels = {
  launchState: "library:launch-state",
  chooseLibrary: "library:choose",
  rememberPlace: "library:remember-place",
  pageShown: "window:page-shown",
  openLibraryRequest: "menu:open-library",
  openLibraryListening: "menu:open-library-listening",
  readFolder: "library:read-folder",
  readNote: "library:read-note",
  saveNote: "library:save-note",
  beforeClose: "window:before-close",
  closeChecked: "window:close-checked",
  newNoteRequest: "menu:new-note",
  createNote: "library:create-note",
  createFolder: "library:create-folder",
  rename: "library:rename",
  move: "library:move",
  trash: "library:trash",
  restoreLastDeleted: "library:restore-last-deleted",
  listFolders: "library:list-folders",
  search: "library:search",
} as const;
