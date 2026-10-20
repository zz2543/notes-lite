import { app, BrowserWindow, clipboard, dialog, ipcMain, Menu, nativeTheme, shell, systemPreferences, type Rectangle } from "electron";
import type { IpcMainEvent, MenuItemConstructorOptions, OpenDialogOptions, WebContents } from "electron";
import { stat } from "node:fs/promises";
import { homedir, release } from "node:os";
import { basename, delimiter, join } from "node:path";
import { execFile } from "node:child_process";
import {
  addEvent,
  conversationStore,
  createSearchIndex,
  detectAgents,
  emptyReply,
  runTurn,
  type Conversation,
  LibraryError,
  entryChanges,
  entrySummary,
  migrateLegacyFolder,
  notesInScope,
  openLibrary,
  operationLog,
  OperationLogError,
  snapshotStore,
  SpaceError,
  spaceErrorReport,
  spaceLibrary,
  spaceStorage,
  watchLibrary,
  type Library,
  type LibraryWatcher,
  type OrganizeOptions,
  type Relocation,
  type SearchIndex,
  type SearchOptions,
  type Space,
  type SpaceDraft,
  type SpacePageProblem,
  type TurnEvent,
} from "../core";
import {
  channels,
  type CloseCheck,
  type Confirmation,
  type CopyResult,
  type LaunchState,
  type LibraryInfo,
  type LogItem,
  type Organized,
  type Place,
  type SaveResult,
  type SpaceDone,
  type SpaceInfo,
  type SpaceNote,
  type TurnStart,
} from "../shared/api";
import { appearanceArguments, type Appearance } from "../shared/appearance";
import { defaultPreferences, readPreferences, type Preferences } from "../shared/preferences";
import { materialWindowOptions, windowMaterial } from "./material";
import { settingsStore } from "./settings";
import { spacePageSettings } from "./spaceKit";
import { registerSpaceScheme, spacePages } from "./spacePages";

// A separate profile, for tests and for running beside an installed copy.
if (process.env.NOTES_DESKTOP_USER_DATA) app.setPath("userData", process.env.NOTES_DESKTOP_USER_DATA);
registerSpaceScheme();

const settings = settingsStore(app.getPath("userData"));
const mac = process.platform === "darwin";
let library: Library | null = null;
let window: BrowserWindow | null = null;
// Each homepage's own storage, kept with the app (spaces-spec #51).
const homepageStorage = spaceStorage(join(app.getPath("userData"), "space-storage.json"));
// Space homepages, each in its own sandbox laid over the card.
// A homepage takes the app's 排版, 强调色 and 动效 (spaceKit), and follows them when they change.
const pages = spacePages(
  () => window,
  () => library?.root ?? null,
  () => spacePageSettings(preferences, systemAppearance().accent),
  (event) => window && !window.isDestroyed() && window.webContents.send(channels.spacePageEvent, event),
  (paths) => changedHere(paths),
  homepageStorage,
);
// Set once the page has saved (or the user chose to drop unsaved input), so the next close goes through.
let closeAllowed = false;
// The close check in progress; the first answer (the page's, or the timeout's) consumes it.
let closeCheck: number | null = null;
let closeChecks = 0;
let quitting = false;
// File > 打开笔记库… with no window open: asked again once the new page listens.
let openLibraryPending = false;
const closeCheckTimeout = 5000;
const showFallback = 500;
const backgroundWorkFallback = 3000;
const sourceViewItem = "source-view";

// Windows keeps its system frame (and so the fallback colour) until the app draws its own title bar there.
const material = windowMaterial({ platform: process.platform, release: release(), frameless: false });

/**
 * The PATH a terminal sets up, read once from the user's login shell: an app opened from the Finder
 * does not get it, and agents installed through nvm, say, are only on it. Not on Windows, where apps
 * get the user's PATH anyway.
 */
