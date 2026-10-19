import { useNoteSource } from "./ipc";

/** The open note on its card. Read-only Markdown source until the editor arrives. */
export function NoteView({ path }: { path: string | null }) {
  const { value: text, error } = useNoteSource(path);
  return (
    <article className="card">
      <header className="card-head">{path?.split("/").join(" / ")}</header>
      {!path && <p className="empty">选择一篇笔记</p>}
      {error && <p className="empty">{error}</p>}
      {text !== undefined && (
        <pre className="source" aria-label="笔记原文">
          {text}
        </pre>
      )}
    </article>
  );
}
