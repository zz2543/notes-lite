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
  onNewNoteRequest: (listener) => {
    const handler = () => listener();
    ipcRenderer.on(channels.newNoteRequest, handler);
    return () => ipcRenderer.off(channels.newNoteRequest, handler);
  },
  createNote: (folder) => ipcRenderer.invoke(channels.createNote, folder),
  createFolder: (parent, name) => ipcRenderer.invoke(channels.createFolder, parent, name),
  rename: (path, name) => ipcRenderer.invoke(channels.rename, path, name),
  move: (path, folder) => ipcRenderer.invoke(channels.move, path, folder),
  trash: (path) => ipcRenderer.invoke(channels.trash, path),
  restoreLastDeleted: () => ipcRenderer.invoke(channels.restoreLastDeleted),
  listFolders: () => ipcRenderer.invoke(channels.listFolders),
  search: (query, options) => ipcRenderer.invoke(channels.search, query, options),
};

contextBridge.exposeInMainWorld("notes", api);