let loginShellPath: Promise<string | undefined> | undefined;
function shellPath(): Promise<string | undefined> {
  if (process.platform === "win32") return Promise.resolve(undefined);
  loginShellPath ??= new Promise((done) => {
    const shell = process.env.SHELL || "/bin/zsh";
    const marker = "__NOTES_DESKTOP_PATH__";
    execFile(shell, ["-ilc", `printf '${marker}%s' "$PATH"`], { timeout: 3000 }, (error, stdout) => {
      const at = stdout.lastIndexOf(marker);
      done((!error && at >= 0 && stdout.slice(at + marker.length).trim()) || undefined);
    });
  });
  return loginShellPath;
}

function installerFolders(): Array<string | undefined> {
  const home = homedir();
  return process.platform === "win32"
    ? [process.env.APPDATA && join(process.env.APPDATA, "npm"), join(home, ".local", "bin")]
    : [join(home, ".local", "bin"), join(home, ".claude", "local"), "/opt/homebrew/bin", "/usr/local/bin", join(home, ".npm-global", "bin"), join(home, ".bun", "bin"), join(home, ".volta", "bin")];
}

/** The login shell's PATH, this process's, then the folders agent installers use. */
const fullPath = async () => [await shellPath(), process.env.PATH, ...installerFolders()].filter(Boolean).join(delimiter);

/** Where the command-line agents are looked for. NOTES_DESKTOP_AGENT_PATH (tests) replaces the whole search path. */
async function agentSearchPath(): Promise<string> {
  if (process.env.NOTES_DESKTOP_AGENT_PATH !== undefined) return process.env.NOTES_DESKTOP_AGENT_PATH;
  return fullPath();
}

/** What an agent runs with: this environment, with the PATH a terminal would have (so its own tools are found). */
async function agentEnvironment(): Promise<NodeJS.ProcessEnv> {
  const key = Object.keys(process.env).find((name) => name.toUpperCase() === "PATH") ?? "PATH";
  if (process.env.NOTES_DESKTOP_AGENT_PATH !== undefined) return process.env;
  return { ...process.env, [key]: await fullPath() };
}

/** The look the page needs before its first frame; the accent is read again for each new window. */
function systemAppearance(): Appearance {
  let accent: string | null = null;
  if (mac || process.platform === "win32") {
    // RGBA hex; the design system's blue stands in when the system does not say.
    const rgba = systemPreferences.getAccentColor();
    if (/^[0-9a-f]{6}/i.test(rgba)) accent = `#${rgba.slice(0, 6)}`;
  }
  return { material, accent };
}

const libraryInfo = (lib: Library, notice?: string): LibraryInfo => ({ root: lib.root, name: basename(lib.root), ...(notice ? { notice } : {}) });

// Deleting goes to the system trash. Looked up on each call, so tests can stand in for the trash.
const libraryOptions: OrganizeOptions = { trash: (path) => shell.trashItem(path) };

// 快照 of every library before each assistant turn, kept with the app (never in a library). macOS clones
// attachments; elsewhere they are copied, up to about 10 GB. NOTES_DESKTOP_SNAPSHOT_COPY_LIMIT (tests)
// copies on every platform, with that limit in bytes.
const copyLimit = Number(process.env.NOTES_DESKTOP_SNAPSHOT_COPY_LIMIT) || undefined;
const snapshots = snapshotStore(join(app.getPath("userData"), "snapshots"), {
  trash: (path) => shell.trashItem(path),
  ...(copyLimit ? { attachments: "copy" as const, copyLimit } : {}),
});

// 对话记录, kept with the app; the conversations of this run stay in memory too.
const conversations = conversationStore(join(app.getPath("userData"), "conversations"));
const conversationsOpen = new Map<string, Conversation>();
const running = new Map<string, AbortController>();

type Started = { ok: true; conversation: Conversation } | { ok: false; message: string };

