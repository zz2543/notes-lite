import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { countWords } from "../../core/text";
import { useNoteSource } from "./ipc";
import { NoteSession, setActiveSession, type SaveStatus } from "./noteSession";

/** The open note on its card: Markdown source edited in place, saved as it is typed. */
export function NoteEditor({ path }: { path: string | null }) {
  const { value: source, error } = useNoteSource(path);
  return (
    <article className="card">
      <header className="card-head">{path?.split("/").join(" / ")}</header>
      {!path && <p className="empty">选择一篇笔记</p>}
      {error && <p className="empty">{error}</p>}
      {path && source !== undefined && <Editor key={path} path={path} source={source} />}
    </article>
  );
}

// A file that breaks lines with CRLF throughout keeps CRLF; otherwise lines split on "\n" and any
// stray "\r" stays part of its line. Either way the text saved is exactly the text loaded plus edits.
const lineSeparatorOf = (source: string) => (/\r\n/.test(source) && !/(^|[^\r])\n/.test(source) ? "\r\n" : "\n");

const WORD_COUNT_DELAY = 150;

function Editor({ path, source }: { path: string; source: string }) {
  const host = useRef<HTMLDivElement>(null);
  const [session, setSession] = useState<NoteSession>();
  const [words, setWords] = useState(() => countWords(source));

  useEffect(() => {
    let countTimer: ReturnType<typeof setTimeout> | undefined;
    const view: EditorView = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: source,
        extensions: [
          EditorState.lineSeparator.of(lineSeparatorOf(source)),
          history(),
          keymap.of([...defaultKeymap, ...historyKeymap]),
          EditorView.lineWrapping,
          EditorView.contentAttributes.of({ "aria-label": "笔记正文", spellcheck: "false" }),
          EditorView.updateListener.of((update) => {
            if (!update.docChanged) return;
            next.edited();
            clearTimeout(countTimer);
            countTimer = setTimeout(() => setWords(countWords(update.state.doc.toString())), WORD_COUNT_DELAY);
          }),
        ],
      }),
    });
    // sliceDoc joins lines with the note's own separator; doc.toString() would always use "\n".
    const next = new NoteSession(path, source, () => ({ text: view.state.sliceDoc(), composing: view.composing }));
    setActiveSession(next);
    setSession(next);
    view.focus();
    return () => {
      clearTimeout(countTimer);
      // The app saves before it switches notes; this only catches an unmount nobody asked to save.
      void next.flush();
      setActiveSession(null);
      view.destroy();
    };
  }, [path, source]);

  return (
    <>
      <div className="editor" ref={host} />
      <footer className="card-foot">
        {session && <SaveState session={session} />}
        <span className="words">{words} 字</span>
      </footer>
    </>
  );
}

const labels: Record<SaveStatus, string> = {
  saved: "已保存",
  pending: "正在保存…",
  saving: "正在保存…",
  failed: "未保存",
  conflict: "保存冲突",
};

function SaveState({ session }: { session: NoteSession }) {
  const status = useSyncExternalStore(session.subscribe, () => session.status);
  const problem = status === "failed" || status === "conflict";
  return (
    <span className={`save ${problem ? "problem" : ""}`} role="status" aria-label="保存状态">
      {/* A long reason is clipped, never the retry button after it; the tooltip keeps it whole. */}
      <span className="save-text" title={problem ? session.message : undefined}>
        {problem ? `${labels[status]}：${session.message}` : labels[status]}
      </span>
      {problem && (
        <button className="retry" onClick={() => void session.flush()}>
          重试
        </button>
      )}
    </span>
  );
}
