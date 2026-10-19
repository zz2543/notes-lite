import { CaretRight, Folder, FolderOpen } from "@phosphor-icons/react";
import type { KeyboardEvent } from "react";
import { useFolder } from "./useFolder";

interface TreeProps {
  libraryName: string;
  selected: string;
  expanded: ReadonlySet<string>;
  /** A row was clicked: select it, or fold it if it is already the selected, open folder. */
  onActivate(path: string): void;
  onToggle(path: string): void;
}

/** 资料库导航: the library root and its folders, loaded level by level as they are expanded. */
export function FolderTree(props: TreeProps) {
  const root = useFolder("");
  return (
    <div className="tree" role="tree" aria-label="文件夹">
      <TreeRow {...props} path="" name={props.libraryName} depth={0} expandable={(root.contents?.folders.length ?? 0) > 0} />
      {props.expanded.has("") && <Subfolders {...props} path="" depth={1} />}
    </div>
  );
}

function Subfolders(props: TreeProps & { path: string; depth: number }) {
  const { contents } = useFolder(props.path);
  return contents?.folders.map((folder) => (
    <Branch key={folder.path} {...props} path={folder.path} name={folder.name} depth={props.depth} expandable={folder.hasSubfolders} />
  ));
}

function Branch(props: TreeProps & { path: string; name: string; depth: number; expandable: boolean }) {
  return (
    <>
      <TreeRow {...props} />
      {props.expandable && props.expanded.has(props.path) && <Subfolders {...props} depth={props.depth + 1} />}
    </>
  );
}

// Rows are flat siblings carrying their level, so a row's name and hit area never include its children.
function TreeRow({ path, name, depth, expandable, selected, expanded, onActivate, onToggle }: TreeProps & { path: string; name: string; depth: number; expandable: boolean }) {
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
      style={{ paddingLeft: 10 + depth * 16 }}
      onClick={() => onActivate(path)}
      onKeyDown={onKeyDown}
    >
      <span
        className="caret"
        style={{ visibility: expandable ? "visible" : "hidden" }}
        onClick={(event) => {
          event.stopPropagation();
          onToggle(path);
        }}
      >
        <CaretRight size={11} weight="bold" style={{ transform: isOpen ? "rotate(90deg)" : undefined }} />
      </span>
      <Icon size={17} weight={isSelected ? "fill" : "regular"} />
      <span className="label">{name}</span>
    </div>
  );
}