/** Begins (or continues) a conversation's turn and passes its events to the page as they come. */
async function startTurn(page: WebContents, request: TurnStart): Promise<Started> {
  const lib = library;
  if (!lib) return { ok: false, message: "请先打开笔记库。" };
  const known = request.conversation
    ? (conversationsOpen.get(request.conversation) ?? (await conversations.read(request.conversation).catch(() => undefined)))
    : undefined;
  const conversation = known ?? conversations.start({ agent: request.agent, root: lib.root, folder: request.folder });
  if (conversation.root !== lib.root) return { ok: false, message: "这个对话属于另一个笔记库。" };
  if (running.has(conversation.id)) return { ok: false, message: "上一轮还没有结束。" };
  const installed = await detectAgents({ path: await agentSearchPath(), pathext: process.env.PATHEXT });
  const agent = installed.find((a) => a.id === conversation.agent);
  if (!agent) return { ok: false, message: "没有找到这个对话所用的 Agent，请确认它仍然安装着。" };
  conversation.messages.push({ role: "user", text: request.text, notes: request.notes }, emptyReply());
  conversationsOpen.set(conversation.id, conversation);
  await conversations.save(conversation);
  const stop = new AbortController();
  running.set(conversation.id, stop);
  const replyAt = conversation.messages.length - 1;
  const pass = (event: TurnEvent) => {
    if (event.kind === "session") conversation.session = event.id;
    const reply = conversation.messages[replyAt];
    if (reply?.role === "assistant") conversation.messages[replyAt] = addEvent(reply, event);
    if (!page.isDestroyed()) page.send(channels.turnEvent, conversation.id, event);
  };
  const turns = snapshots.library(lib.root);
  void runTurn({
    agent,
    root: lib.root,
    folder: conversation.folder,
    text: request.text,
    notes: request.notes,
    session: conversation.session,
    snapshots: turns,
    log: operationLog(lib.root, { ...libraryOptions, turns }),
    env: await agentEnvironment(),
    signal: stop.signal,
    onEvent: pass,
  })
    .catch((error: Error) => {
      // The snapshots themselves failed: the turn ends saying why.
      const reply = conversation.messages[replyAt];
      if (reply?.role === "assistant" && !reply.done) pass({ kind: "end", changes: [], failed: error.message });
    })
    .finally(() => {
      running.delete(conversation.id);
      void conversations.save(conversation).catch(() => undefined);
    });
  return { ok: true, conversation };
}

/**
 * Readies a library just opened: the old app's `.留白/` moves into `.notes/` (and then to the trash) the first time, and the
 * authoring guide follows this version. Answers with what the user should be told, if anything.
 */
async function prepare(lib: Library): Promise<string | undefined> {
  const migration = await migrateLegacyFolder(lib.root, libraryOptions);
  const spaces = spaceLibrary(lib.root, libraryOptions);
  if ((await spaces.spaces()).length > 0) await spaces.installGuide().catch(() => undefined);
  return migration.kind === "failed" ? migration.message : undefined;
}

let watcher: LibraryWatcher | null = null;
let watched: Library | null = null;

/** Passes every change in the open library, made here or by another program, on to the page. */
function watch(lib: Library) {
  watcher?.close();
  watched = lib;
  try {
    watcher = watchLibrary(lib.root, (paths) => {
      // Search finds notes as they are now, whoever changed them.
      for (const path of paths) if (!path.split("/").some((part) => part.startsWith("."))) noteChanged(path);
      if (window && !window.isDestroyed()) window.webContents.send(channels.libraryChanged, paths);
      // Open homepages follow too: a rewritten space file, or notes changed in their scope.
      void pages.libraryChanged(paths).catch(() => undefined);
    });
  } catch {
    // A folder the system will not watch still opens; it just won't follow changes made elsewhere.
    watcher = null;
  }
}

// Read once at start, before the app is even ready; the window waits for it (a few hundred bytes).
const stored = settings.read();

// 设置: kept in memory, so the page can have them synchronously before its first frame.
let preferences: Preferences = defaultPreferences;
const preferencesReady = stored.then((s) => void (preferences = readPreferences(s.preferences)));

/** What the main process itself draws from the preferences: light or dark, for the page and the material alike. */
function applyPreferences() {
  nativeTheme.themeSource = preferences.colorScheme;
  // An opaque window's own colour shows before the page paints (on resize, say); it follows too.
  const { backgroundColor } = materialWindowOptions(material, nativeTheme.shouldUseDarkColors);
  if (backgroundColor && window && !window.isDestroyed()) window.setBackgroundColor(backgroundColor);
}

