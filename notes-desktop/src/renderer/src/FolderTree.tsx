import { CaretRight, Folder, FolderOpen, NotePencil } from "@phosphor-icons/react";
import type { CSSProperties, KeyboardEvent, MouseEvent } from "react";
import { useFolder } from "./ipc";
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
}

/** 资料库导航: the library root and its folders, loaded level by level as they are expanded. */
export function FolderTree(props: TreeProps) {
  const root = useFolder("");
  return (
    <div className="tree" role="tree" aria-label="文件夹">
      <TreeRow {...props} path="" name={props.libraryName} depth={0} expandable={(root.value?.folders.length ?? 0) > 0} />
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
  return contents?.folders.map((folder) => (
    <Branch key={folder.path} {...props} path={folder.path} name={folder.name} depth={props.depth} expandable={folder.hasSubfolders} />
  ));
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
function TreeRow({ path, name, depth, expandable, selected, expanded, onActivate, onToggle, onNewNote, onMenu }: RowProps) {
  const isSelected = selected === path;
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
      aria-selected={isSelected}
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
      <span
        className="caret"
        style={{ visibility: expandable ? "visible" : "hidden" }}
        onClick={(event) => {
          event.stopPropagation();
          onToggle(path);
        }}
      >
        <CaretRight size={icon.caret} weight="bold" style={{ transform: isOpen ? "rotate(90deg)" : undefined }} />
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
