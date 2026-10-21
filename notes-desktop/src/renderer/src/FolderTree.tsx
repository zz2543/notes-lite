import { CaretRight, FileText, Folder, FolderOpen, NotePencil } from "@phosphor-icons/react";
import type { CSSProperties, KeyboardEvent, MouseEvent } from "react";
import type { FolderEntry, NoteEntry } from "../../core";
import { useFolder } from "./ipc";
import { SelectionPill } from "./SelectionPill";
import { icon } from "./tokens";

interface TreeProps {
  libraryName: string;
  selected: string;
  expanded: ReadonlySet<string>;
  /** A row was clicked: select it, or fold it if it is already the selected, open folder. */
  onActivate(path: string): void;
  onToggle(path: string): void;
  /** The new-note icon that appears on a hovered row was clicked. */
  onNewNote?(path: string): void;
  /** A row was right-clicked: its folder's menu. */
  onMenu?(path: string, name: string, event: MouseEvent): void;
  /** 单栏导航: each folder lists its notes after its subfolders. Absent in 双栏导航, where only folders show. */
  notes?: NoteRows;
}

interface NoteRows {
  /** The open note: it alone carries the selection pill. */
  open: string | null;
  onOpen(path: string): void;
  /** A note was right-clicked: its menu. */
  onMenu?(path: string, title: string, event: MouseEvent): void;
}

const canExpand = (folder: FolderEntry, withNotes: boolean) => folder.hasSubfolders || (withNotes && folder.hasNotes);

/**
 * 资料库导航: the library root and its folders, loaded level by level as they are expanded. In 单栏导航
 * the notes join them, so one tree browses the whole library.
 */
export function FolderTree(props: TreeProps) {
  const root = useFolder("");
  const withNotes = props.notes !== undefined;
  const expandable = (root.value?.folders.length ?? 0) > 0 || (withNotes && (root.value?.notes.length ?? 0) > 0);
  return (
    <div className="tree" role="tree" aria-label={withNotes ? "文件夹与笔记" : "文件夹"}>
      <TreeRow {...props} path="" name={props.libraryName} depth={0} expandable={expandable} />
      {props.expanded.has("") && <Subfolders {...props} path="" depth={1} />}
    </div>
  );
}

interface RowProps extends TreeProps {
  path: string;
  name: string;
  depth: number;
  expandable: boolean;
}

function Subfolders(props: TreeProps & { path: string; depth: number }) {
  const { value: contents } = useFolder(props.path);
  const { notes } = props;
  return (
    <>
      {contents?.folders.map((folder) => (
        <Branch
          key={folder.path}
          {...props}
          path={folder.path}
          name={folder.name}
          depth={props.depth}
          expandable={canExpand(folder, notes !== undefined)}
        />
      ))}
      {notes && contents?.notes.map((note) => <NoteRow key={note.path} note={note} depth={props.depth} {...notes} />)}
    </>
  );
}

function NoteRow({ note, depth, open, onOpen, onMenu }: NoteRows & { note: NoteEntry; depth: number }) {
  const isOpen = open === note.path;
  return (
    <div
      className={`row note ${isOpen ? "on" : ""}`}
      role="treeitem"
      aria-label={note.title}
      aria-level={depth + 1}
      aria-selected={isOpen}
      tabIndex={-1}
      style={{ "--depth": depth } as CSSProperties}
      onClick={() => onOpen(note.path)}
      onKeyDown={(event) => {
        if (event.key !== "Enter" && event.key !== " ") return;
        event.preventDefault();
        onOpen(note.path);
      }}
      onContextMenu={(event) => {
        event.preventDefault();
        onMenu?.(note.path, note.title, event);
      }}
    >
      {isOpen && <SelectionPill group="side" />}
      <span className="caret" />
      <FileText size={icon.regular} weight={isOpen ? "fill" : "regular"} />
      <span className="label">{note.title}</span>
    </div>
  );
}

function Branch(props: RowProps) {
  return (
    <>
      <TreeRow {...props} />
      {props.expandable && props.expanded.has(props.path) && <Subfolders {...props} depth={props.depth + 1} />}
    </>
  );
}

// Rows are flat siblings carrying their level, so a row's name and hit area never include its children.
function TreeRow({ path, name, depth, expandable, selected, expanded, onActivate, onToggle, onNewNote, onMenu, notes }: RowProps) {
  const isSelected = selected === path;
  // In 单栏导航 the open note holds the pill; the folder being browsed keeps its open icon.
  const hasPill = isSelected && !notes?.open;
  const isOpen = expandable && expanded.has(path);
  const Icon = isSelected ? FolderOpen : Folder;
  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onActivate(path);
    }
  };
  return (
    <div
      className={`row ${isSelected ? "on" : ""}`}
      role="treeitem"
      aria-label={name}
      aria-level={depth + 1}
      aria-selected={hasPill}
      aria-expanded={expandable ? isOpen : undefined}
      tabIndex={isSelected ? 0 : -1}
      style={{ "--depth": depth } as CSSProperties}
      onClick={() => onActivate(path)}
      onKeyDown={onKeyDown}
      onContextMenu={(event) => {
        event.preventDefault();
        onMenu?.(path, name, event);
      }}
    >
      {hasPill && <SelectionPill group="side" />}
      <span
        className="caret"
        role={expandable ? "button" : undefined}
        aria-label={expandable ? `${isOpen ? "收起" : "展开"}${name}` : undefined}
        aria-hidden={expandable ? undefined : true}
        style={{ visibility: expandable ? "visible" : "hidden" }}
        onClick={(event) => {
          event.stopPropagation();
          onToggle(path);
        }}
      >
        <CaretRight size={icon.caret} weight="bold" />
      </span>
      <Icon size={icon.regular} weight={isSelected ? "fill" : "regular"} />
      <span className="label">{name}</span>
      {onNewNote && (
        <button
          className="row-new"
          aria-label={`在“${name}”中新建笔记`}
          title="新建笔记"
          tabIndex={-1}
          onClick={(event) => {
            event.stopPropagation();
            onNewNote(path);
          }}
        >
          <NotePencil size={icon.small} />
        </button>
      )}
    </div>
  );
}
