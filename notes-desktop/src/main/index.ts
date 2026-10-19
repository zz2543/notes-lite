import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme } from "electron";
import type { MenuItemConstructorOptions, OpenDialogOptions } from "electron";
import { basename, join } from "node:path";
import { LibraryError, openLibrary, watchLibrary, type Library, type LibraryWatcher } from "../core";
import { channels, type CloseCheck, type LaunchState, type LibraryInfo, type SaveResult } from "../shared/api";
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

let watcher: LibraryWatcher | null = null;

/** Passes every change in the open library, made here or by another program, on to the page. */
function watch(lib: Library) {
  watcher?.close();
  try {
    watcher = watchLibrary(lib.root, (paths) => {
      if (window && !window.isDestroyed()) window.webContents.send(channels.libraryChanged, paths);
    });
  } catch {
    // A folder the system will not watch still opens; it just won't follow changes made elsewhere.
    watcher = null;
  }
}

// Starts while the window loads, so the remembered library is ready by the time the page asks.
const launch: Promise<LaunchState> = (async () => {
  const { libraryPath } = await settings.read();
  if (!libraryPath) return { kind: "welcome" };
  library = await openLibrary(libraryPath).catch(() => null);
  if (library) watch(library);
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
  library = await openLibrary(path);
  watch(library);
  await settings.update({ libraryPath: path });
  return libraryInfo(library);
}

function requireLibrary(): Library {
  if (!library) throw new Error("请先打开笔记库。");
  return library;
}

function registerIpc() {
  ipcMain.handle(channels.launchState, () => launch);
  ipcMain.handle(channels.chooseLibrary, () => chooseLibrary());
  ipcMain.handle(channels.readFolder, (_, path: string) => requireLibrary().readFolder(path));
  ipcMain.handle(channels.readNote, (_, path: string) => requireLibrary().readNote(path));
  // Errors cross IPC as plain messages, so a save answers with a result the page can act on.
  ipcMain.handle(channels.saveNote, async (_, path: string, text: string, expected: string): Promise<SaveResult> => {
    try {
      await requireLibrary().saveNote(path, text, expected);
      return { ok: true };
    } catch (error) {
      const code = error instanceof LibraryError ? error.code : "write-failed";
      return { ok: false, code, message: (error as Error).message };
    }
  });
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
  const template: MenuItemConstructorOptions[] = [
    ...(mac ? [{ role: "appMenu" } as const] : []),
    { label: "文件", submenu: [openLibraryItem, { type: "separator" }, mac ? { role: "close" } : { role: "quit" }] },
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
  window.once("ready-to-show", () => window?.show());
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
