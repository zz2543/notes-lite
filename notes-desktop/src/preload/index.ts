import { contextBridge, ipcRenderer } from "electron";
import { channels, type CloseCheck, type NotesApi, type SpacePageEvent } from "../shared/api";
import type { Preferences } from "../shared/preferences";
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
  readSummaries: (path) => ipcRenderer.invoke(channels.readSummaries, path),
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
  followLink: (note, link) => ipcRenderer.invoke(channels.followLink, note, link),
  openLinkedFile: (note, link) => ipcRenderer.invoke(channels.openLinkedFile, note, link),
  readImage: (note, link) => ipcRenderer.invoke(channels.readImage, note, link),
  importAttachments: (note, files) => ipcRenderer.invoke(channels.importAttachments, note, files),
  chooseAttachments: (note) => ipcRenderer.invoke(channels.chooseAttachments, note),
  chooseAttachmentFolder: () => ipcRenderer.invoke(channels.chooseAttachmentFolder),
  onImportAttachmentsRequest: (listener) => {
    const handler = () => listener();
    ipcRenderer.on(channels.importAttachmentsRequest, handler);
    return () => ipcRenderer.off(channels.importAttachmentsRequest, handler);
  },
  openExternal: (url) => ipcRenderer.invoke(channels.openExternal, url),
  onOperationLogRequest: (listener) => {
    const handler = () => listener();
    ipcRenderer.on(channels.operationLogRequest, handler);
    return () => ipcRenderer.off(channels.operationLogRequest, handler);
  },
  openSettings: () => ipcRenderer.send(channels.openSettings),
  openNoteText: () => ipcRenderer.invoke(channels.openNoteText),
  provideOpenNoteText: (provider) => {
    const handler = (_: unknown, id: number) => ipcRenderer.send(channels.openNoteTextReply, id, provider());
    ipcRenderer.on(channels.openNoteTextRequest, handler);
    return () => ipcRenderer.off(channels.openNoteTextRequest, handler);
  },
  // Asked once, synchronously, before any script runs: the answer is already in memory in the main process.
  preferences: ipcRenderer.sendSync(channels.preferences),
  setPreferences: (change) => ipcRenderer.invoke(channels.setPreferences, change),
  onPreferencesChanged: (listener) => {
    const handler = (_: unknown, preferences: Preferences) => listener(preferences);
    ipcRenderer.on(channels.preferencesChanged, handler);
    return () => ipcRenderer.off(channels.preferencesChanged, handler);
  },
  onSystemAccentChanged: (listener) => {
    const handler = (_: unknown, accent: string | null) => listener(accent);
    ipcRenderer.on(channels.systemAccentChanged, handler);
    return () => ipcRenderer.off(channels.systemAccentChanged, handler);
  },
  listSpaces: () => ipcRenderer.invoke(channels.listSpaces),
  createSpace: (draft) => ipcRenderer.invoke(channels.createSpace, draft),
  createExampleSpace: () => ipcRenderer.invoke(channels.createExampleSpace),
  updateSpace: (name, draft) => ipcRenderer.invoke(channels.updateSpace, name, draft),
  deleteSpace: (name) => ipcRenderer.invoke(channels.deleteSpace, name),
  reorderSpaces: (names) => ipcRenderer.invoke(channels.reorderSpaces, names),
  copySpacePrompt: (name) => ipcRenderer.invoke(channels.copySpacePrompt, name),
  spaceNetwork: (name) => ipcRenderer.invoke(channels.spaceNetwork, name),
  setSpaceNetwork: (name, allowed) => ipcRenderer.invoke(channels.setSpaceNetwork, name, allowed),
  spacePrompt: (name) => ipcRenderer.invoke(channels.spacePrompt, name),
  revealSpaceSource: (name) => ipcRenderer.invoke(channels.revealSpaceSource, name),
  spaceNotes: (name) => ipcRenderer.invoke(channels.spaceNotes, name),
  showSpacePage: (name, bounds) => ipcRenderer.send(channels.showSpacePage, name, bounds),
  hideSpacePage: () => ipcRenderer.send(channels.hideSpacePage),
  operationLog: () => ipcRenderer.invoke(channels.operationLog),
  undoOperation: (id) => ipcRenderer.invoke(channels.undoOperation, id),
  onSpacePageEvent: (listener) => {
    const handler = (_: unknown, event: SpacePageEvent) => listener(event);
    ipcRenderer.on(channels.spacePageEvent, handler);
    return () => ipcRenderer.off(channels.spacePageEvent, handler);
  },
  copySpaceError: (name, problem) => ipcRenderer.invoke(channels.copySpaceError, name, problem),
  detectAgents: () => ipcRenderer.invoke(channels.detectAgents),
  agentModels: (agent) => ipcRenderer.invoke(channels.agentModels, agent),
  prepareSnapshots: () => ipcRenderer.send(channels.prepareSnapshots),
  snapshotUsage: () => ipcRenderer.invoke(channels.snapshotUsage),
  clearSnapshots: () => ipcRenderer.invoke(channels.clearSnapshots),
  startTurn: (request) => ipcRenderer.invoke(channels.startTurn, request),
  stopTurn: (conversation) => ipcRenderer.send(channels.stopTurn, conversation),
  answerApproval: (conversation, approval, allowed) => ipcRenderer.send(channels.answerApproval, conversation, approval, allowed),
  reviewTurn: (request) => ipcRenderer.invoke(channels.reviewTurn, request),
  turnDiff: (turn, path) => ipcRenderer.invoke(channels.turnDiff, turn, path),
  conversations: () => ipcRenderer.invoke(channels.conversations),
  openConversation: (conversation) => ipcRenderer.invoke(channels.openConversation, conversation),
  onTurnEvent: (listener) => {
    const handler = (_: unknown, conversation: string, event: Parameters<typeof listener>[1]) => listener(conversation, event);
    ipcRenderer.on(channels.turnEvent, handler);
    return () => ipcRenderer.off(channels.turnEvent, handler);
  },
};

contextBridge.exposeInMainWorld("notes", api);