async function changePreferences(change: unknown): Promise<Preferences> {
  preferences = readPreferences(change, preferences);
  applyPreferences();
  pages.settingsChanged();
  await settings.update({ preferences });
  return preferences;
}

// Starts while the window loads, so the remembered library is ready by the time the page asks.
const launch: Promise<LaunchState> = (async () => {
  const { libraryPath, place } = await stored;
  if (!libraryPath) return { kind: "welcome" };
  library = await openLibrary(libraryPath, libraryOptions).catch(() => null);
  if (!library) return { kind: "welcome", missing: libraryPath };
  const notice = await prepare(library);
  const found = place && (await stillThere(library, place));
  if (found) readAhead(library, found);
  return { kind: "open", library: libraryInfo(library, notice), place: found };
})();

// What the page reads first at launch (the reopened folder with the folders above it, and the
// note), read while the page itself is still loading. Each answers the page's first ask once.
const readsAhead = new Map<string, Promise<unknown>>();

function readAhead(lib: Library, place: Place) {
  const parts = place.folder ? place.folder.split("/") : [];
  for (const folder of ["", ...parts.map((_, i) => parts.slice(0, i + 1).join("/"))]) {
    readsAhead.set(`folder:${folder}`, lib.readFolder(folder));
  }
  if (place.note) readsAhead.set(`note:${place.note}`, lib.readNote(place.note));
  // An answer nobody asks for is no error worth reporting; the page reads again if it needs to.
  for (const read of readsAhead.values()) read.catch(() => {});
}

/** The answer read ahead for `key`, the first time it is asked for; otherwise reads now. */
function readOnce<T>(key: string, read: () => Promise<T>): Promise<T> {
  const ahead = readsAhead.get(key) as Promise<T> | undefined;
  readsAhead.delete(key);
  return ahead ?? read();
}

/** The part of a remembered place the library still has: a gone note is dropped, a gone folder too. */
async function stillThere(lib: Library, place: Place): Promise<Place | undefined> {
  const is = (path: string, kind: "file" | "folder") =>
    stat(join(lib.root, path)).then((found) => (kind === "file" ? found.isFile() : found.isDirectory()), () => false);
  if (typeof place.folder !== "string" || !(await is(place.folder, "folder"))) return undefined;
  const note = typeof place.note === "string" && (await is(place.note, "file")) ? place.note : null;
  return { folder: place.folder, note };
}

async function chooseLibrary(): Promise<LibraryInfo | null> {
  const options: OpenDialogOptions = {
    title: "选择笔记库",
    buttonLabel: "打开",
    properties: ["openDirectory", "createDirectory"],
  };
  const picked = window ? await dialog.showOpenDialog(window, options) : await dialog.showOpenDialog(options);
  const path = picked.filePaths[0];
  if (picked.canceled || !path) return null;
  library = await openLibrary(path, libraryOptions);
  pages.closeAll();
  readsAhead.clear();
  const notice = await prepare(library);
  watch(library);
  // A new library starts at its root; the place remembered belonged to the old one.
  await settings.update({ libraryPath: path, place: undefined });
  return libraryInfo(library, notice);
}

function requireLibrary(): Library {
  if (!library) throw new Error("请先打开笔记库。");
  return library;
}

// The open library's search index. It is built in the background once the window is up (or a
// library is chosen), never before the first note shows, and again whenever the library changes.
let index: { library: Library; index: SearchIndex } | null = null;

function searchIndex(): SearchIndex {
  const lib = requireLibrary();
  if (index?.library !== lib) index = { library: lib, index: createSearchIndex(lib.root) };
  return index.index;
}

const indexInBackground = () => void (library && searchIndex());

/** Once the page shows the remembered library: index it and follow its changes, if not yet. */
function startBackgroundWork() {
  // Turns begun more than 30 days ago go, in every library.
  void snapshots.clean().catch(() => undefined);
  if (!library) return;
  if (watched !== library) watch(library);
  indexInBackground();
}

/** A note the app saved (or otherwise changed) is searched as it is now. */
function noteChanged(path: string) {
  if (index && index.library === library) void index.index.update(path);
}

