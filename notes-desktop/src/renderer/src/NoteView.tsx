import { useEffect, useState } from "react";
import { errorText } from "./useFolder";

/** The open note on its card. Read-only Markdown source until the editor arrives. */
export function NoteView({ path }: { path: string | null }) {
  const [note, setNote] = useState<{ path: string; text?: string; error?: string }>();
  useEffect(() => {
    if (!path) return;
    let live = true;
    window.notes.readNote(path).then(
      (text) => live && setNote({ path, text }),
      (error: unknown) => live && setNote({ path, error: errorText(error) }),
    );
    return () => {
      live = false;
    };
  }, [path]);

  const shown = note?.path === path ? note : undefined;
  return (
    <article className="card">
      <header className="card-head">{path?.split("/").join(" / ")}</header>
      {!path && <p className="empty">选择一篇笔记</p>}
      {shown?.error && <p className="empty">{shown.error}</p>}
      {shown?.text !== undefined && (
        <pre className="source" aria-label="笔记原文">
          {shown.text}
        </pre>
      )}
    </article>
  );
}
