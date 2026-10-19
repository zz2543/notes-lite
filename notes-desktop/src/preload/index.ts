import { contextBridge, ipcRenderer } from "electron";
import { channels, type LibraryInfo, type NotesApi } from "../shared/api";

const api: NotesApi = {
  launchState: () => ipcRenderer.invoke(channels.launchState),
  chooseLibrary: () => ipcRenderer.invoke(channels.chooseLibrary),
  onLibraryChanged: (listener) => {
    const handler = (_: unknown, library: LibraryInfo) => listener(library);
    ipcRenderer.on(channels.libraryChanged, handler);
    return () => ipcRenderer.off(channels.libraryChanged, handler);
  },
  readFolder: (path) => ipcRenderer.invoke(channels.readFolder, path),
  readNote: (path) => ipcRenderer.invoke(channels.readNote, path),
};

contextBridge.exposeInMainWorld("notes", api);
