import { useEffect, useRef } from "react";
import type { CloseCheck, CopyResult, SaveResult } from "../../shared/api";
import { errorText } from "./ipc";
import { isWithin, onLibraryChange } from "./libraryChanges";

export type SaveStatus = "saved" | "pending" | "saving" | "failed" | "conflict";

/** What following the disk came to; `gone` says why the note can no longer be shown. */
export interface Followed {
  gone?: string;
}

const autosaveDelay = 450;

const changedElsewhere = "这篇笔记已在别处修改。";

/**
 * The open note's text as the editor holds it, and how it reaches the disk. A write reads the
 * editor's text when it starts, and "saved" is only ever reported for what the disk holds. When
 * the disk changes under unsaved input, the input is held as a conflict until the user chooses.
 */
export class NoteDraft {
  status: SaveStatus = "saved";
  message?: string;
  /** The conflict notice is up, asking what to do with the input. */
  notice = false;
  /** In a conflict: the disk holds no version of the note that can be shown (moved, deleted, unreadable). */
  unavailable = false;
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
    // A conflict waits for the user's choice: writing again would only meet the same refusal.
    if (this.closed || this.status === "conflict") return;
    if (this.status !== "failed") this.set("pending");
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
    let disk: Disk;
    let writes: number;
    // The change may be this draft's own write: read only once no write overlaps the read.
    do {
      await this.writing;
      writes = this.writes;
      disk = await this.readDisk();
    } while (this.writing || writes !== this.writes);
    if (this.closed) return {};
    const { text, composing } = this.readEditor();
    if (!composing && text === this.saved) {
      // Nothing unsaved to lose: show what the disk holds now, or let go when it holds nothing to show.
      if (disk.text === undefined) return this.letGo(disk.error);
      if (disk.text !== this.saved || this.status === "conflict") this.adopt(disk.text);
      return {};
    }
    if (disk.text === this.saved) {
      // Back to the version the input was based on (the change was undone elsewhere): saving can go on.
      if (this.status === "conflict") {
        this.set("pending");
        this.edited();
      }
      return {};
    }
    if (disk.text === text) {
      clearTimeout(this.timer);
      this.saved = text;
      this.set("saved");
      return {};
    }
    const unavailable = disk.text === undefined;
    // Raised again only with news; the user may have set the notice aside already.
    const news = this.status !== "conflict" || this.unavailable !== unavailable;
    this.conflict(disk.error ?? changedElsewhere, unavailable, news);
    return {};
  }

  /** Keeps the input in the editor, unsaved, and puts the conflict notice away until there is news. */
  keepInput() {
    this.notice = false;
    this.emit();
  }

  /** Saves the input as a new note beside this one; this draft is done with once it is saved. */
  async saveCopy(): Promise<{ path: string } | { error: string }> {
    const failed = (error: unknown): CopyResult => ({ ok: false, code: "write-failed", message: errorText(error) });
    const result = await window.notes.saveCopy(this.path, this.readEditor().text).catch(failed);
    if (!result.ok) return { error: result.message };
    this.close();
    return { path: result.path };
  }

  /** Drops the input for the version on disk; `gone` when there is none to show. */
  async reload(): Promise<Followed> {
    const disk = await this.readDisk();
    if (this.closed) return {};
    if (disk.text === undefined) return this.letGo(disk.error);
    this.adopt(disk.text);
    return {};
  }

  private readDisk(): Promise<Disk> {
    return window.notes.readNote(this.path).then(
      (text) => ({ text }),
      (error: unknown) => ({ error: errorText(error) }),
    );
  }

  /** Shows the version on disk as the note's saved text. */
  private adopt(text: string) {
    clearTimeout(this.timer);
    this.saved = text;
    this.showDisk?.(text);
    this.set("saved");
  }

  private letGo(reason: string): Followed {
    this.close();
    return { gone: reason };
  }

  private close() {
    this.closed = true;
    clearTimeout(this.timer);
  }

  private conflict(message: string, unavailable: boolean, raise: boolean) {
    this.unavailable = unavailable;
    if (raise) this.notice = true;
    this.set("conflict", message);
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
      } else if (result.code === "conflict" || result.code === "not-found") {
        this.conflict(result.message, result.code === "not-found", true);
      } else {
        this.set("failed", result.message);
      }
    });
    return this.writing;
  }

  private set(status: SaveStatus, message?: string) {
    this.status = status;
    this.message = message;
    // A retry in flight keeps the notice up; anything but a conflict puts it away.
    if (status !== "conflict" && status !== "saving") this.notice = false;
    this.emit();
  }

  private emit() {
    for (const listener of this.listeners) listener();
  }
}

type Disk = { text: string; error?: undefined } | { text?: undefined; error: string };

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
export function useOpenNoteFollowsDisk(note: string | null, letGo: (reason: string, note: string) => void) {
  const latestLetGo = useRef(letGo);
  latestLetGo.current = letGo;
  useEffect(() => {
    if (note === null) return;
    let live = true;
    const off = onLibraryChange(async (paths) => {
      const draft = openDraft;
      if (draft?.path !== note || !paths.some((changed) => isWithin(note, changed))) return;
      const { gone } = await draft.followDisk();
      if (live && gone !== undefined) latestLetGo.current(gone, note);
    });
    return () => {
      live = false;
      off();
    };
  }, [note]);
}
