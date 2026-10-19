import { useEffect, useRef } from "react";
import type { CloseCheck, SaveResult } from "../../shared/api";
import { errorText } from "./ipc";
import { isWithin, onLibraryChange } from "./libraryChanges";

export type SaveStatus = "saved" | "pending" | "saving" | "failed" | "conflict";

/** What following the disk came to; `gone` says why the note can no longer be shown. */
export interface Followed {
  gone?: string;
}

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
  /** Writes started so far, so a read of the disk can tell whether one of them overlapped it. */
  private writes = 0;
  private following: Promise<Followed> = Promise.resolve({});
  /** Set once the note no longer belongs to this draft (it was let go); nothing more is written. */
  private closed = false;
  private listeners = new Set<() => void>();

  constructor(
    readonly path: string,
    source: string,
    /** The editor's text, and whether an input method is still composing it. */
    private readonly readEditor: () => { text: string; composing: boolean },
    /** Shows the version on disk in the editor, starting afresh. */
    private readonly showDisk?: (text: string) => void,
  ) {
    this.saved = source;
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  edited() {
    if (this.closed) return;
    if (this.status !== "failed" && this.status !== "conflict") this.set("pending");
    clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.write(), autosaveDelay);
  }

  /** Saves anything unsaved now; true once the disk holds the editor's text. */
  async flush(): Promise<boolean> {
    if (this.closed) return true;
    clearTimeout(this.timer);
    await this.writing;
    await this.write(true);
    return this.status === "saved";
  }

  /**
   * The note changed on disk, by this app or another program. With nothing unsaved the editor
   * follows the disk; `gone` says why the note can no longer be shown, when that is so.
   */
  followDisk(): Promise<Followed> {
    this.following = this.following.then(() => this.compareWithDisk());
    return this.following;
  }

  private async compareWithDisk(): Promise<Followed> {
    let disk: { text?: string; error?: string };
    let writes: number;
    // The change may be this draft's own write: read only once no write overlaps the read.
    do {
      await this.writing;
      writes = this.writes;
      disk = await window.notes.readNote(this.path).then(
        (text) => ({ text }),
        (error: unknown) => ({ error: errorText(error) }),
      );
    } while (this.writing || writes !== this.writes);
    if (this.closed) return {};
    const { text, composing } = this.readEditor();
    const unsaved = composing || text !== this.saved;
    if (disk.text === undefined) {
      if (unsaved) return {};
      this.close();
      return { gone: disk.error };
    }
    if (disk.text === this.saved || unsaved || !this.showDisk) return {};
    clearTimeout(this.timer);
    this.saved = disk.text;
    this.showDisk(disk.text);
    this.set("saved");
    return {};
  }

  private close() {
    this.closed = true;
    clearTimeout(this.timer);
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
    this.writes++;
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

/**
 * Keeps the open note in step with changes made to it elsewhere; `letGo` is called with the reason
 * when it can no longer be shown and nothing unsaved holds it open.
 */
export function useOpenNoteFollowsDisk(note: string | null, letGo: (reason: string) => void) {
  const latestLetGo = useRef(letGo);
  latestLetGo.current = letGo;
  useEffect(() => {
    if (note === null) return;
    let live = true;
    const off = onLibraryChange(async (paths) => {
      const draft = openDraft;
      if (draft?.path !== note || !paths.some((changed) => isWithin(note, changed))) return;
      const { gone } = await draft.followDisk();
      if (live && gone !== undefined) latestLetGo.current(gone);
    });
    return () => {
      live = false;
      off();
    };
  }, [note]);
}
