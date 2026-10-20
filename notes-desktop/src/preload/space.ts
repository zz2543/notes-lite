// The space homepage's preload: its only way out of the sandbox. It runs in the homepage's main
// frame alone (embedded frames get nothing) and carries `space` requests to main untouched.
import { contextBridge, ipcRenderer } from "electron";
import { spacePageChannels } from "../shared/spacePage";

contextBridge.exposeInMainWorld("__notesSpace", {
  call: (method: string, args: unknown[]) => ipcRenderer.invoke(spacePageChannels.request, { method, args }),
  /** Reports an error for the 错误条; main reads only the fields it knows and trusts none of them. */
  error: (problem: unknown) => ipcRenderer.send(spacePageChannels.error, problem),
  /** Paths in the scope that changed, whoever changed them. */
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
