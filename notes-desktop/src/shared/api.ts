import type { AgentId, Conversation, FolderContents, InstalledAgent, TurnEvent, LibraryErrorCode, Relocation, SearchOptions, SearchResults, SnapshotUsage, SpaceDraft, SpaceErrorCode, SpacePageProblem, SpaceScope } from "../core";

export type { SpacePageProblem };
import type { Appearance } from "./appearance";
import type { Preferences } from "./preferences";

export interface LibraryInfo {
  /** Absolute path of the library folder. */
  root: string;
  /** The folder's own name, shown as the root of the folder tree. */
  name: string;
  /** Something to tell the user once it opens, such as why the old app's spaces could not be moved in. */
  notice?: string;
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

/** A copy saved, with the new note's path, or why not. */
export type CopyResult = { ok: true; path: string } | { ok: false; code: LibraryErrorCode; message: string };

/** The page's answer when the window is about to close: everything saved, or why not. */
export type CloseCheck = { saved: true } | { saved: false; message: string };

/** What the renderer may ask of the main process; exposed as `window.notes`. */
export interface NotesApi {
  /** The window material (and system colours), known before the page draws its first frame. */
  readonly appearance: Appearance;
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
  /** 摘要 of a folder's direct notes, by path, for the 详细 list. */
  readSummaries(path: string): Promise<Record<string, string>>;
  readNote(path: string): Promise<string>;
  /** `expected` is the source last read or saved; a note changed on disk since then is not overwritten. */
  saveNote(path: string, text: string, expected: string): Promise<SaveResult>;
  /** 笔记 › Markdown 源码 in the menu asks the page to show the source (true) or the typeset note. */
  onSourceViewRequest(listener: (showSource: boolean) => void): () => void;
  /** The page tells the menu which view the editor shows, so its check mark follows the card's button. */
  sourceViewChanged(showSource: boolean): void;
  /** Before the window closes or the app quits, the main process asks the page to save. */
  onBeforeClose(check: () => Promise<CloseCheck>): () => void;
  /** A window closed on macOS (only hidden) is shown again, as it was. */
  onShownAgain(listener: () => void): () => void;

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
  /**
   * Something in the open library changed, by this app or any other program: library-relative
   * paths, hidden ones included; "" when anything may have changed.
   */
  onLibraryChanged(listener: (paths: string[]) => void): () => void;
  /** Writes `text` as a new note “<title> 副本” beside the note at `path`, which is left alone. */
  saveCopy(path: string, text: string): Promise<CopyResult>;
  /** Asks before something the user cannot take back; true when they go ahead. */
  confirm(question: Confirmation): Promise<boolean>;

  // 设置 (ticket 15).
  /** The menu's 设置… asks the page to open the settings panel. */
  onSettingsRequest(listener: () => void): () => void;
  /** The preferences as stored when the page loaded, so its first frame already shows them. */
  readonly preferences: Preferences;
  /** Stores a change and applies what the main process owns (外观); answers with all preferences. */
  setPreferences(change: Partial<Preferences>): Promise<Preferences>;
  /** The system accent colour changed while the app runs (#rrggbb, or null when the system does not say). */
  onSystemAccentChanged(listener: (accent: string | null) => void): () => void;
  // 空间 (ticket 18). The space files live in the library's `.notes/空间/`.
  /** The open library's spaces, in the user's order. */
  listSpaces(): Promise<SpaceInfo[]>;
  /** Creates the space and copies the prompt for an external agent to the clipboard. */
  createSpace(draft: SpaceDraft): Promise<SpaceDone<SpaceInfo>>;
  updateSpace(name: string, draft: SpaceDraft): Promise<SpaceDone<SpaceInfo>>;
  /** Moves only the space file to the trash. */
  deleteSpace(name: string): Promise<SpaceDone<null>>;
  reorderSpaces(names: string[]): Promise<SpaceDone<null>>;
  /** Copies the prompt for an external agent to the clipboard. */
  copySpacePrompt(name: string): Promise<SpaceDone<null>>;

  // 助手栏 (ticket 26).
  /** The command-line agents installed on this computer, looked for afresh each time. */
  detectAgents(): Promise<InstalledAgent[]>;
  /** The 助手栏 opened: the open library is snapshotted in the background, ahead of the first turn (ticket 27). */
  prepareSnapshots(): void;
  /** How much disk every library's snapshots take, for 设置 › 助手. */
  snapshotUsage(): Promise<SnapshotUsage>;
  /** Lets every snapshot go now; no turn so far can be undone after. */
  clearSnapshots(): Promise<void>;
  /**
   * Starts a turn (ticket 28): in the conversation given, or in a new one with this agent and working
   * directory. Answers at once with the conversation as it now stands; the turn's events follow.
   */
  startTurn(request: TurnStart): Promise<{ ok: true; conversation: Conversation } | { ok: false; message: string }>;
  /** Stops the conversation's running turn. */
  stopTurn(conversation: string): void;
  /** An event of a running turn, by conversation. */
  onTurnEvent(listener: (conversation: string, event: TurnEvent) => void): () => void;

