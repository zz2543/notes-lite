import { defaultKeymap, history, historyKeymap, redo } from "@codemirror/commands";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { countWords } from "../../core/markdown";
import { ConflictNotice } from "./ConflictNotice";
import { useNoteSource } from "./ipc";
import { NoteDraft, setOpenDraft, type SaveStatus } from "./noteDraft";

interface Choices {
  /** The input was saved as a new note at `path`: open it in place of this one. */
  onOpenCopy(path: string): void;
  /** The note can no longer be shown and nothing unsaved holds it: close it, saying why. */
  onLetGo(reason: string): void;
}

/** The open note on its card: Markdown source edited in place, saved as it is typed. */
export function NoteEditor({ path, ...choices }: { path: string | null } & Choices) {
  const { value: source, error } = useNoteSource(path);
  return (
    <article className="card">
      <header className="card-head">{path?.split("/").join(" / ")}</header>
      {!path && <p className="empty">选择一篇笔记</p>}
      {error && <p className="empty">{error}</p>}
      {path && source !== undefined && <Editor key={path} path={path} source={source} {...choices} />}
    </article>
  );
}

// A file that breaks lines with CRLF throughout keeps CRLF; otherwise lines split on "\n" and any
// stray "\r" stays part of its line. Either way the text saved is exactly the text loaded plus edits.
const lineSeparatorOf = (source: string) => (/\r\n/.test(source) && !/(^|[^\r])\n/.test(source) ? "\r\n" : "\n");

const wordCountDelay = 150;

function Editor({ path, source, onOpenCopy, onLetGo }: { path: string; source: string } & Choices) {
  const host = useRef<HTMLDivElement>(null);
  const editor = useRef<EditorView>(null);
  const [draft, setDraft] = useState<NoteDraft>();
  const [words, setWords] = useState(() => countWords(source));

  useEffect(() => {
    let countTimer: ReturnType<typeof setTimeout> | undefined;
    const stateFor = (doc: string) => {
      const separator = lineSeparatorOf(doc);
      return EditorState.create({
        doc,
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
      });
    };
    const view: EditorView = new EditorView({ parent: host.current!, state: stateFor(source) });
    editor.current = view;
    // The version on disk starts afresh, with its own undo history, the caret and scroll kept in place.
    const showDisk = (text: string) => {
      const { scrollTop } = view.scrollDOM;
      const head = view.state.selection.main.head;
      const fresh = stateFor(text);
      view.setState(fresh.update({ selection: { anchor: Math.min(head, fresh.doc.length) } }).state);
      view.scrollDOM.scrollTop = scrollTop;
      clearTimeout(countTimer);
      setWords(countWords(text));
    };
    // sliceDoc joins lines with the note's own separator; doc.toString() would always use "\n".
    const draft = new NoteDraft(path, source, () => ({ text: view.state.sliceDoc(), composing: view.composing }), showDisk);
    setOpenDraft(draft);
    setDraft(draft);
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
      {draft && <ConflictNotice draft={draft} onKeep={() => editor.current?.focus()} onOpenCopy={onOpenCopy} onLetGo={onLetGo} />}
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
      {/* Retrying a conflict succeeds once the disk is back to the version the input started from. */}
      {problem && (
        <button className="retry" onClick={() => void draft.flush()}>
          重试
        </button>
      )}
    </span>
  );
}
