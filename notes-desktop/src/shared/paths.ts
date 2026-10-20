// Rules about library paths ("/"-separated, library-relative) that main, the core library and the
// page all follow. No Node here.

/** Inside a dot-folder (the app's `.notes/`, `.git/`…) or a dot-file itself: never shown, searched or reported. */
export const isHidden = (path: string) => path.split("/").some((part) => part.startsWith("."));

/** A note's title: its file name without `.md`. */
export const noteTitle = (path: string) => path.slice(path.lastIndexOf("/") + 1).replace(/\.md$/i, "");