  // 空间主页 (ticket 19). The homepage runs in a sandbox main lays over the card.
  /** The notes inside a space's scope, by path. */
  spaceNotes(name: string): Promise<SpaceDone<SpaceNote[]>>;
  /** Lays the space's homepage over `bounds` (window coordinates, CSS pixels). */
  showSpacePage(name: string, bounds: Bounds): void;
  /** Takes the homepage off the window; it keeps its state for when it comes back. */
  hideSpacePage(): void;
  /** The operation log, newest first. */
  operationLog(): Promise<SpaceDone<LogItem[]>>;
  /** Takes one entry back; refused, with why, when what it wrote has changed since. */
  undoOperation(id: string): Promise<SpaceDone<null>>;

  // 空间主页的刷新与错误 (ticket 21).
  /** A homepage loaded afresh, went wrong, or wrote through `space`. */
  onSpacePageEvent(listener: (event: SpacePageEvent) => void): () => void;
  /** 复制错误给 agent: the problem, with the space file and the guide, to the clipboard. */
  copySpaceError(name: string, problem: SpacePageProblem): Promise<SpaceDone<null>>;
}

/** What main tells the app about a space's homepage. */
export type SpacePageEvent =
  | { space: string; kind: "loaded" }
  | { space: string; kind: "problem"; problem: SpacePageProblem }
  /** The page wrote through `space`: `changes` operation-log entries, `records` of them records. */
  | { space: string; kind: "wrote"; changes: number; records: number };

export interface TurnStart {
  /** The conversation to continue; null begins one. */
  conversation: string | null;
  /** For a new conversation: its agent and its working directory (library-relative). */
  agent: AgentId;
  folder: string;
  text: string;
  /** Notes put in the context, library-relative. */
  notes: string[];
}

export interface SpaceNote {
  path: string;
  title: string;
}

export interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** An operation-log entry as the log panel shows it. */
export interface LogItem {
  id: string;
  /** ISO 8601. */
  date: string;
  space: string;
  summary: string;
  changes: Array<{ sign: "-" | "+"; text: string }>;
  undone: boolean;
}

/** A space as the side panel shows it. */
export interface SpaceInfo {
  name: string;
  icon: string;
  scope: SpaceScope;
  hasPage: boolean;
}

export type SpaceDone<T> = { ok: true; value: T } | { ok: false; code: SpaceErrorCode | LibraryErrorCode; message: string };

export interface Confirmation {
  message: string;
  detail: string;
  /** The button that goes ahead; the other one cancels. */
  action: string;
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
  readSummaries: "library:read-summaries",
  readNote: "library:read-note",
  saveNote: "library:save-note",
  beforeClose: "window:before-close",
  closeChecked: "window:close-checked",
  sourceViewRequest: "menu:source-view",
  sourceViewChanged: "editor:source-view-changed",
  newNoteRequest: "menu:new-note",
  createNote: "library:create-note",
  createFolder: "library:create-folder",
  rename: "library:rename",
  move: "library:move",
  trash: "library:trash",
  restoreLastDeleted: "library:restore-last-deleted",
  listFolders: "library:list-folders",
  search: "library:search",
  libraryChanged: "library:changed",
  shownAgain: "window:shown-again",
  saveCopy: "library:save-copy",
  confirm: "window:confirm",
  settingsRequest: "menu:settings",
  preferences: "settings:preferences",
  setPreferences: "settings:set-preferences",
  systemAccentChanged: "system:accent-changed",
  listSpaces: "spaces:list",
  createSpace: "spaces:create",
  updateSpace: "spaces:update",
  deleteSpace: "spaces:delete",
  reorderSpaces: "spaces:reorder",
  copySpacePrompt: "spaces:copy-prompt",
  detectAgents: "assistant:detect-agents",
  prepareSnapshots: "assistant:prepare-snapshots",
  snapshotUsage: "assistant:snapshot-usage",
  clearSnapshots: "assistant:clear-snapshots",
  startTurn: "assistant:start-turn",
  stopTurn: "assistant:stop-turn",
  turnEvent: "assistant:turn-event",
  spaceNotes: "spaces:notes",
  showSpacePage: "spaces:show-page",
  hideSpacePage: "spaces:hide-page",
  operationLog: "spaces:operation-log",
  undoOperation: "spaces:undo",
  spacePageEvent: "spaces:page-event",
  copySpaceError: "spaces:copy-error",
} as const;
