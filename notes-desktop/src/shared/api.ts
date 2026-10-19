import type { FolderContents } from "../core";

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

/** What the renderer may ask of the main process; exposed as `window.notes`. */
export interface NotesApi {
  launchState(): Promise<LaunchState>;
  /** Lets the user pick a folder and opens it; null when they cancel. */
  chooseLibrary(): Promise<LibraryInfo | null>;
  /** Called when another library is opened from the app menu. */
  onLibraryChanged(listener: (library: LibraryInfo) => void): () => void;
  readFolder(path: string): Promise<FolderContents>;
  readNote(path: string): Promise<string>;
}

export const channels = {
  launchState: "library:launch-state",
  chooseLibrary: "library:choose",
  libraryChanged: "library:changed",
  readFolder: "library:read-folder",
  readNote: "library:read-note",
} as const;
