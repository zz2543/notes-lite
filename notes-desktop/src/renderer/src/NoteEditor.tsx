import { defaultKeymap, history, historyKeymap, redo } from "@codemirror/commands";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { countWords } from "../../core/markdown";
import { useNoteSource } from "./ipc";
import { NoteDraft, setOpenDraft, type SaveStatus } from "./noteDraft";

/**
 * The open note on its card: Markdown source edited in place, saved as it is typed. A `fresh` note
 * (just created) opens with the caret after its title, ready to type.
 */
export function NoteEditor({ path, fresh = false }: { path: string | null; fresh?: boolean }) {
  const { value: source, error } = useNoteSource(path);
  return (
    <article className="card">
      <header className="card-head">{path?.split("/").join(" / ")}</header>
      {!path && <p className="empty">选择一篇笔记</p>}
      {error && <p className="empty">{error}</p>}
      {path && source !== undefined && <Editor key={path} path={path} source={source} fresh={fresh} />}
    </article>
  );
}

// A file that breaks lines with CRLF throughout keeps CRLF; otherwise lines split on "\n" and any
// stray "\r" stays part of its line. Either way the text saved is exactly the text loaded plus edits.
const lineSeparatorOf = (source: string) => (/\r\n/.test(source) && !/(^|[^\r])\n/.test(source) ? "\r\n" : "\n");

const wordCountDelay = 150;

function Editor({ path, source, fresh }: { path: string; source: string; fresh: boolean }) {
  const host = useRef<HTMLDivElement>(null);
  const [draft, setDraft] = useState<NoteDraft>();
  const [words, setWords] = useState(() => countWords(source));

  useEffect(() => {
    let countTimer: ReturnType<typeof setTimeout> | undefined;
    const separator = lineSeparatorOf(source);
    const view: EditorView = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: source,
        extensions: [
          EditorState.lineSeparator.of(separator),
          // Pasted or dropped text takes the note's own line breaks, or a CRLF note would hide "\n"s inside lines.
          EditorView.clipboardInputFilter.of((text) => (separator === "\r\n" ? text.replace(/\r?\n/g, "\r\n") : text)),
          history(),
          // Redo answers to ⌘⇧Z / Ctrl+Shift+Z everywhere, and to Ctrl+Y on Windows as usual.
          keymap.of([{ key: "Mod-Shift-z", run: redo, preventDefault: true }, ...defaultKeymap, ...historyKeymap]),
          EditorView.lineWrapping,
          EditorView.contentAttributes.of({ "aria-label": "笔记正文", spellcheck: "false" }),
          EditorView.updateListener.of((update) => {
            if (!update.docChanged) return;
            draft.edited();
            clearTimeout(countTimer);
            countTimer = setTimeout(() => setWords(countWords(update.state.doc.toString())), wordCountDelay);
          }),
        ],
      }),
    });
    // sliceDoc joins lines with the note's own separator; doc.toString() would always use "\n".
    const draft = new NoteDraft(path, source, () => ({ text: view.state.sliceDoc(), composing: view.composing }));
    setOpenDraft(draft);
    setDraft(draft);
    if (fresh) view.dispatch({ selection: { anchor: view.state.doc.length } });
    view.focus();
    return () => {
      clearTimeout(countTimer);
      // The app saves before it switches notes; this only catches an unmount nobody asked to save.
      void draft.flush();
      setOpenDraft(null);
      view.destroy();
    };
  }, [path, source]);

  return (
    <>
      <div className="editor" ref={host} />
      <footer className="card-foot">
        {draft && <SaveState draft={draft} />}
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

function SaveState({ draft }: { draft: NoteDraft }) {
  const status = useSyncExternalStore(draft.subscribe, () => draft.status);
  const problem = status === "failed" || status === "conflict";
  return (
    <span className={`save ${problem ? "problem" : ""}`} role="status" aria-label="保存状态">
      {/* A long reason is clipped, never the retry button after it; the tooltip keeps it whole. */}
      <span className="save-text" title={problem ? draft.message : undefined}>
        {problem ? `${labels[status]}：${draft.message}` : labels[status]}
      </span>
      {/* A conflict can't be retried away; resolving it (reload or save a copy) comes with external changes. */}
      {status === "failed" && (
        <button className="retry" onClick={() => void draft.flush()}>
          重试
        </button>
      )}
    </span>
  );
}
