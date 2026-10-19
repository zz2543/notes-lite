import { contextBridge, ipcRenderer } from "electron";
import { channels, type CloseCheck, type NotesApi } from "../shared/api";

const api: NotesApi = {
  launchState: () => ipcRenderer.invoke(channels.launchState),
  chooseLibrary: () => ipcRenderer.invoke(channels.chooseLibrary),
  onOpenLibraryRequest: (listener) => {
    const handler = () => listener();
    ipcRenderer.on(channels.openLibraryRequest, handler);
    // A request made before the page was listening (menu used with no window open) is sent now.
    ipcRenderer.send(channels.openLibraryListening);
    return () => ipcRenderer.off(channels.openLibraryRequest, handler);
  },
  readFolder: (path) => ipcRenderer.invoke(channels.readFolder, path),
  readNote: (path) => ipcRenderer.invoke(channels.readNote, path),
  saveNote: (path, text, expected) => ipcRenderer.invoke(channels.saveNote, path, text, expected),
  onBeforeClose: (check) => {
    const handler = async () => {
      const answer: CloseCheck = await check().catch((error: Error) => ({ saved: false, message: error.message }));
      ipcRenderer.send(channels.closeChecked, answer);
    };
    ipcRenderer.on(channels.beforeClose, handler);
    return () => ipcRenderer.off(channels.beforeClose, handler);
  },
  onLibraryChanged: (listener) => {
    const handler = (_: unknown, paths: string[]) => listener(paths);
    ipcRenderer.on(channels.libraryChanged, handler);
    return () => ipcRenderer.off(channels.libraryChanged, handler);
  },
  saveCopy: (path, text) => ipcRenderer.invoke(channels.saveCopy, path, text),
  confirm: (question) => ipcRenderer.invoke(channels.confirm, question),
};

contextBridge.exposeInMainWorld("notes", api);
