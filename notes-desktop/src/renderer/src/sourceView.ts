import { useSyncExternalStore } from "react";

// Whether the editor shows the Markdown source instead of the typeset note. One choice for the whole
// window, kept while notes change (as in the old app); not saved across launches.
let showSource = false;
const listeners = new Set<() => void>();

export function setShowSource(on: boolean) {
  if (on === showSource) return;
  showSource = on;
  window.notes.sourceViewChanged(on);
  for (const listener of listeners) listener();
}

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => void listeners.delete(listener);
};

export const useShowSource = (): boolean => useSyncExternalStore(subscribe, () => showSource);

const mac = /Mac/.test(navigator.platform);

/** ⌘⇧M / Ctrl+Shift+M, and 笔记 › Markdown 源码 in the menu, switch the view. */
export function listenForSourceView(): () => void {
  const onKey = (event: KeyboardEvent) => {
    if (event.isComposing || event.code !== "KeyM" || !event.shiftKey || event.altKey) return;
    if (mac ? !event.metaKey || event.ctrlKey : !event.ctrlKey || event.metaKey) return;
    event.preventDefault();
    setShowSource(!showSource);
  };
  window.addEventListener("keydown", onKey, true);
  const offMenu = window.notes.onSourceViewRequest(setShowSource);
  window.notes.sourceViewChanged(showSource);
  return () => {
    window.removeEventListener("keydown", onKey, true);
    offMenu();
  };
}
