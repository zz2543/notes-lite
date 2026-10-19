import { useEffect, useState } from "react";
import type { FolderContents } from "../../core/library";

/** The user-facing part of an error that crossed over from the main process. */
export function errorText(error: unknown): string {
  const text = error instanceof Error ? error.message : String(error);
  return text.replace(/^Error invoking remote method '[^']+': (?:\w*Error: )?/, "");
}

export interface FolderState {
  contents?: FolderContents;
  error?: string;
}

/** 当前目录内容 of one folder, read when the path changes. */
export function useFolder(path: string): FolderState {
  const [state, setState] = useState<FolderState & { path?: string }>({});
  useEffect(() => {
    let live = true;
    window.notes.readFolder(path).then(
      (contents) => live && setState({ path, contents }),
      (error: unknown) => live && setState({ path, error: errorText(error) }),
    );
    return () => {
      live = false;
    };
  }, [path]);
  return state.path === path ? state : {};
}
