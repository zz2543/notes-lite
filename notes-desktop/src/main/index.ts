import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme } from "electron";
import type { MenuItemConstructorOptions, OpenDialogOptions } from "electron";
import { basename, join } from "node:path";
import { LibraryError, openLibrary, type Library } from "../core";
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
let quitting = false;

const libraryInfo = (lib: Library): LibraryInfo => ({ root: lib.root, name: basename(lib.root) });

// Starts while the window loads, so the remembered library is ready by the time the page asks.
const launch: Promise<LaunchState> = (async () => {
  const { libraryPath } = await settings.read();
  if (!libraryPath) return { kind: "welcome" };
  library = await openLibrary(libraryPath).catch(() => null);
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
      const conflict = error instanceof LibraryError && error.code === "conflict";
      return { ok: false, conflict, message: (error as Error).message };
    }
  });
  ipcMain.on(channels.closeChecked, async (_, check: CloseCheck) => {
    if (!window) return;
    if (!check.saved) {
      const { response } = await dialog.showMessageBox(window, {
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
    else window.close();
  });
}

function buildMenu() {
  const openLibraryItem: MenuItemConstructorOptions = {
    label: "打开笔记库…",
    accelerator: "CmdOrCtrl+O",
    // The page saves the open note first, then asks for the folder like its own switch button.
    click: () => {
      if (!window) createWindow();
      window?.webContents.send(channels.openLibraryRequest);
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
    window.webContents.send(channels.beforeClose);
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
