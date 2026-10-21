import { defaultKeymap, history, historyKeymap, redo } from "@codemirror/commands";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { countWords, isAddress, linkPath } from "../../shared/markdown";
import { ConflictNotice } from "./ConflictNotice";
import { pageShown, useNoteSource } from "./ipc";
import { linkHost, type LinkHost } from "./linkHost";
import { importChosen, linkHandling } from "./links";
import { listEditing } from "./listEditing";
import { markdownDisplay, switchMarkdownView } from "./markdownView";
import { NoteDraft, setOpenDraft, type SaveStatus } from "./noteDraft";
import { setShowSource, useShowSource } from "./sourceView";

interface Choices {
  /** The input was saved as a new note at `path`: open it in place of this one. */
  onOpenCopy(path: string): void;
  /** The note can no longer be shown and nothing unsaved holds it: close it, saying why. */
  onLetGo(reason: string): void;
  /** A link in the note led to the note at `path`: open it. */
  onOpenLinked(path: string): void;
  /** Something to tell the user: a link that leads nowhere, a file that couldn't be imported. */
  notify(message: string): void;
}

/**
 * The open note on its card: Markdown source edited in place, saved as it is typed. A `fresh` note
 * (just created) opens with the caret after its title, ready to type.
 */
export function NoteEditor({
  path,
  fresh = false,
  headEnd,
  ...choices
}: {
  path: string | null;
  fresh?: boolean;
  /** At the head's right end, after the card's own tools: the 助手栏 toggle while the column is closed. */
  headEnd?: ReactNode;
} & Choices) {
  const { value: source, error } = useNoteSource(path);
  const showSource = useShowSource();
  useEffect(() => {
    if (!path || error) pageShown();
  }, [path, error]);
  // With a note open, its editor answers the menu's 导入图片或附件….
  useEffect(() => {
    if (path) return;
    return window.notes.onImportAttachmentsRequest(() => choices.notify("请先打开一篇笔记，再导入图片或附件。"));
  }, [path]);
  return (
    <article className="card" aria-label="卡片">
      <header className="card-head">
        <span className="card-path">{path?.split("/").join(" / ")}</span>
        <button
          className="card-tool"
          aria-pressed={showSource}
          title="切换源码与原地排版"
          // The editor keeps focus, so typing goes on where it was.
          onMouseDown={(event) => event.preventDefault()}
          onClick={() => setShowSource(!showSource)}
        >
          Markdown 源码
        </button>
        {headEnd}
      </header>
      {!path && <p className="empty">选择一篇笔记</p>}
      {error && <p className="empty">{error}</p>}
      {path && source !== undefined && (
        <Editor key={path} path={path} source={source} fresh={fresh} showSource={showSource} {...choices} />
      )}
    </article>
  );
}

// A file that breaks lines with CRLF throughout keeps CRLF; otherwise lines split on "\n" and any
// stray "\r" stays part of its line. Either way the text saved is exactly the text loaded plus edits.
const lineSeparatorOf = (source: string) => (/\r\n/.test(source) && !/(^|[^\r])\n/.test(source) ? "\r\n" : "\n");

const wordCountDelay = 150;

