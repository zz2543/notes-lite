import { watch } from "node:fs";

export interface LibraryWatcher {
  close(): void;
}

/** How long changes are gathered after the first one before they are reported together. */
const gatherTime = 80;

// saveNote writes ".<name>.<pid>.saving" beside the note and swaps it in; only the swap is news.
const saveTemp = /(^|\/)\.[^/]+\.\d+\.saving$/;

/**
 * Follows changes made anywhere in the library, by any program (the app's own saves included),
 * and reports them as library-relative, "/"-separated paths, hidden ones too. A burst of changes,
 * like a sync tool's, is reported once, each path named once.
 */
export function watchLibrary(root: string, onChange: (paths: string[]) => void): LibraryWatcher {
  let gathered = new Set<string>();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const report = () => {
    timer = undefined;
    const paths = [...gathered];
    gathered = new Set();
    onChange(paths);
  };
  const relative = (name: string) => (process.platform === "win32" ? name.replaceAll("\\", "/") : name).replace(/^\/+/, "");
  const gather = (path: string) => {
    if (saveTemp.test(path)) return;
    gathered.add(path);
    timer ??= setTimeout(report, gatherTime);
  };
  // "" stands for anything at all, when the system cannot say which path changed.
  const watcher = watch(root, { recursive: true }, (_event, name) => gather(name ? relative(name) : ""));
  // Windows reports a library folder that was removed or became unreadable as an error; nothing more
  // will be heard, and everything may have changed.
  watcher.on("error", () => {
    watcher.close();
    gather("");
  });
  return {
    close: () => {
      watcher.close();
      clearTimeout(timer);
    },
  };
}
