import { DotsThree, Folder } from "@phosphor-icons/react";
import { useState, type MouseEvent } from "react";
import type { NoteEntry } from "../../core";
import { useFolder, useSummaries } from "./ipc";
import { listDate, listDetails } from "./listDetail";
import { ContextMenu, type Menu } from "./Organize";
import { usePreferences } from "./preferences";
import { SelectionPill } from "./SelectionPill";
import { icon } from "./tokens";

/** A note or folder shown in 当前目录内容. */
export interface ListedItem {
  path: string;
  name: string;
  kind: "note" | "folder";
}

interface Props {
  folder: string;
  /** Null while the search field stands in for the header. */
  title: string | null;
  openNote: string | null;
  onOpenFolder(path: string): void;
  onOpenNote(path: string): void;
  /** An item was right-clicked: its menu. */
  onMenu?(item: ListedItem, event: MouseEvent): void;
}

/**
 * 当前目录内容: the selected folder's direct subfolders, then its direct notes. Notes show as much as
 * 笔记列表详细程度 asks: 简洁 the title, 标准 a muted date too, 详细 a one-line summary as well.
 */
export function FolderContentsList({ folder, title, openNote, onOpenFolder, onOpenNote, onMenu }: Props) {
  const { preferences, change } = usePreferences();
  const detail = preferences.listDetail;
  const { value: contents, error } = useFolder(folder);
  const { value: summaries } = useSummaries(folder, detail === "detailed");
  const [listMenu, setListMenu] = useState<Menu>();
  const empty = contents && contents.folders.length === 0 && contents.notes.length === 0;
  const menu = (item: ListedItem) => (event: MouseEvent) => {
    event.preventDefault();
    onMenu?.(item, event);
  };
  // The “…” menu offers the same choice as the settings panel; either one changes both.
  const openListMenu = (event: MouseEvent<HTMLButtonElement>) => {
    const { left, bottom } = event.currentTarget.getBoundingClientRect();
    const items = listDetails.map(({ value, label }) => ({ label, checked: value === detail, run: () => change({ listDetail: value }) }));
    setListMenu({ x: left, y: bottom, items });
  };
  const note = (n: NoteEntry) => (
    <>
      <span className="label">{n.title}</span>
      {detail === "detailed" && summaries?.[n.path] && <span className="summary">{summaries[n.path]}</span>}
      {detail !== "compact" && <span className="date">{listDate(n.modified)}</span>}
    </>
  );
  return (
    <>
      {title !== null && (
        <header className="list-head">
          <h1>{title}</h1>
          <button className="icon-button small" aria-label="列表选项" title="列表选项" aria-haspopup="menu" onClick={openListMenu}>
            <DotsThree size={icon.small} weight="bold" />
          </button>
        </header>
      )}
      {listMenu && <ContextMenu {...listMenu} onClose={() => setListMenu(undefined)} />}
      {error && <p className="empty">{error}</p>}
      {empty && <p className="empty">这个文件夹是空的</p>}
      {contents && !empty && (
        <ul className={`items ${detail}`} aria-label="当前目录内容">
          {contents.folders.map((f) => (
            <li key={f.path}>
              <button className="item" onClick={() => onOpenFolder(f.path)} onContextMenu={menu({ path: f.path, name: f.name, kind: "folder" })}>
                <Folder size={icon.regular} />
                <span className="label">{f.name}</span>
              </button>
            </li>
          ))}
          {contents.notes.map((n) => (
            <li key={n.path}>
              <button
                className={`item note ${openNote === n.path ? "on" : ""}`}
                aria-current={openNote === n.path || undefined}
                onClick={() => onOpenNote(n.path)}
                onContextMenu={menu({ path: n.path, name: n.title, kind: "note" })}
              >
                {openNote === n.path && <SelectionPill group="list" />}
                {note(n)}
              </button>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
