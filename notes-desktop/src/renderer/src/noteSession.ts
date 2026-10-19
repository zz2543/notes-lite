import type { CloseCheck, SaveResult } from "../../shared/api";
import { errorText } from "./ipc";

export type SaveStatus = "saved" | "pending" | "saving" | "failed" | "conflict";

const AUTOSAVE_DELAY = 450;

/**
 * One open note's unsaved input and how it reached the disk. Saving never waits on the editor: it
 * reads the current text when a write starts, and only ever reports "saved" for what the disk holds.
 */
export class NoteSession {
  status: SaveStatus = "saved";
  message?: string;
  private saved: string;
  private timer?: ReturnType<typeof setTimeout>;
  private writing?: Promise<void>;
  private listeners = new Set<() => void>();

  constructor(
    readonly path: string,
    source: string,
    /** The editor's current text, and whether an input method is still composing it. */
    private readonly current: () => { text: string; composing: boolean },
  ) {
    this.saved = source;
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  edited() {
    if (this.status !== "failed" && this.status !== "conflict") this.set("pending");
    clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.write(), AUTOSAVE_DELAY);
  }

  /** Saves anything unsaved now; true once the disk holds the editor's text. */
  async flush(): Promise<boolean> {
    clearTimeout(this.timer);
    await this.writing;
    await this.write(true);
    return this.status === "saved";
  }

  private write(force = false): Promise<void> {
    if (this.writing) return this.writing;
    const { text: value, composing } = this.current();
    // Wait for the input method to commit before writing, unless the window is going away.
    if (composing && !force) {
      this.timer = setTimeout(() => void this.write(), AUTOSAVE_DELAY);
      return Promise.resolve();
    }
    if (value === this.saved) {
      this.set("saved");
      return Promise.resolve();
    }
    this.set("saving");
    const failed = (error: unknown): SaveResult => ({ ok: false, conflict: false, message: errorText(error) });
    this.writing = window.notes.saveNote(this.path, value, this.saved).catch(failed).then((result) => {
      this.writing = undefined;
      if (result.ok) {
        this.saved = value;
        this.set(this.current().text === value ? "saved" : "pending");
        if (this.status === "pending") this.edited();
      } else {
        this.set(result.conflict ? "conflict" : "failed", result.message);
      }
    });
    return this.writing;
  }

  private set(status: SaveStatus, message?: string) {
    this.status = status;
    this.message = message;
    for (const listener of this.listeners) listener();
  }
}

let active: NoteSession | null = null;

export function setActiveSession(session: NoteSession | null) {
  active = session;
}

/** Saves the open note, if any; used before switching notes or libraries and before closing. */
export async function flushActive(): Promise<CloseCheck> {
  if (!active || (await active.flush())) return { saved: true };
  return { saved: false, message: active.message ?? "笔记还没有保存。" };
}
