import { Folder } from "@phosphor-icons/react";
import type { MouseEvent } from "react";
import { useFolder } from "./ipc";
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

/** 当前目录内容: the selected folder's direct subfolders, then its direct notes (titles only, the 简洁 level). */
export function FolderContentsList({ folder, title, openNote, onOpenFolder, onOpenNote, onMenu }: Props) {
  const { value: contents, error } = useFolder(folder);
  const empty = contents && contents.folders.length === 0 && contents.notes.length === 0;
  const menu = (item: ListedItem) => (event: MouseEvent) => {
    event.preventDefault();
    onMenu?.(item, event);
  };
  return (
    <>
      {title !== null && (
        <header className="list-head">
          <h1>{title}</h1>
        </header>
      )}
      {error && <p className="empty">{error}</p>}
      {empty && <p className="empty">这个文件夹是空的</p>}
      {contents && !empty && (
        <ul className="items" aria-label="当前目录内容">
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
                className={`item ${openNote === n.path ? "on" : ""}`}
                aria-current={openNote === n.path || undefined}
                onClick={() => onOpenNote(n.path)}
                onContextMenu={menu({ path: n.path, name: n.title, kind: "note" })}
              >
                {openNote === n.path && <SelectionPill group="list" />}
                <span className="label">{n.title}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
