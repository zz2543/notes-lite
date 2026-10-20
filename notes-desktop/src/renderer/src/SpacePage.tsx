import { House, ListChecks } from "@phosphor-icons/react";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { LogItem, SpaceInfo, SpaceNote } from "../../shared/api";
import { Dialog, useOverlayOpen } from "./Organize";
import { SelectionPill } from "./SelectionPill";
import { icon } from "./tokens";

// An open space: its notes in the middle column with 主页 pinned on top, and on the card its
// homepage (run by main in a sandbox laid over the card) or, when a note is chosen, the editor.
// The operation log lists what homepages wrote and takes entries back one by one.

const touchesSpaces = (path: string) => path === "" || path === ".notes" || path.startsWith(".notes/空间");

/** The space named `name` as it is now, read again whenever a space file changes. */
export function useSpace(name: string | null): SpaceInfo | null | undefined {
  const [spaces, setSpaces] = useState<SpaceInfo[]>();
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    window.notes.listSpaces().then(
      (listed) => live && setSpaces(listed),
      () => live && setSpaces([]),
    );
    return () => {
      live = false;
    };
  }, [revision]);
  useEffect(() => window.notes.onLibraryChanged((paths) => paths.some(touchesSpaces) && setRevision((n) => n + 1)), []);
  if (name === null) return null;
  return spaces && (spaces.find((space) => space.name === name) ?? null);
}

/** The notes in the space's scope, read again when the library changes. */
function useSpaceNotes(name: string): SpaceNote[] | undefined {
  const [notes, setNotes] = useState<{ name: string; notes: SpaceNote[] }>();
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    void window.notes.spaceNotes(name).then((listed) => live && setNotes({ name, notes: listed.ok ? listed.value : [] }));
    return () => {
      live = false;
    };
  }, [name, revision]);
  useEffect(() => window.notes.onLibraryChanged(() => setRevision((n) => n + 1)), []);
  return notes?.name === name ? notes.notes : undefined;
}

interface SpaceContentsProps {
  space: SpaceInfo;
  showingHome: boolean;
  openNote: string | null;
  onHome(): void;
  onOpenNote(path: string): void;
}

/** The middle column for an open space: 主页, then every note in its scope. */
export function SpaceContents({ space, showingHome, openNote, onHome, onOpenNote }: SpaceContentsProps) {
  const notes = useSpaceNotes(space.name);
  return (
    <>
      <header className="list-head">
        <h1>
          {space.icon && <span aria-hidden>{space.icon} </span>}
          {space.name}
        </h1>
      </header>
      <ul className="items" aria-label="空间内容">
        <li>
          <button className={`item ${showingHome ? "on" : ""}`} aria-current={showingHome || undefined} onClick={onHome}>
            {showingHome && <SelectionPill group="list" />}
            <House size={icon.regular} />
            <span className="label">主页</span>
          </button>
        </li>
        {notes?.map((note) => {
          const on = !showingHome && openNote === note.path;
          return (
            <li key={note.path}>
              <button className={`item ${on ? "on" : ""}`} aria-current={on || undefined} title={note.path} onClick={() => onOpenNote(note.path)}>
                {on && <SelectionPill group="list" />}
                <span className="label">{note.title}</span>
              </button>
            </li>
          );
        })}
      </ul>
      {notes?.length === 0 && <p className="empty">范围内还没有笔记</p>}
    </>
  );
}

interface SpaceHomeProps {
  space: SpaceInfo;
  notify(message: string): void;
}

/** The card while a space's homepage shows: its head, and the place main lays the homepage over. */
export function SpaceHome({ space, notify }: SpaceHomeProps) {
  const [logOpen, setLogOpen] = useState(false);
  const copyPrompt = async () => {
    const copied = await window.notes.copySpacePrompt(space.name);
    notify(copied.ok ? "提示词已复制到剪贴板，粘贴给 Claude Code、Codex 等外部 agent，就能生成空间主页。" : copied.message);
  };
  return (
    <article className="card">
      <header className="card-head">
        <span className="card-path">{space.name} · 主页</span>
        <button className="card-tool" onClick={() => setLogOpen(true)}>
          <ListChecks size={icon.small} />
          操作记录
        </button>
      </header>
      {space.hasPage ? (
        <PageSlot name={space.name} />
      ) : (
        <div className="space-empty space-no-page">
          <p>这个空间还没有主页。</p>
          <button className="primary" onClick={() => void copyPrompt()}>
            让 agent 生成主页
          </button>
          <p>提示词会复制到剪贴板，把它交给外部 agent，主页写好后会显示在这里。</p>
        </div>
      )}
      {logOpen && <OperationLogDialog onClose={() => setLogOpen(false)} notify={notify} />}
    </article>
  );
}

/** Where the homepage goes; main keeps it over this box, and takes it away while a menu or dialog is open. */
function PageSlot({ name }: { name: string }) {
  const slot = useRef<HTMLDivElement>(null);
  const covered = useOverlayOpen();
  useLayoutEffect(() => {
    const box = slot.current;
    if (!box || covered) return window.notes.hideSpacePage();
    const place = () => {
      const { x, y, width, height } = box.getBoundingClientRect();
      window.notes.showSpacePage(name, { x, y, width, height });
    };
    place();
    const watch = new ResizeObserver(place);
    watch.observe(box);
    window.addEventListener("resize", place);
    return () => {
      watch.disconnect();
      window.removeEventListener("resize", place);
      window.notes.hideSpacePage();
    };
  }, [name, covered]);
  return <div ref={slot} className="space-page-slot" aria-label="空间主页" role="region" />;
}

const time = new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });

/** 操作记录: everything homepages wrote in the last 30 days, newest first, each undoable on its own. */
function OperationLogDialog({ onClose, notify }: { onClose(): void; notify(message: string): void }) {
  const [items, setItems] = useState<LogItem[]>();
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    void window.notes.operationLog().then((read) => {
      if (!live) return;
      if (read.ok) setItems(read.value);
      else {
        setItems([]);
        notify(read.message);
      }
    });
    return () => {
      live = false;
    };
  }, [revision]);
  const undo = async (item: LogItem) => {
    const undone = await window.notes.undoOperation(item.id);
    if (!undone.ok) notify(undone.message);
    setRevision((n) => n + 1);
  };
  return (
    <Dialog title="操作记录" onClose={onClose} onSubmit={onClose}>
      <p className="dialog-hint">空间主页的每次写入都记在这里，保留 30 天，可以逐条撤销。</p>
      {items?.length === 0 && <p className="dialog-hint">还没有操作记录。</p>}
      {items && items.length > 0 && (
        <ul className="dialog-list log-list">
          {items.map((item) => (
            <li key={item.id} className={`log-item ${item.undone ? "undone" : ""}`}>
              <div className="log-text">
                <span className="log-summary">{item.summary}</span>
                <span className="log-meta">
                  {item.space} · {time.format(new Date(item.date))}
                  {item.undone && " · 已撤销"}
                </span>
                {item.changes.length > 0 && (
                  <pre className="log-changes">{item.changes.map((change) => `${change.sign} ${change.text}`).join("\n")}</pre>
                )}
              </div>
              {!item.undone && (
                <button type="button" className="secondary" onClick={() => void undo(item)}>
                  撤销
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
      <div className="dialog-buttons">
        <button type="submit" className="primary">
          关闭
        </button>
      </div>
    </Dialog>
  );
}
