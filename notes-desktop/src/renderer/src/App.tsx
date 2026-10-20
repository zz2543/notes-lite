import { ArrowCounterClockwise, CaretUpDown, HardDrives, MagnifyingGlass } from "@phosphor-icons/react";
import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import type { SearchHit } from "../../core";
import type { LaunchState, LibraryInfo, Place } from "../../shared/api";
import { FolderContentsList } from "./FolderContentsList";
import { FolderTree } from "./FolderTree";
import { isSearchShortcut, SearchHead, SearchResultsList, searchShortcut, startSearch, useSearch, type SearchState } from "./InlineSearch";
import { errorText, pageShown } from "./ipc";
import { useFolderFallback } from "./libraryChanges";
import { NoteEditor } from "./NoteEditor";
import { saveOpenNote, useOpenNoteFollowsDisk } from "./noteDraft";
import { listenForSourceView } from "./sourceView";
import { useOrganize } from "./Organize";
import { SpaceContents, SpaceHome, useSpace } from "./SpacePage";
import { SidePages, SideSwitch, SpacePanel, type SideMode } from "./Spaces";
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
    // A window closed on macOS is only hidden; shown again, typing goes on where it was, though
    // the system may have moved focus to the first control meanwhile.
    let focused: Element | null = null;
    const offClose = window.notes.onBeforeClose(() => {
      focused = document.activeElement;
      return saveOpenNote();
    });
    const offShown = window.notes.onShownAgain(() => {
      if (focused instanceof HTMLElement && focused.isConnected) focused.focus({ preventScroll: true });
    });
    const offSourceView = listenForSourceView();
    return () => {
      offSourceView();
      offMenu();
      offClose();
      offShown();
    };
  }, []);

  return (
    <>
      {/* Until the remembered library answers, the window shows only its own color: no spinner. */}
      {phase.kind === "welcome" && <Welcome missing={phase.missing} onChoose={choose} />}
      {phase.kind === "open" && (
        <LibraryView key={phase.library.root} library={phase.library} place={phase.place} onSwitch={choose} saveFirst={saveFirst} notify={setError} />
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
  useEffect(pageShown, []);
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
  /** Where the user last was in this library; the root with no note open when absent. */
  place?: Place;
  onSwitch(): void;
  /** Saves the open note; false when it could not, so the note must stay open. */
  saveFirst(): Promise<boolean>;
  /** Shows a passing notice, such as why a note could not be moved to the trash. */
  notify(message: string): void;
}

function LibraryView({ library, place, onSwitch, saveFirst, notify }: LibraryViewProps) {
  const [folder, setFolder] = useState(place?.folder ?? "");
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(() => new Set(ancestors(place?.folder ?? "")));
  const [note, setNote] = useState<string | null>(place?.note ?? null);

  // The next launch reopens this folder and note.
  useEffect(() => window.notes.rememberPlace({ folder, note }), [folder, note]);
  // The last note clicked wins, however long saving the current one takes.
  const requested = useRef(note);
  // Other programs may move, delete or rewrite what is shown.
  useFolderFallback(folder, setFolder);
  // `path`: the note the disk let go of. A note this app just renamed, moved or closed is not
  // closed again by the watcher's late word about where it used to be.
  const letGo = (reason: string, path?: string) => {
    if (path !== undefined && requested.current !== path) return;
    requested.current = null;
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

  // Opens a note once the open one is saved; true once it is open.
  const openNote = async (path: string): Promise<boolean> => {
    requested.current = path;
    if (path === note) return true;
    if (!(await saveFirst()) || requested.current !== path) return false;
    showNote(path);
    return true;
  };

  // 整理笔记与文件夹: a new note opens ready to type; a note rewritten on disk is read again.
  // The note reopened at launch also waits with the caret at its end, ready to carry on typing.
  const [fresh, setFresh] = useState<string | null>(place?.note ?? null);
  const [reloads, setReloads] = useState(0);
  const showNote = (path: string | null, how: { fresh?: boolean; reload?: boolean } = {}) => {
    requested.current = path;
    setNote(path);
    setFresh(how.fresh ? path : null);
    if (how.reload) setReloads((n) => n + 1);
  };
  const relocated = (from: string, to: string) => {
    const remap = (path: string) => (path === from || path.startsWith(`${from}/`) ? to + path.slice(from.length) : path);
    setFolder(remap);
    setExpanded((now) => new Set([...now].map(remap)));
    requested.current = requested.current && remap(requested.current);
    setNote((now) => now && remap(now));
  };
  const organize = useOrganize({ libraryName: library.name, folder, note, saveFirst, notify, showFolder: openFolder, showNote, relocated });
  const lastDeletedName = organize.lastDeleted?.split("/").pop()?.replace(/\.md$/i, "");

  // The input saved as a copy beside its note: shown where it lies, and opened.
  const openCopy = (path: string) => {
    openFolder(path.slice(0, Math.max(0, path.lastIndexOf("/"))));
    void openNote(path);
  };

  const title = folder ? (folder.split("/").pop() ?? folder) : library.name;

  // “资料库 | 空间”. An open space shows its notes in the middle and its homepage on the card,
  // until one of its notes is chosen; 主页 brings the homepage back.
  const [sideMode, setSideMode] = useState<SideMode>("library");
  const [space, setSpace] = useState<string | null>(null);
  const [showingHome, setShowingHome] = useState(true);
  const openSpace = useSpace(space);
  const inSpace = sideMode === "spaces" && openSpace ? openSpace : null;
  const goHome = async () => {
    if (await saveFirst()) setShowingHome(true);
  };
  const selectSpace = (name: string | null) => {
    setSpace(name);
    if (name !== null) void goHome();
  };
  const openSpaceNote = async (path: string) => {
    if (await openNote(path)) setShowingHome(false);
  };
  // Said once the library opens, such as the old app's spaces failing to move into `.notes/`.
  useEffect(() => {
    if (library.notice) notify(library.notice);
  }, [library]);

  // 就地搜索: the list header turns into the search field; results stand in for the list.
  const [search, setSearch] = useState<SearchState | null>(null);
  const [focusRequest, setFocusRequest] = useState(0);
  const answer = useSearch(search?.query ?? "", search?.scope === "folder" ? folder : undefined);
  const openSearch = () => {
    setSearch((now) => now ?? startSearch);
    setFocusRequest((n) => n + 1);
  };
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!isSearchShortcut(event)) return;
      event.preventDefault();
      openSearch();
    };
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, []);
  // A result opens in its own folder, as if reached by browsing; the search is done.
  const openResult = async (hit: SearchHit) => {
    if (!(await openNote(hit.path))) return;
    openFolder(hit.folder);
    setSearch(null);
  };
  const closeOnEscape = (event: ReactKeyboardEvent) => {
    if (search && event.key === "Escape" && !event.nativeEvent.isComposing) setSearch(null);
  };
  const firstHit = answer?.query === search?.query ? answer?.results?.hits[0] : undefined;

  return (
    <div className="app">
      <aside className="side">
        <div className="drag" />
        <SideSwitch mode={sideMode} onChange={setSideMode} />
        <SidePages mode={sideMode}>
          {sideMode === "library" ? (
            <>
              <div className="side-label">
                <span className="label">文件夹</span>
                <button className="icon-button small" onClick={openSearch} aria-label="搜索" title={`搜索 ${searchShortcut}`}>
                  <MagnifyingGlass size={icon.small} />
                </button>
              </div>
              <FolderTree
                libraryName={library.name}
                selected={folder}
                expanded={expanded}
                onActivate={activate}
                onToggle={toggle}
                onNewNote={(path) => void organize.newNote(path)}
                onMenu={organize.folderMenu}
              />
              {lastDeletedName !== undefined && (
                <button className="side-foot side-restore" onClick={() => void organize.restore()} title={`恢复“${lastDeletedName}”`}>
                  <ArrowCounterClockwise size={icon.small} />
                  <span className="label">恢复上次删除</span>
                </button>
              )}
            </>
          ) : (
            <SpacePanel libraryName={library.name} selected={space} onSelect={selectSpace} notify={notify} />
          )}
        </SidePages>
        <button className="side-foot" onClick={onSwitch} title="切换笔记库" aria-label="切换笔记库">
          <HardDrives size={icon.small} />
          <span className="label">{library.name}</span>
          <CaretUpDown size={icon.caret} />
        </button>
      </aside>
      <section className="list" onKeyDown={closeOnEscape}>
        {inSpace ? (
          <SpaceContents
            space={inSpace}
            showingHome={showingHome}
            openNote={note}
            onHome={() => void goHome()}
            onOpenNote={(path) => void openSpaceNote(path)}
          />
        ) : (
          <>
            {search && (
              <SearchHead
                state={search}
                folderName={title}
                focusRequest={focusRequest}
                onChange={setSearch}
                onSubmit={() => firstHit && void openResult(firstHit)}
                onClose={() => setSearch(null)}
              />
            )}
            {search?.query ? (
              <SearchResultsList answer={answer} libraryName={library.name} openNote={note} onOpen={(hit) => void openResult(hit)} />
            ) : (
              <FolderContentsList
                folder={folder}
                title={search ? null : title}
                openNote={note}
                onOpenFolder={openFolder}
                onOpenNote={(path) => void openNote(path)}
                onMenu={organize.itemMenu}
              />
            )}
          </>
        )}
      </section>
      <main className="card-wrap">
        {inSpace && showingHome ? (
          <SpaceHome space={inSpace} notify={notify} />
        ) : (
          <NoteEditor key={reloads} path={note} fresh={note !== null && note === fresh} onOpenCopy={openCopy} onLetGo={letGo} />
        )}
      </main>
      {organize.overlay}
    </div>
  );
}
