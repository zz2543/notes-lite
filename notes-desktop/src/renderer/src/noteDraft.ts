import type { CloseCheck, SaveResult } from "../../shared/api";
import { errorText } from "./ipc";

export type SaveStatus = "saved" | "pending" | "saving" | "failed" | "conflict";

const autosaveDelay = 450;

/**
 * The open note's text as the editor holds it, and how it reaches the disk. A write reads the
 * editor's text when it starts, and "saved" is only ever reported for what the disk holds.
 */
export class NoteDraft {
  status: SaveStatus = "saved";
  message?: string;
  private saved: string;
  private timer?: ReturnType<typeof setTimeout>;
  private writing?: Promise<void>;
  private listeners = new Set<() => void>();

  constructor(
    readonly path: string,
    source: string,
    /** The editor's text, and whether an input method is still composing it. */
    private readonly readEditor: () => { text: string; composing: boolean },
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
    this.timer = setTimeout(() => void this.write(), autosaveDelay);
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
    const { text, composing } = this.readEditor();
    // Wait for the input method to commit before writing, unless the window is going away.
    if (composing && !force) {
      this.timer = setTimeout(() => void this.write(), autosaveDelay);
      return Promise.resolve();
    }
    // Undoing back to the saved text needs no write, unless the disk has since diverged from it.
    if (text === this.saved && this.status !== "conflict") {
      this.set("saved");
      return Promise.resolve();
    }
    this.set("saving");
    const failed = (error: unknown): SaveResult => ({ ok: false, code: "write-failed", message: errorText(error) });
    this.writing = window.notes.saveNote(this.path, text, this.saved).catch(failed).then((result) => {
      this.writing = undefined;
      if (result.ok) {
        this.saved = text;
        this.set(this.readEditor().text === text ? "saved" : "pending");
        if (this.status === "pending") this.edited();
      } else if (result.code === "conflict") {
        this.set("conflict", `${result.message}为避免覆盖，没有保存；你的输入仍保留在编辑器中。`);
      } else {
        this.set("failed", result.message);
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

// Only one note is open at a time; the app saves it before anything takes it away.
let openDraft: NoteDraft | null = null;

export function setOpenDraft(draft: NoteDraft | null) {
  openDraft = draft;
}

/** Saves the open note, if any: before switching notes or libraries and before the window closes. */
export async function saveOpenNote(): Promise<CloseCheck> {
  if (!openDraft || (await openDraft.flush())) return { saved: true };
  return { saved: false, message: openDraft.message ?? "笔记还没有保存。" };
}
