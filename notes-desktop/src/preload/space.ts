// The space homepage's preload: its only way out of the sandbox. It runs in the homepage's main
// frame alone (embedded frames get nothing) and carries `space` requests to main untouched.
import { contextBridge, ipcRenderer } from "electron";
import { spacePageChannels } from "../shared/spacePage";

contextBridge.exposeInMainWorld("__notesSpace", {
  call: (method: string, args: unknown[]) => ipcRenderer.invoke(spacePageChannels.request, { method, args }),
  /** Paths in the scope that changed; main sends them once refreshing arrives (ticket 21). */
  onChange: (listener: (paths: string[]) => void) => {
    ipcRenderer.on(spacePageChannels.changed, (_, paths: string[]) => listener(paths));
  },
});

// 排版, 强调色 and 动效 changed in the app: the page follows without reloading. Only the style element
// the app put in the page is rewritten; the page's own scripts never see this.
ipcRenderer.on(spacePageChannels.settings, (_, css: string) => {
  const style = document.getElementById("space-settings");
  if (style) style.textContent = css;
});
