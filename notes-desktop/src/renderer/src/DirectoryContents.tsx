import { FileText, Folder } from "@phosphor-icons/react";
import { useFolder } from "./useFolder";

interface Props {
  folder: string;
  title: string;
  openNote: string | null;
  onOpenFolder(path: string): void;
  onOpenNote(path: string): void;
}

/** 当前目录内容: the selected folder's direct subfolders, then its direct notes. */
export function DirectoryContents({ folder, title, openNote, onOpenFolder, onOpenNote }: Props) {
  const { contents, error } = useFolder(folder);
  const empty = contents && contents.folders.length === 0 && contents.notes.length === 0;
  return (
    <>
      <header className="list-head">
        <h1>{title}</h1>
      </header>
      {error && <p className="empty">{error}</p>}
      {empty && <p className="empty">这个文件夹是空的</p>}
      {contents && !empty && (
        <ul className="items" aria-label="当前目录内容">
          {contents.folders.map((f) => (
            <li key={f.path}>
              <button className="item" onClick={() => onOpenFolder(f.path)}>
                <Folder size={16} />
                <span className="label">{f.name}</span>
              </button>
            </li>
          ))}
          {contents.notes.map((n) => (
            <li key={n.path}>
              <button className={`item ${openNote === n.path ? "on" : ""}`} aria-current={openNote === n.path || undefined} onClick={() => onOpenNote(n.path)}>
                <FileText size={16} weight={openNote === n.path ? "fill" : "regular"} />
                <span className="label">{n.title}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
