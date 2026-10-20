import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme, shell, systemPreferences } from "electron";
import type { IpcMainEvent, MenuItemConstructorOptions, OpenDialogOptions } from "electron";
import { stat } from "node:fs/promises";
import { release } from "node:os";
import { basename, join } from "node:path";
import {
  createSearchIndex,
  LibraryError,
  openLibrary,
  watchLibrary,
  type Library,
  type LibraryWatcher,
  type OrganizeOptions,
  type Relocation,
  type SearchIndex,
  type SearchOptions,
} from "../core";
import {
  channels,
  type CloseCheck,
  type Confirmation,
  type CopyResult,
  type LaunchState,
  type LibraryInfo,
  type Organized,
  type Place,
  type SaveResult,
} from "../shared/api";
import { appearanceArguments, type Appearance } from "../shared/appearance";
import { materialWindowOptions, windowMaterial } from "./material";
import { settingsStore } from "./settings";

// A separate profile, for tests and for running beside an installed copy.
if (process.env.NOTES_DESKTOP_USER_DATA) app.setPath("userData", process.env.NOTES_DESKTOP_USER_DATA);

const settings = settingsStore(app.getPath("userData"));
const mac = process.platform === "darwin";
let library: Library | null = null;
let window: BrowserWindow | null = null;
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

const libraryInfo = (lib: Library): LibraryInfo => ({ root: lib.root, name: basename(lib.root) });

// Deleting goes to the system trash. Looked up on each call, so tests can stand in for the trash.
const libraryOptions: OrganizeOptions = { trash: (path) => shell.trashItem(path) };

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
    });
  } catch {
    // A folder the system will not watch still opens; it just won't follow changes made elsewhere.
    watcher = null;
  }
}

// Starts while the window loads, so the remembered library is ready by the time the page asks.
const launch: Promise<LaunchState> = (async () => {
  const { libraryPath, place } = await settings.read();
  if (!libraryPath) return { kind: "welcome" };
  library = await openLibrary(libraryPath, libraryOptions).catch(() => null);
  if (!library) return { kind: "welcome", missing: libraryPath };
  const found = place && (await stillThere(library, place));
  if (found) readAhead(library, found);
  return { kind: "open", library: libraryInfo(library), place: found };
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
  readsAhead.clear();
  watch(library);
  // A new library starts at its root; the place remembered belonged to the old one.
  await settings.update({ libraryPath: path, place: undefined });
  return libraryInfo(library);
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
  if (!library) return;
  if (watched !== library) watch(library);
  indexInBackground();
}

/** A note the app saved (or otherwise changed) is searched as it is now. */
function noteChanged(path: string) {
  if (index && index.library === library) void index.index.update(path);
}

function registerIpc() {
  ipcMain.handle(channels.launchState, () => launch);
  ipcMain.handle(channels.chooseLibrary, async () => {
    const chosen = await chooseLibrary();
    indexInBackground();
    return chosen;
  });
  ipcMain.on(channels.rememberPlace, (_, place: Place) => void settings.update({ place }).catch(() => {}));
  ipcMain.handle(channels.readFolder, (_, path: string) => readOnce(`folder:${path}`, () => requireLibrary().readFolder(path)));
  ipcMain.handle(channels.readNote, (_, path: string) => readOnce(`note:${path}`, () => requireLibrary().readNote(path)));
  // Errors cross IPC as plain messages, so a save answers with a result the page can act on.
  ipcMain.handle(channels.saveNote, async (_, path: string, text: string, expected: string): Promise<SaveResult> => {
    try {
      await requireLibrary().saveNote(path, text, expected);
      noteChanged(path);
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
  const touched = <T>(value: T, ...paths: string[]) => {
    for (const path of paths) noteChanged(path);
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
      return { ok: true, path: await requireLibrary().saveCopy(path, text) };
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
  ipcMain.handle(channels.search, (_, query: string, options: SearchOptions) => searchIndex().search(query, options));
  ipcMain.on(channels.closeChecked, (_, check: CloseCheck) => void finishClose(closeCheck, check));
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
  const template: MenuItemConstructorOptions[] = [
    ...(mac ? [{ role: "appMenu" } as const] : []),
    {
      label: "文件",
      submenu: [newNoteItem, { type: "separator" }, openLibraryItem, { type: "separator" }, mac ? { role: "close" } : { role: "quit" }],
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
  window.on("closed", () => (window = null));
  // The page only ever shows the app itself.
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event) => event.preventDefault());

  if (process.env.ELECTRON_RENDERER_URL) void window.loadURL(process.env.ELECTRON_RENDERER_URL);
  else void window.loadFile(join(__dirname, "../renderer/index.html"));
}

void app.whenReady().then(() => {
  registerIpc();
  buildMenu();
  createWindow();
  app.on("activate", () => {
    if (!reveal()) createWindow();
  });
});

app.on("before-quit", () => (quitting = true));

app.on("window-all-closed", () => {
  if (!mac) app.quit();
});
