import { CaretUpDown, HardDrives } from "@phosphor-icons/react";
import { useEffect, useRef, useState } from "react";
import type { LaunchState, LibraryInfo } from "../../shared/api";
import { FolderContentsList } from "./FolderContentsList";
import { FolderTree } from "./FolderTree";
import { errorText } from "./ipc";
import { useFolderFallback } from "./libraryChanges";
import { NoteEditor } from "./NoteEditor";
import { saveOpenNote, useOpenNoteFollowsDisk } from "./noteDraft";
import { icon } from "./tokens";

type Phase = { kind: "starting" } | LaunchState;

const noticeDuration = 6000;

export function App() {
  const [phase, setPhase] = useState<Phase>({ kind: "starting" });
  const [error, setError] = useState<string>();

  // A notice, not a dialog: it fades on its own and never blocks what is under it.
  useEffect(() => {
    if (!error) return;
    const timer = setTimeout(() => setError(undefined), noticeDuration);
    return () => clearTimeout(timer);
  }, [error]);

  // Anything unsaved reaches the disk before the open note goes away: another note, another
  // library, or the window itself.
  const saveFirst = async (): Promise<boolean> => {
    const check = await saveOpenNote();
    if (!check.saved) setError(`${check.message}你的输入仍保留在编辑器中。`);
    return check.saved;
  };

  const choose = async () => {
    setError(undefined);
    if (!(await saveFirst())) return;
    try {
      const library = await window.notes.chooseLibrary();
      if (library) setPhase({ kind: "open", library });
    } catch (e) {
      setError(errorText(e));
    }
  };

  useEffect(() => {
    void window.notes.launchState().then(setPhase);
    const offMenu = window.notes.onOpenLibraryRequest(() => void choose());
    const offClose = window.notes.onBeforeClose(saveOpenNote);
    return () => {
      offMenu();
      offClose();
    };
  }, []);

  return (
    <>
      {/* Until the remembered library answers, the window shows only its own color: no spinner. */}
      {phase.kind === "welcome" && <Welcome missing={phase.missing} onChoose={choose} />}
      {phase.kind === "open" && (
        <LibraryView key={phase.library.root} library={phase.library} onSwitch={choose} saveFirst={saveFirst} notify={setError} />
      )}
      {error && (
        <div className="toast" role="alert">
          {error}
        </div>
      )}
    </>
  );
}

function Welcome({ missing, onChoose }: { missing?: string; onChoose(): void }) {
  return (
    <main className="welcome">
      <div className="drag" />
      <h1>打开笔记库</h1>
      {missing && (
        <p className="missing" role="status">
          找不到上次的笔记库“{missing}”，它可能被移动、改名或删除了。
        </p>
      )}
      <p>
        选择一个本地文件夹作为笔记库，里面的 Markdown 文件就是你的笔记。
        <br />
        下次启动会自动打开它。
      </p>
      <button className="primary" onClick={onChoose}>
        选择笔记库…
      </button>
    </main>
  );
}

function ancestors(path: string): string[] {
  const parts = path ? path.split("/") : [];
  return ["", ...parts.map((_, i) => parts.slice(0, i + 1).join("/"))];
}

interface LibraryViewProps {
  library: LibraryInfo;
  onSwitch(): void;
  /** Saves the open note; false when it could not, so the note must stay open. */
  saveFirst(): Promise<boolean>;
  /** Shows a passing notice. */
  notify(message: string): void;
}

function LibraryView({ library, onSwitch, saveFirst, notify }: LibraryViewProps) {
  const [folder, setFolder] = useState("");
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(() => new Set([""]));
  const [note, setNote] = useState<string | null>(null);
  // Other programs may move, delete or rewrite what is shown.
  useFolderFallback(folder, setFolder);
  const letGo = (reason: string) => {
    setNote(null);
    notify(reason);
  };
  useOpenNoteFollowsDisk(note, letGo);

  const toggle = (path: string) =>
    setExpanded((now) => {
      const next = new Set(now);
      if (!next.delete(path)) next.add(path);
      return next;
    });

  // Selecting a folder opens it; clicking the selected, open folder folds it, and again unfolds it.
  const activate = (path: string) => {
    if (path === folder) return toggle(path);
    setFolder(path);
    setExpanded((now) => new Set([...now, path]));
  };

  // From 当前目录内容: select the folder and reveal it in the tree.
  const openFolder = (path: string) => {
    setFolder(path);
    setExpanded((now) => new Set([...now, ...ancestors(path)]));
  };

  // The last note clicked wins, however long saving the current one takes.
  const requested = useRef(note);
  const openNote = async (path: string) => {
    requested.current = path;
    if (path === note || !(await saveFirst())) return;
    if (requested.current === path) setNote(path);
  };

  // The input saved as a copy beside its note: shown where it lies, and opened.
  const openCopy = (path: string) => {
    openFolder(path.slice(0, Math.max(0, path.lastIndexOf("/"))));
    void openNote(path);
  };

  const title = folder ? (folder.split("/").pop() ?? folder) : library.name;

  return (
    <div className="app">
      <aside className="side">
        <div className="drag" />
        <div className="side-label">文件夹</div>
        <FolderTree libraryName={library.name} selected={folder} expanded={expanded} onActivate={activate} onToggle={toggle} />
        <button className="side-foot" onClick={onSwitch} title="切换笔记库" aria-label="切换笔记库">
          <HardDrives size={icon.small} />
          <span className="label">{library.name}</span>
          <CaretUpDown size={icon.caret} />
        </button>
      </aside>
      <section className="list">
        <FolderContentsList folder={folder} title={title} openNote={note} onOpenFolder={openFolder} onOpenNote={(path) => void openNote(path)} />
      </section>
      <main className="card-wrap">
        <NoteEditor path={note} onOpenCopy={openCopy} onLetGo={letGo} />
      </main>
    </div>
  );
}
