import type { FolderContents } from "../core/library";

export interface LibraryInfo {
  /** Absolute path of the library folder. */
  root: string;
  /** The folder's own name, shown as the root of the folder tree. */
  name: string;
}

/** What the renderer may ask of the main process; exposed as `window.notes`. */
export interface NotesApi {
  /** The library opened at launch: the remembered one, or null on first launch or when it is gone. */
  currentLibrary(): Promise<LibraryInfo | null>;
  /** Lets the user pick a folder and opens it; null when they cancel. */
  chooseLibrary(): Promise<LibraryInfo | null>;
  /** Called when another library is opened from the app menu. */
  onLibraryChanged(listener: (library: LibraryInfo) => void): () => void;
  readFolder(path: string): Promise<FolderContents>;
  readNote(path: string): Promise<string>;
}

export const channels = {
  currentLibrary: "library:current",
  chooseLibrary: "library:choose",
  libraryChanged: "library:changed",
  readFolder: "library:read-folder",
  readNote: "library:read-note",
} as const;