function Editor({
  path,
  source,
  fresh,
  showSource,
  onOpenCopy,
  onLetGo,
  onOpenLinked,
  notify,
}: { path: string; source: string; fresh: boolean; showSource: boolean } & Choices) {
  const host = useRef<HTMLDivElement>(null);
  const viewRef = useRef<EditorView>(null);
  const shown = useRef(showSource);
  const [draft, setDraft] = useState<NoteDraft>();
  const [words, setWords] = useState(() => countWords(source));

  // The latest callbacks, for the editor made once per note.
  const linkChoices = useRef({ onOpenLinked, notify });
  linkChoices.current = { onOpenLinked, notify };

  useEffect(() => {
    let countTimer: ReturnType<typeof setTimeout> | undefined;
    const links = noteLinks(path, linkChoices);
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
          markdownDisplay(shown.current),
          listEditing,
          linkHost.of(links.host),
          linkHandling,
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
    // The version on disk starts afresh, with its own undo history, the caret and scroll kept in place.
    const showDisk = (text: string) => {
      const { scrollTop } = view.scrollDOM;
      const head = view.state.selection.main.head;
      const next = stateFor(text);
      view.setState(next.update({ selection: { anchor: Math.min(head, next.doc.length) } }).state);
      view.scrollDOM.scrollTop = scrollTop;
      clearTimeout(countTimer);
      setWords(countWords(text));
    };
    // sliceDoc joins lines with the note's own separator; doc.toString() would always use "\n".
    const draft = new NoteDraft(path, source, () => ({ text: view.state.sliceDoc(), composing: view.composing }), showDisk);
    setOpenDraft(draft);
    setDraft(draft);
    viewRef.current = view;
    if (fresh) view.dispatch({ selection: { anchor: view.state.doc.length } });
    view.focus();
    pageShown();
    const offImport = window.notes.onImportAttachmentsRequest(() => void importChosen(view, links.choose));
    return () => {
      offImport();
      links.close();
      clearTimeout(countTimer);
      // The app saves before it switches notes; this only catches an unmount nobody asked to save.
      void draft.flush();
      setOpenDraft(null);
      viewRef.current = null;
      view.destroy();
    };
  }, [path, source]);

  // The same document shown another way: the state (text, selection, undo, composition) stays.
  useEffect(() => {
    if (shown.current === showSource || !viewRef.current) return;
    shown.current = showSource;
    switchMarkdownView(viewRef.current, showSource);
  }, [showSource]);

  return (
    <>
      {draft && <ConflictNotice draft={draft} onKeep={() => viewRef.current?.focus()} onOpenCopy={onOpenCopy} onLetGo={onLetGo} />}
      <div className="editor" ref={host} role="group" aria-label="编辑器" />
      <footer className="card-foot">
        {draft && <SaveState draft={draft} />}
        <span className="words">{words} 字</span>
      </footer>
    </>
  );
}

/** Following links and importing files for the note at `path`; its images are read once each until
 *  something other than a note changes in the library. */
function noteLinks(path: string, choices: { current: Pick<Choices, "onOpenLinked" | "notify"> }) {
  const notes = window.notes;
  /** Whether it worked; a refusal is shown to the user. */
  const reported = (result: { ok: true } | { ok: false; message: string }) => {
    if (!result.ok) choices.current.notify(result.message);
    return result.ok;
  };
  const images = new Map<string, ReturnType<LinkHost["image"]>>();
  const offChanged = notes.onLibraryChanged((paths) => {
    if (paths.some((changed) => !/\.md$/i.test(changed))) images.clear();
  });
  const host: LinkHost = {
    follow: async (link) => {
      // A web or mail address leaves the app; anything else is looked for in the library.
      if (isAddress(link.target)) return void reported(await notes.openExternal(link.target.trim()));
      // `[[#标题]]`, `[x](#标题)`: a place in this note, which there is nothing yet to go to.
      if (linkPath(link.target) === "") return;
      const found = await notes.followLink(path, link);
      if (!reported(found) || !found.ok) return;
      if (found.value.kind === "note") choices.current.onOpenLinked(found.value.path);
      else reported(await notes.openLinkedFile(path, link));
    },
    open: async (link) => void reported(await notes.openLinkedFile(path, link)),
    image: (link) => {
      const key = `${link.wiki}\n${link.target}`;
      let image = images.get(key);
      if (!image) images.set(key, (image = notes.readImage(path, link)));
      return image;
    },
    importFiles: async (files) => {
      const imported = await notes.importAttachments(path, files);
      return reported(imported) && imported.ok ? imported.value : null;
    },
  };
  const choose = async () => {
    const chosen = await notes.chooseAttachments(path);
    return reported(chosen) && chosen.ok ? chosen.value : null;
  };
  return { host, choose, close: offChanged };
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
