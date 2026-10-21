// What the editor asks of the app about links and attachments (ticket 13), apart from the editor's own
// modules so that each of them can ask.
import { Facet } from "@codemirror/state";
import type { Link } from "../../shared/markdown";

/** What the editor asks of the app about links and attachments, for the note it shows. */
export interface LinkHost {
  /** ⌘ / Ctrl-click on a link: open the note, the file or the web page it leads to. */
  follow(link: Link): void;
  /** A double click on an image: open it with the system's app for it. */
  open(link: Link): void;
  /** The image as a data: URL, or why it can't be shown. */
  image(link: Link): Promise<{ ok: true; value: string } | { ok: false; message: string }>;
  /** Imports files into the library; the Markdown for each, or null when it failed (the host says why). */
  importFiles(files: { name: string; data: Uint8Array }[]): Promise<string[] | null>;
}

export const linkHost = Facet.define<LinkHost, LinkHost | null>({ combine: (hosts) => hosts[0] ?? null });

const mac = typeof navigator !== "undefined" && /Mac/.test(navigator.platform);
/** ⌘ on macOS, Ctrl elsewhere: the key that makes a click follow a link rather than place the caret. */
export const followsLink = (event: MouseEvent) => (mac ? event.metaKey : event.ctrlKey) && !event.altKey && !event.shiftKey;

// An image's double click may land on its Markdown, come back above it at the first click: the first
// press is remembered for a moment, so the second still opens the image.
let pressed: { view: object; link: Link; time: number } | null = null;
const doubleClickTime = 500;
/** A press on an image drawn in `view`. */
export function pressImage(view: object, link: Link) {
  pressed = { view, link, time: Date.now() };
}
/** The image pressed in `view` just before, when a second press now makes a double click. */
export function imagePressedBefore(view: object): Link | null {
  return pressed && pressed.view === view && Date.now() - pressed.time < doubleClickTime ? pressed.link : null;
}
