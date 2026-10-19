import type { FolderContents, LibraryErrorCode } from "../core";

export interface LibraryInfo {
  /** Absolute path of the library folder. */
  root: string;
  /** The folder's own name, shown as the root of the folder tree. */
  name: string;
}

/** What the window shows at launch: the remembered library, or the welcome page. */
export type LaunchState =
  | { kind: "open"; library: LibraryInfo }
  /** `missing` is the remembered library's path when it can no longer be opened. */
  | { kind: "welcome"; missing?: string };

export type SaveResult = { ok: true } | { ok: false; code: LibraryErrorCode; message: string };

/** A copy saved, with the new note's path, or why not. */
export type CopyResult = { ok: true; path: string } | { ok: false; code: LibraryErrorCode; message: string };

/** The page's answer when the window is about to close: everything saved, or why not. */
export type CloseCheck = { saved: true } | { saved: false; message: string };

/** What the renderer may ask of the main process; exposed as `window.notes`. */
export interface NotesApi {
  launchState(): Promise<LaunchState>;
  /** Lets the user pick a folder and opens it; null when they cancel. */
  chooseLibrary(): Promise<LibraryInfo | null>;
  /** File > 打开笔记库… asks the page, which saves first and then lets the user choose. */
  onOpenLibraryRequest(listener: () => void): () => void;
  readFolder(path: string): Promise<FolderContents>;
  readNote(path: string): Promise<string>;
  /** `expected` is the source last read or saved; a note changed on disk since then is not overwritten. */
  saveNote(path: string, text: string, expected: string): Promise<SaveResult>;
  /** Before the window closes or the app quits, the main process asks the page to save. */
  onBeforeClose(check: () => Promise<CloseCheck>): () => void;
  /**
   * Something in the open library changed, by this app or any other program: library-relative
   * paths, hidden ones included; "" when anything may have changed.
   */
  onLibraryChanged(listener: (paths: string[]) => void): () => void;
  /** Writes `text` as a new note “<title> 副本” beside the note at `path`, which is left alone. */
  saveCopy(path: string, text: string): Promise<CopyResult>;
}

export const channels = {
  launchState: "library:launch-state",
  chooseLibrary: "library:choose",
  openLibraryRequest: "menu:open-library",
  openLibraryListening: "menu:open-library-listening",
  readFolder: "library:read-folder",
  readNote: "library:read-note",
  saveNote: "library:save-note",
  beforeClose: "window:before-close",
  closeChecked: "window:close-checked",
  libraryChanged: "library:changed",
  saveCopy: "library:save-copy",
} as const;
