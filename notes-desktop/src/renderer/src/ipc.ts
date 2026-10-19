import { useEffect, useState } from "react";
import type { FolderContents } from "../../core";
import { touchesFolder, useChangeCount } from "./libraryChanges";

/** The user-facing part of an error that crossed over from the main process. */
export function errorText(error: unknown): string {
  const text = error instanceof Error ? error.message : String(error);
  return text.replace(/^Error invoking remote method '[^']+': (?:\w*Error: )?/, "");
}

export interface Read<T> {
  value?: T;
  error?: string;
}

/**
 * Reads `path` from the library whenever it (or `version`) changes; an answer for an older path is
 * never shown, and while a path is read again its last answer stays.
 */
export function useRead<T>(path: string | null, read: (path: string) => Promise<T>, version = 0): Read<T> {
  const [state, setState] = useState<Read<T> & { path?: string }>({});
  useEffect(() => {
    if (path === null) return;
    let live = true;
    read(path).then(
      (value) => live && setState({ path, value }),
      (error: unknown) => live && setState({ path, error: errorText(error) }),
    );
    return () => {
      live = false;
    };
  }, [path, read, version]);
  return path !== null && state.path === path ? state : {};
}

// Module-level readers keep a stable identity for useRead's effect.
const readFolder = (path: string) => window.notes.readFolder(path);
const readNote = (path: string) => window.notes.readNote(path);

/** 当前目录内容 of one folder, read again whenever something in it changes. */
export const useFolder = (path: string): Read<FolderContents> => useRead(path, readFolder, useChangeCount(path, touchesFolder));

/** A note's Markdown source. */
export const useNoteSource = (path: string | null): Read<string> => useRead(path, readNote);
