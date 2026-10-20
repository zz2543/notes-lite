import { useEffect, useRef, useState } from "react";
import { isHidden } from "../../shared/paths";

// Changes in the open library, made by this app or any other program, as the watcher reports them.

type Listener = (paths: string[]) => void;

const listeners = new Set<Listener>();
let listening = false;

const visible = (path: string) => !isHidden(path);

/**
 * Calls `listener` with each batch of changed paths the folder tree, the list or the open note can
 * show (the app's own hidden folders are left out). "" means anything may have changed.
 */
export function onLibraryChange(listener: Listener): () => void {
  if (!listening) {
    listening = true;
    window.notes.onLibraryChanged((paths) => {
      const shown = paths.filter(visible);
      if (shown.length > 0) for (const each of listeners) each(shown);
    });
  }
  listeners.add(listener);
  return () => void listeners.delete(listener);
}

const parentOf = (path: string) => path.slice(0, Math.max(0, path.lastIndexOf("/")));

/** Whether `path` is `folder` itself or lies anywhere inside it ("" being the whole library). */
export const isWithin = (path: string, folder: string) => folder === "" || path === folder || path.startsWith(`${folder}/`);

/**
 * Whether a change at `changed` can alter what `folder` lists: its direct entries, whether its
 * subfolders hold folders of their own, or the folder itself.
 */
export const touchesFolder = (folder: string, changed: string) =>
  isWithin(folder, changed) || parentOf(changed) === folder || (changed.includes("/") && parentOf(parentOf(changed)) === folder);

/** Counts the changes that `touches` says concern `path`, so a reader can read it again. */
export function useChangeCount(path: string | null, touches: (path: string, changed: string) => boolean): number {
  const [count, setCount] = useState(0);
  useEffect(() => {
    if (path === null) return;
    return onLibraryChange((paths) => {
      if (paths.some((changed) => touches(path, changed))) setCount((n) => n + 1);
    });
  }, [path, touches]);
  return count;
}

/** Selects the nearest folder still there when the selected one is moved or deleted elsewhere. */
export function useFolderFallback(folder: string, select: (path: string) => void) {
  const selected = useRef(folder);
  selected.current = folder;
  const latestSelect = useRef(select);
  latestSelect.current = select;
  useEffect(
    () =>
      onLibraryChange(async (paths) => {
        const gone = selected.current;
        if (!paths.some((changed) => isWithin(gone, changed))) return;
        const still = await nearestFolder(gone);
        if (selected.current === gone && still !== gone) latestSelect.current(still);
      }),
    [],
  );
}

async function nearestFolder(path: string): Promise<string> {
  const parts = path.split("/");
  for (let depth = parts.length; depth > 0; depth--) {
    const candidate = parts.slice(0, depth).join("/");
    if (await window.notes.readFolder(candidate).then(() => true, () => false)) return candidate;
  }
  return "";
}
