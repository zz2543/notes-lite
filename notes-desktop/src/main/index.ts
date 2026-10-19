import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme } from "electron";
import type { MenuItemConstructorOptions, OpenDialogOptions } from "electron";
import { basename, join } from "node:path";
import { openLibrary, type Library } from "../core";
import { channels, type LibraryInfo } from "../shared/api";
import { settingsStore } from "./settings";

// A separate profile, for tests and for running beside an installed copy.
if (process.env.NOTES_DESKTOP_USER_DATA) app.setPath("userData", process.env.NOTES_DESKTOP_USER_DATA);

const settings = settingsStore(app.getPath("userData"));
const mac = process.platform === "darwin";
let library: Library | null = null;
let window: BrowserWindow | null = null;

const describe = (opened: Library): LibraryInfo => ({ root: opened.root, name: basename(opened.root) });

// Starts while the window loads, so the remembered library is ready by the time the page asks.
const remembered = (async () => {
  const { libraryPath } = await settings.read();
  if (libraryPath) library = await openLibrary(libraryPath).catch(() => null);
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
  return describe(library);
}

function opened(): Library {
  if (!library) throw new Error("请先打开笔记库。");
  return library;
}

function registerIpc() {
  ipcMain.handle(channels.currentLibrary, async () => {
    await remembered;
    return library && describe(library);
  });
  ipcMain.handle(channels.chooseLibrary, () => chooseLibrary());
  ipcMain.handle(channels.readFolder, (_, path: string) => opened().readFolder(path));
  ipcMain.handle(channels.readNote, (_, path: string) => opened().readNote(path));
}

function buildMenu() {
  const openLibraryItem: MenuItemConstructorOptions = {
    label: "打开笔记库…",
    accelerator: "CmdOrCtrl+O",
    click: async () => {
      const next = await chooseLibrary();
      if (next) window?.webContents.send(channels.libraryChanged, next);
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
    title: "notes-desktop",
    // Shown once the first frame is ready, over the window's own color: no white flash on launch.
    show: false,
    backgroundColor: nativeTheme.shouldUseDarkColors ? "#1e1e22" : "#f2f1f5",
    ...(mac ? { titleBarStyle: "hiddenInset" as const, trafficLightPosition: { x: 18, y: 18 } } : {}),
    webPreferences: { preload: join(__dirname, "../preload/index.js"), sandbox: true, contextIsolation: true },
  });
  window.once("ready-to-show", () => window?.show());
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

app.on("window-all-closed", () => {
  if (!mac) app.quit();
});
