import { CaretRight, Folder } from "@phosphor-icons/react";
import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { SelectedIcon } from "./SelectedIcon";
import { icon } from "./tokens";

// The library's folders as a tree in a dialog (新建空间, 编辑空间, 移动到): folded to the top level, a
// caret opens each, as in the side panel's tree, rather than every folder at once.

const parentOf = (path: string) => path.slice(0, Math.max(0, path.lastIndexOf("/")));
/** `path` is `folder` or inside it. */
const within = (path: string, folder: string) => folder === "" || path === folder || path.startsWith(`${folder}/`);
/** The folders `path` lies in, outermost first, not counting the library itself. */
const ancestors = (path: string) => {
  const parts = path.split("/");
  return parts.slice(0, -1).map((_, i) => parts.slice(0, i + 1).join("/"));
};

/** The tree's open folders: at first those leading to `shown`, so what is chosen can be seen. */
function useOpenFolders(shown: readonly string[]) {
  const [open, setOpen] = useState<ReadonlySet<string>>(() => new Set(shown.flatMap(ancestors)));
  const toggle = (folder: string) =>
    setOpen((now) => {
      const next = new Set(now);
      if (!next.delete(folder)) next.add(folder);
      return next;
    });
  return { open, toggle };
}

/** The folders shown, in the library's order: the top level, and inside each open folder its own. */
function visibleRows(folders: readonly string[], open: ReadonlySet<string>) {
  const parents = new Set(folders.map(parentOf));
  return folders
    .filter((folder) => folder !== "" && ancestors(folder).every((a) => open.has(a)))
    .map((folder) => ({ folder, depth: folder.split("/").length, branch: parents.has(folder) }));
}

function Caret({ folder, branch, open, onToggle }: { folder: string; branch: boolean; open: boolean; onToggle(): void }) {
  if (!branch) return <span className="picker-caret" aria-hidden />;
  const name = folder.split("/").at(-1);
  return (
    <button
      type="button"
      className={`picker-caret ${open ? "open" : ""}`}
      aria-label={`${open ? "收起" : "展开"}“${name}”`}
      aria-expanded={open}
      onClick={(event) => {
        event.preventDefault();
        onToggle();
      }}
    >
      <CaretRight size={icon.caret} weight="bold" aria-hidden />
    </button>
  );
}

interface ChecklistProps {
  folders: readonly string[];
  /** The folders ticked; each one takes in the folders inside it. */
  chosen: ReadonlySet<string>;
  onChange(chosen: ReadonlySet<string>): void;
  label: string;
  empty?: ReactNode;
}

/**
 * 新建空间 / 编辑空间's scope. A folder ticked takes in everything inside it, so its subfolders show
 * ticked too (and wait until it is unticked); one with only some folders inside ticked shows a dash.
 */
export function FolderChecklist({ folders, chosen, onChange, label, empty }: ChecklistProps) {
  const { open, toggle } = useOpenFolders([...chosen]);
  const coveredBy = (folder: string) => ancestors(folder).find((a) => chosen.has(a));
  const partly = (folder: string) => !chosen.has(folder) && [...chosen].some((c) => c !== folder && within(c, folder));
  const tick = (folder: string) => {
    const next = new Set(chosen);
    if (next.has(folder)) next.delete(folder);
    else {
      // Taken in by it now, the folders inside need not be listed.
      for (const c of chosen) if (within(c, folder)) next.delete(c);
      next.add(folder);
    }
    onChange(next);
  };
  return (
    <div className="dialog-list space-folders" role="group" aria-label={label}>
      {visibleRows(folders, open).map(({ folder, depth, branch }) => {
        const parts = folder.split("/");
        const cover = coveredBy(folder);
        return (
          <div key={folder} className="picker-row" style={{ "--depth": depth - 1 } as CSSProperties}>
            <Caret folder={folder} branch={branch} open={open.has(folder)} onToggle={() => toggle(folder)} />
            <label className="space-check" title={cover ? `已包含在“${cover.split("/").at(-1)}”中` : folder}>
              <PartlyBox
                aria-label={parts.join(" / ")}
                checked={chosen.has(folder) || cover !== undefined}
                partly={partly(folder)}
                disabled={cover !== undefined}
                onChange={() => tick(folder)}
              />
              <span className="label">{parts.at(-1)}</span>
            </label>
          </div>
        );
      })}
      {folders.length === 0 && empty}
    </div>
  );
}

function PartlyBox({ partly, ...props }: { partly: boolean; checked: boolean; disabled: boolean; onChange(): void; "aria-label": string }) {
  const box = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (box.current) box.current.indeterminate = partly && !props.checked;
  }, [partly, props.checked]);
  return <input ref={box} type="checkbox" aria-checked={partly && !props.checked ? "mixed" : props.checked} {...props} />;
}

interface ChooserProps {
  folders: readonly string[];
  libraryName: string;
  /** Where the item lies now: the tree opens to it. */
  near: string;
  chosen: string | undefined;
  allowed(folder: string): boolean;
  onChoose(folder: string): void;
  onConfirm(folder: string): void;
}

/** 移动到…'s target: one folder, the library itself on top, the tree open to where the item lies. */
export function FolderChooser({ folders, libraryName, near, chosen, allowed, onChoose, onConfirm }: ChooserProps) {
  const { open, toggle } = useOpenFolders(near ? [`${near}/`] : []);
  const option = (folder: string, depth: number, branch: boolean) => {
    const parts = folder ? folder.split("/") : [];
    return (
      <div key={folder} className="picker-row" style={{ "--depth": depth } as CSSProperties}>
        {folder ? <Caret folder={folder} branch={branch} open={open.has(folder)} onToggle={() => toggle(folder)} /> : <span className="picker-caret" aria-hidden />}
        <button
          type="button"
          role="option"
          className="dialog-option"
          aria-label={folder ? parts.join(" / ") : libraryName}
          aria-selected={chosen === folder}
          disabled={!allowed(folder)}
          onClick={() => onChoose(folder)}
          onDoubleClick={() => onConfirm(folder)}
        >
          <SelectedIcon off={Folder} selected={chosen === folder} />
          <span className="label">{parts.at(-1) ?? libraryName}</span>
        </button>
      </div>
    );
  };
  return (
    <div className="dialog-list" role="listbox" aria-label="目标文件夹">
      {option("", 0, false)}
      {visibleRows(folders, open).map(({ folder, depth, branch }) => option(folder, depth, branch))}
    </div>
  );
}
