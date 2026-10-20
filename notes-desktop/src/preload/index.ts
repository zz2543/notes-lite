import { contextBridge, ipcRenderer } from "electron";
import { channels, type CloseCheck, type NotesApi } from "../shared/api";
import { readAppearance } from "../shared/appearance";

const api: NotesApi = {
  appearance: readAppearance(process.argv),
  launchState: () => ipcRenderer.invoke(channels.launchState),
  chooseLibrary: () => ipcRenderer.invoke(channels.chooseLibrary),
  rememberPlace: (place) => ipcRenderer.send(channels.rememberPlace, place),
  shown: () => ipcRenderer.send(channels.pageShown),
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
  onSourceViewRequest: (listener) => {
    const handler = (_: unknown, showSource: boolean) => listener(showSource);
    ipcRenderer.on(channels.sourceViewRequest, handler);
    return () => ipcRenderer.off(channels.sourceViewRequest, handler);
  },
  sourceViewChanged: (showSource) => ipcRenderer.send(channels.sourceViewChanged, showSource),
  onShownAgain: (listener) => {
    const handler = () => listener();
    ipcRenderer.on(channels.shownAgain, handler);
    return () => ipcRenderer.off(channels.shownAgain, handler);
  },
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
  onLibraryChanged: (listener) => {
    const handler = (_: unknown, paths: string[]) => listener(paths);
    ipcRenderer.on(channels.libraryChanged, handler);
    return () => ipcRenderer.off(channels.libraryChanged, handler);
  },
  saveCopy: (path, text) => ipcRenderer.invoke(channels.saveCopy, path, text),
  confirm: (question) => ipcRenderer.invoke(channels.confirm, question),
  listSpaces: () => ipcRenderer.invoke(channels.listSpaces),
  createSpace: (draft) => ipcRenderer.invoke(channels.createSpace, draft),
  updateSpace: (name, draft) => ipcRenderer.invoke(channels.updateSpace, name, draft),
  deleteSpace: (name) => ipcRenderer.invoke(channels.deleteSpace, name),
  reorderSpaces: (names) => ipcRenderer.invoke(channels.reorderSpaces, names),
  copySpacePrompt: (name) => ipcRenderer.invoke(channels.copySpacePrompt, name),
};

contextBridge.exposeInMainWorld("notes", api);