/** The app itself changed these paths: search reads them again, and an assistant turn running now leaves them out. */
async function changedHere(paths: string[]) {
  for (const path of paths) noteChanged(path);
  if (library) await snapshots.library(library.root).appWrote(paths).catch(() => undefined);
}

function registerIpc() {
  ipcMain.handle(channels.launchState, () => launch);
  ipcMain.handle(channels.chooseLibrary, async () => {
    const chosen = await chooseLibrary();
    indexInBackground();
    return chosen;
  });
  ipcMain.handle(channels.readSummaries, (_, path: string) => requireLibrary().readSummaries(path));
  ipcMain.on(channels.rememberPlace, (_, place: Place) => void settings.update({ place }).catch(() => {}));
  ipcMain.handle(channels.readFolder, (_, path: string) => readOnce(`folder:${path}`, () => requireLibrary().readFolder(path)));
  ipcMain.handle(channels.readNote, (_, path: string) => readOnce(`note:${path}`, () => requireLibrary().readNote(path)));
  // Errors cross IPC as plain messages, so a save answers with a result the page can act on.
  ipcMain.handle(channels.saveNote, async (_, path: string, text: string, expected: string): Promise<SaveResult> => {
    try {
      await requireLibrary().saveNote(path, text, expected);
      await changedHere([path]);
      return { ok: true };
    } catch (error) {
      const code = error instanceof LibraryError ? error.code : "write-failed";
      return { ok: false, code, message: (error as Error).message };
    }
  });
  ipcMain.on(channels.sourceViewChanged, (_, showSource: boolean) => {
    const item = Menu.getApplicationMenu()?.getMenuItemById(sourceViewItem);
    if (item) item.checked = showSource;
  });
  // 整理笔记与文件夹: a refusal (a taken name, say) reaches the page as a result it can show.
  const organize = <T>(channel: string, run: (lib: Library, ...args: string[]) => Promise<T>) =>
    ipcMain.handle(channel, async (_, ...args: string[]): Promise<Organized<T>> => {
      try {
        return { ok: true, value: await run(requireLibrary(), ...args) };
      } catch (error) {
        const code = error instanceof LibraryError ? error.code : "write-failed";
        return { ok: false, code, message: (error as Error).message };
      }
    });
  // The search index reads again whatever an operation touched.
  const touched = async <T>(value: T, ...paths: string[]) => {
    await changedHere(paths);
    return value;
  };
  const relocated = (from: string, moved: Relocation) => touched(moved, from, moved.path, ...moved.updated);
  organize(channels.createNote, async (lib, folder) => {
    const path = await lib.createNote(folder ?? "");
    return touched(path, path);
  });
  organize(channels.createFolder, (lib, parent, name) => lib.createFolder(parent ?? "", name ?? ""));
  organize(channels.rename, async (lib, path = "", name = "") => relocated(path, await lib.rename(path, name)));
  organize(channels.move, async (lib, path = "", folder = "") => relocated(path, await lib.move(path, folder)));
  organize(channels.trash, async (lib, path = "") => (await lib.trash(path), touched(null, path)));
  organize(channels.restoreLastDeleted, async (lib) => {
    const path = await lib.restoreLastDeleted();
    return touched(path, path);
  });
  ipcMain.handle(channels.listFolders, () => requireLibrary().listFolders());
  ipcMain.handle(channels.saveCopy, async (_, path: string, text: string): Promise<CopyResult> => {
    try {
      const copy = await requireLibrary().saveCopy(path, text);
      await changedHere([copy]);
      return { ok: true, path: copy };
    } catch (error) {
      const code = error instanceof LibraryError ? error.code : "write-failed";
      return { ok: false, code, message: (error as Error).message };
    }
  });
  ipcMain.handle(channels.confirm, async (_, { message, detail, action }: Confirmation) => {
    const options = { type: "warning" as const, message, detail, buttons: ["取消", action], defaultId: 0, cancelId: 0 };
    const { response } = window ? await dialog.showMessageBox(window, options) : await dialog.showMessageBox(options);
    return response === 1;
  });
  // 空间: the core library does the work; a refusal reaches the page as a result it can show.
  const spaces = () => spaceLibrary(requireLibrary().root, libraryOptions);
  const info = ({ name, icon, scope, hasPage }: Space): SpaceInfo => ({ name, icon, scope, hasPage });
  const space = <T, A extends unknown[]>(channel: string, run: (...args: A) => Promise<T>) =>
    ipcMain.handle(channel, async (_, ...args: unknown[]): Promise<SpaceDone<T>> => {
      try {
        return { ok: true, value: await run(...(args as A)) };
      } catch (error) {
        const code = error instanceof SpaceError || error instanceof LibraryError || error instanceof OperationLogError ? error.code : "write-failed";
        return { ok: false, code, message: (error as Error).message };
      }
    });
  const copyPrompt = async (chosen: Space) => clipboard.writeText(await spaces().prompt(chosen));
  ipcMain.handle(channels.listSpaces, async () => (await spaces().spaces()).map(info));
  space(channels.createSpace, async (draft: SpaceDraft) => {
    const created = await spaces().create(draft);
    await copyPrompt(created);
    return info(created);
  });
  // A homepage's own storage goes with its space when renamed, and a deleted space's is let go.
  space(channels.updateSpace, async (name: string, draft: SpaceDraft) => {
    const updated = await spaces().update(name, draft);
    if (updated.name !== name) {
      pages.close(name);
      await homepageStorage.renamed(requireLibrary().root, name, updated.name);
    }
    return info(updated);
  });
  space(channels.deleteSpace, async (name: string) => {
    await spaces().delete(name);
    pages.close(name);
    await homepageStorage.deleted(requireLibrary().root, name);
    return null;
  });
  space(channels.reorderSpaces, async (names: string[]) => (await spaces().reorder(names), null));
  space(channels.copySpacePrompt, async (name: string) => (await copyPrompt(await spaces().space(name)), null));
  space(channels.revealSpaceSource, async (name: string) => {
    const { path } = await spaces().space(name);
    shell.showItemInFolder(join(requireLibrary().root, ...path.split("/")));
    return null;
  });
  // 空间主页 and its operation log.
  space(channels.spaceNotes, async (name: string): Promise<SpaceNote[]> => {
    const notes = await notesInScope(requireLibrary().root, (await spaces().space(name)).scope);
    return notes.map((path) => ({ path, title: path.split("/").pop()!.replace(/\.md$/i, "") }));
  });
  ipcMain.on(channels.showSpacePage, (_, name: string, bounds: Rectangle) => void pages.show(name, bounds).catch(() => pages.hide()));
  ipcMain.on(channels.hideSpacePage, () => pages.hide());
  const log = () => {
    const { root } = requireLibrary();
    return operationLog(root, { ...libraryOptions, turns: snapshots.library(root) });
  };
  space(channels.operationLog, async (): Promise<LogItem[]> =>
    (await log().entries()).map((entry) => ({
      id: entry.id,
      date: entry.date,
      space: entry.space,
      summary: entrySummary(entry),
      changes: entryChanges(entry),
      undone: entry.undone,
    })),
  );
  space(channels.undoOperation, async (id: string) => (await log().undo(id), null));
  space(channels.copySpaceError, async (name: string, problem: SpacePageProblem) => {
    const lib = spaces();
    clipboard.writeText(spaceErrorReport({ space: name, file: join(lib.folder, `${name}.html`), guide: lib.guidePath, error: problem }));
    return null;
  });
  ipcMain.on(channels.prepareSnapshots, () => {
    void (library && snapshots.library(library.root).baseline().catch(() => undefined));
    // The login shell is asked for its PATH ahead of the first turn too.
    void shellPath();
  });
  ipcMain.handle(channels.snapshotUsage, () => snapshots.usage());
  ipcMain.handle(channels.clearSnapshots, () => snapshots.clear());
  ipcMain.handle(channels.detectAgents, async () => detectAgents({ path: await agentSearchPath(), pathext: process.env.PATHEXT }));
  ipcMain.handle(channels.startTurn, (event, request: TurnStart) => startTurn(event.sender, request));
  ipcMain.on(channels.stopTurn, (_, id: string) => running.get(id)?.abort());
  ipcMain.handle(channels.search, (_, query: string, options: SearchOptions) => searchIndex().search(query, options));
  ipcMain.on(channels.closeChecked, (_, check: CloseCheck) => void finishClose(closeCheck, check));
  ipcMain.on(channels.preferences, (event) => (event.returnValue = preferences));
  ipcMain.handle(channels.setPreferences, (_, change: unknown) => changePreferences(change));
  ipcMain.on(channels.openLibraryListening, (event) => {
    if (!openLibraryPending) return;
    openLibraryPending = false;
    event.sender.send(channels.openLibraryRequest);
  });
}

