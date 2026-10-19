import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme, shell } from "electron";
import type { MenuItemConstructorOptions, OpenDialogOptions } from "electron";
import { basename, join } from "node:path";
import {
  createSearchIndex,
  LibraryError,
  openLibrary,
  type Library,
  type OrganizeOptions,
  type Relocation,
  type SearchIndex,
  type SearchOptions,
} from "../core";
import { channels, type CloseCheck, type LaunchState, type LibraryInfo, type Organized, type SaveResult } from "../shared/api";
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

const libraryInfo = (lib: Library): LibraryInfo => ({ root: lib.root, name: basename(lib.root) });

// Deleting goes to the system trash. Looked up on each call, so tests can stand in for the trash.
const libraryOptions: OrganizeOptions = { trash: (path) => shell.trashItem(path) };

// Starts while the window loads, so the remembered library is ready by the time the page asks.
const launch: Promise<LaunchState> = (async () => {
  const { libraryPath } = await settings.read();
  if (!libraryPath) return { kind: "welcome" };
  library = await openLibrary(libraryPath, libraryOptions).catch(() => null);
  return library ? { kind: "open", library: libraryInfo(library) } : { kind: "welcome", missing: libraryPath };
})();

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
  await settings.update({ libraryPath: path });
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
  ipcMain.handle(channels.readFolder, (_, path: string) => requireLibrary().readFolder(path));
  ipcMain.handle(channels.readNote, (_, path: string) => requireLibrary().readNote(path));
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
  closeAllowed = true;
  if (quitting) app.quit();
  else if (!win.isDestroyed()) win.close();
}

function buildMenu() {
  const openLibraryItem: MenuItemConstructorOptions = {
    label: "打开笔记库…",
    accelerator: "CmdOrCtrl+O",
    // The page saves the open note first, then asks for the folder like its own switch button.
    click: () => {
      if (window) window.webContents.send(channels.openLibraryRequest);
      else {
        openLibraryPending = true;
        createWindow();
      }
    },
  };
  // The page knows the current folder, so it does the creating.
  const newNoteItem: MenuItemConstructorOptions = {
    id: "new-note",
    label: "新建笔记",
    accelerator: "CmdOrCtrl+N",
    click: () => window?.webContents.send(channels.newNoteRequest),
  };
  const template: MenuItemConstructorOptions[] = [
    ...(mac ? [{ role: "appMenu" } as const] : []),
    {
      label: "文件",
      submenu: [newNoteItem, { type: "separator" }, openLibraryItem, { type: "separator" }, mac ? { role: "close" } : { role: "quit" }],
    },
    { role: "editMenu" },
    { role: "viewMenu" },
    { role: "windowMenu" },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  window = new BrowserWindow({
    width: 1200,
    height: 780,
    minWidth: 760,
    minHeight: 480,
    // Shown once the first frame is ready, over the window's own color: no white flash on launch.
    // The color is --win-fallback from the design system, needed here before any CSS has loaded.
    show: false,
    backgroundColor: nativeTheme.shouldUseDarkColors ? "#1e1e22" : "#f2f1f5",
    ...(mac ? { titleBarStyle: "hiddenInset" as const, trafficLightPosition: { x: 18, y: 18 } } : {}),
    webPreferences: { preload: join(__dirname, "../preload/index.js"), sandbox: true, contextIsolation: true },
  });
  window.once("ready-to-show", () => {
    window?.show();
    void launch.then(indexInBackground);
  });
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
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("before-quit", () => (quitting = true));

app.on("window-all-closed", () => {
  if (!mac) app.quit();
});
