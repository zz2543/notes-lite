// The space homepage's preload: its only way out of the sandbox. It runs in the homepage's main
// frame alone (embedded frames get nothing) and carries `lb` requests to main untouched.
import { contextBridge, ipcRenderer } from "electron";
import { spacePageChannels } from "../shared/spacePage";

contextBridge.exposeInMainWorld("__notesSpace", {
  call: (method: string, args: unknown[]) => ipcRenderer.invoke(spacePageChannels.request, { method, args }),
  /** Paths in the scope that changed; main sends them once refreshing arrives (ticket 21). */
  onChange: (listener: (paths: string[]) => void) => {
    ipcRenderer.on(spacePageChannels.changed, (_, paths: string[]) => listener(paths));
  },
});