/** Closes (or quits) once the page has answered; unsaved input is only dropped if the user says so. */
async function finishClose(id: number | null, check: CloseCheck) {
  const win = window;
  if (!win || id === null || id !== closeCheck) return;
  closeCheck = null;
  if (!check.saved) {
    const { response } = await dialog.showMessageBox(win, {
      type: "warning",
      message: "笔记还没有保存",
      detail: `${check.message}\n关闭后，这些输入会丢失。`,
      buttons: ["返回", "不保存，直接关闭"],
      defaultId: 0,
      cancelId: 0,
    });
    if (response === 0) {
      quitting = false;
      return;
    }
  }
  // On macOS the app stays when its window closes. A window whose notes are all saved is only
  // hidden, so the Dock icon brings it back at once, just as it was (启动性能: reopen in 0.3 s).
  // Input the user chose to drop goes with a window that really closes.
  if (mac && !quitting && check.saved) {
    win.hide();
    return;
  }
  closeAllowed = true;
  if (quitting) app.quit();
  else if (!win.isDestroyed()) win.close();
}

/** The window, brought forward; false when there is none to bring. */
function reveal(): boolean {
  if (!window || window.isDestroyed()) return false;
  const hidden = !window.isVisible();
  window.show();
  if (hidden) window.webContents.send(channels.shownAgain);
  return true;
}

