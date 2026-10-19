import { CaretUpDown, HardDrives } from "@phosphor-icons/react";
import { useEffect, useState } from "react";
import type { LibraryInfo } from "../../shared/api";
import { DirectoryContents } from "./DirectoryContents";
import { FolderTree } from "./FolderTree";
import { NoteView } from "./NoteView";
import { errorText } from "./useFolder";

type Phase = { kind: "starting" } | { kind: "welcome" } | { kind: "open"; library: LibraryInfo };

export function App() {
  const [phase, setPhase] = useState<Phase>({ kind: "starting" });
  const [error, setError] = useState<string>();

  useEffect(() => {
    void window.notes.currentLibrary().then((library) => setPhase(library ? { kind: "open", library } : { kind: "welcome" }));
    return window.notes.onLibraryChanged((library) => setPhase({ kind: "open", library }));
  }, []);

  const choose = async () => {
    setError(undefined);
    try {
      const library = await window.notes.chooseLibrary();
      if (library) setPhase({ kind: "open", library });
    } catch (e) {
      setError(errorText(e));
    }
  };

  return (
    <>
      {/* Until the remembered library answers, the window shows only its own color: no spinner. */}
      {phase.kind === "welcome" && <Welcome onChoose={choose} />}
      {phase.kind === "open" && <LibraryView key={phase.library.root} library={phase.library} onSwitch={choose} />}
      {error && (
        <div className="toast" role="alert">
          {error}
        </div>
      )}
    </>
  );
}

function Welcome({ onChoose }: { onChoose(): void }) {
  return (
    <main className="welcome">
      <div className="drag" />
      <h1>打开笔记库</h1>
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

function LibraryView({ library, onSwitch }: { library: LibraryInfo; onSwitch(): void }) {
  const [folder, setFolder] = useState("");
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(() => new Set([""]));
  const [note, setNote] = useState<string | null>(null);

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

  const title = folder ? (folder.split("/").pop() ?? folder) : library.name;

  return (
    <div className="app">
      <aside className="side">
        <div className="drag" />
        <div className="side-label">文件夹</div>
        <FolderTree libraryName={library.name} selected={folder} expanded={expanded} onActivate={activate} onToggle={toggle} />
        <button className="side-foot" onClick={onSwitch} title="切换笔记库" aria-label="切换笔记库">
          <HardDrives size={15} />
          <span className="label">{library.name}</span>
          <CaretUpDown size={13} />
        </button>
      </aside>
      <section className="list">
        <DirectoryContents folder={folder} title={title} openNote={note} onOpenFolder={openFolder} onOpenNote={setNote} />
      </section>
      <main className="card-wrap">
        <NoteView path={note} />
      </main>
    </div>
  );
}