function buildMenu() {
  const openLibraryItem: MenuItemConstructorOptions = {
    label: "打开笔记库…",
    accelerator: "CmdOrCtrl+O",
    // The page saves the open note first, then asks for the folder like its own switch button.
    click: () => {
      if (reveal()) window?.webContents.send(channels.openLibraryRequest);
      else {
        openLibraryPending = true;
        createWindow();
      }
    },
  };
  const sourceViewToggle: MenuItemConstructorOptions = {
    id: sourceViewItem,
    label: "Markdown 源码",
    type: "checkbox",
    accelerator: "CmdOrCtrl+Shift+M",
    // The page handles the shortcut itself, so it works however the menu is shown; the menu only shows it.
    registerAccelerator: false,
    click: (item) => window?.webContents.send(channels.sourceViewRequest, item.checked),
  };
  // The page knows the current folder, so it does the creating.
  const newNoteItem: MenuItemConstructorOptions = {
    id: "new-note",
    label: "新建笔记",
    accelerator: "CmdOrCtrl+N",
    click: () => reveal() && window?.webContents.send(channels.newNoteRequest),
  };
  // The page handles ⌘, / Ctrl+, itself (the welcome page opens the panel too); the menu only shows it.
  const settingsItem: MenuItemConstructorOptions = {
    label: "设置…",
    accelerator: "CmdOrCtrl+,",
    registerAccelerator: false,
    click: () => window?.webContents.send(channels.settingsRequest),
  };
  const appMenu: MenuItemConstructorOptions = {
    role: "appMenu",
    submenu: [
      { role: "about" },
      { type: "separator" },
      settingsItem,
      { type: "separator" },
      { role: "services" },
      { type: "separator" },
      { role: "hide" },
      { role: "hideOthers" },
      { role: "unhide" },
      { type: "separator" },
      { role: "quit" },
    ],
  };
  const fileItems: MenuItemConstructorOptions[] = [newNoteItem, { type: "separator" }, openLibraryItem, { type: "separator" }];
  const template: MenuItemConstructorOptions[] = [
    ...(mac ? [appMenu] : []),
    {
      label: "文件",
      submenu: mac ? [...fileItems, { role: "close" }] : [...fileItems, settingsItem, { type: "separator" }, { role: "quit" }],
    },
    { role: "editMenu" },
    { label: "笔记", submenu: [sourceViewToggle] },
    { role: "viewMenu" },
    { role: "windowMenu" },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  const win = (window = new BrowserWindow({
    width: 1200,
    height: 780,
    minWidth: 760,
    minHeight: 480,
    // Shown once the first frame is ready, over the window's own material or color: no white flash.
    show: false,
    ...materialWindowOptions(material, nativeTheme.shouldUseDarkColors),
    ...(mac ? { titleBarStyle: "hiddenInset" as const, trafficLightPosition: { x: 18, y: 18 } } : {}),
    webPreferences: {
      preload: join(__dirname, "../preload/index.js"),
      sandbox: true,
      contextIsolation: true,
      additionalArguments: appearanceArguments(systemAppearance()),
    },
  }));
  // The window appears once its page shows where the user left off (or the welcome page): never
  // blank, never a spinner. A page that is slow to say so is shown anyway once it has painted.
  const pageShown = new Promise<void>((resolve) => {
    const listener = (event: IpcMainEvent) => {
      if (event.sender !== win.webContents) return;
      ipcMain.off(channels.pageShown, listener);
      resolve();
    };
    ipcMain.on(channels.pageShown, listener);
    win.once("closed", () => ipcMain.off(channels.pageShown, listener));
  });
  let shownOnce = false;
  const showFirst = () => {
    if (shownOnce || win.isDestroyed()) return;
    shownOnce = true;
    win.show();
  };
  void pageShown.then(showFirst);
  win.once("ready-to-show", () => setTimeout(showFirst, showFallback));
  // Anything that reads or watches the whole library (the search index, the file watcher) waits
  // until then too, so it never competes with the first note for the disk.
  const settled = Promise.race([pageShown, new Promise<void>((resolve) => setTimeout(resolve, backgroundWorkFallback))]);
  void Promise.all([launch, settled]).then(startBackgroundWork);
  closeAllowed = false;
  // The page saves what is still unsaved before the window goes, on close and on quit alike.
  window.on("close", (event) => {
    if (closeAllowed || !window || window.webContents.isCrashed()) return;
    event.preventDefault();
    if (closeCheck !== null) return;
    const id = (closeCheck = ++closeChecks);
    window.webContents.send(channels.beforeClose);
    // A page that never answers (still loading, or hung) must not keep the window open for good.
    const silent: CloseCheck = { saved: false, message: "页面没有响应，无法确认笔记是否已保存。" };
    setTimeout(() => void finishClose(id, silent), closeCheckTimeout);
  });
  window.on("closed", () => {
    pages.closeAll();
    window = null;
  });
  // The page only ever shows the app itself.
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event) => event.preventDefault());

  if (process.env.ELECTRON_RENDERER_URL) void window.loadURL(process.env.ELECTRON_RENDERER_URL);
  else void window.loadFile(join(__dirname, "../renderer/index.html"));
}

/** 强调色 follows the system while the app runs. */
function followSystemAccent() {
  const changed = () => {
    if (window && !window.isDestroyed()) window.webContents.send(channels.systemAccentChanged, systemAppearance().accent);
    pages.settingsChanged();
  };
  systemPreferences.on("accent-color-changed", changed);
  if (mac) systemPreferences.subscribeNotification("AppleColorPreferencesChangedNotification", changed);
}

void app.whenReady().then(async () => {
  registerIpc();
  buildMenu();
  followSystemAccent();
  // The first frame is drawn in the chosen light or dark.
  await preferencesReady;
  applyPreferences();
  createWindow();
  app.on("activate", () => {
    if (!reveal()) createWindow();
  });
});

app.on("before-quit", () => (quitting = true));
// An agent still running stops with the app.
app.on("will-quit", () => running.forEach((turn) => turn.abort()));

app.on("window-all-closed", () => {
  if (!mac) app.quit();
});
