import { Folder } from "@phosphor-icons/react";
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type FormEvent, type KeyboardEvent, type MouseEvent, type ReactNode } from "react";
import type { ListedItem } from "./FolderContentsList";
import { libraryChanged } from "./ipc";
import "./organize.css";
import { icon } from "./tokens";

// 整理笔记与文件夹: the menus, dialogs and steps behind creating, renaming, moving, deleting and
// restoring. The library does the work; this decides what the view shows afterwards.

const parentOf = (path: string) => path.split("/").slice(0, -1).join("/");
const within = (path: string, item: string) => path === item || path.startsWith(`${item}/`);
const isNote = (path: string) => /\.md$/i.test(path);
const mac = navigator.userAgent.includes("Macintosh");

/** What organizing may see and change of the library view. */
export interface OrganizeView {
  libraryName: string;
  /** The selected folder. */
  folder: string;
  /** The open note, if any. */
  note: string | null;
  /** Saves the open note; false (after saying why) when it could not, so nothing should move. */
  saveFirst(): Promise<boolean>;
  notify(message: string): void;
  /** Selects a folder and reveals it in the folder tree. */
  showFolder(path: string): void;
  /** Opens a note, or closes it with null. `fresh`: just created, so typing goes after its title. `reload`: read it again. */
  showNote(path: string | null, how?: { fresh?: boolean; reload?: boolean }): void;
  /** Something moved: whatever the view holds at or under `from` now lives under `to`. */
  relocated(from: string, to: string): void;
}

interface MenuItem {
  label: string;
  run(): void;
}

type Menu = { x: number; y: number; items: Array<MenuItem | "separator"> };

export function useOrganize(view: OrganizeView) {
  // Steps finish after awaits; they act on the view as it is then.
  const live = useRef(view);
  live.current = view;
  const [menu, setMenu] = useState<Menu>();
  const [dialog, setDialog] = useState<ReactNode>();
  const [lastDeleted, setLastDeleted] = useState<string | null>(null);
  const close = () => setDialog(undefined);

  const newNote = async (folder: string) => {
    if (!(await live.current.saveFirst())) return;
    const created = await window.notes.createNote(folder);
    if (!created.ok) return live.current.notify(created.message);
    libraryChanged();
    live.current.showFolder(folder);
    live.current.showNote(created.value, { fresh: true });
  };

  // ⌘N / Ctrl+N creates in the current folder. The page sees the keys before the menu does and
  // keeps them, so the menu's 新建笔记 only answers to being chosen.
  useEffect(() => {
    const onKeyDown = (event: globalThis.KeyboardEvent) => {
      const command = mac ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey;
      if (event.code !== "KeyN" || !command || event.shiftKey || event.altKey || event.isComposing) return;
      event.preventDefault();
      void newNote(live.current.folder);
    };
    window.addEventListener("keydown", onKeyDown);
    const offMenu = window.notes.onNewNoteRequest(() => void newNote(live.current.folder));
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      offMenu();
    };
  }, []);

  const newFolder = (parent: string) =>
    setDialog(
      <NameDialog
        title="新建文件夹"
        hint={`位置：${parent || live.current.libraryName}`}
        initial=""
        confirm="新建"
        onClose={close}
        onSubmit={async (name) => {
          const created = await window.notes.createFolder(parent, name);
          if (!created.ok) return created.message;
          libraryChanged();
          live.current.showFolder(created.value);
        }}
      />,
    );

  /** After a rename or move: the view follows, and an open note whose links changed is read again. */
  const followed = (from: string, to: string, updated: string[]) => {
    libraryChanged();
    const { note } = live.current;
    live.current.relocated(from, to);
    const open = note && within(note, from) ? to + note.slice(from.length) : note;
    if (open && updated.includes(open)) live.current.showNote(open, { reload: true });
  };

  const rename = (item: ListedItem) =>
    setDialog(
      <NameDialog
        title={item.kind === "note" ? "重命名笔记" : "重命名文件夹"}
        initial={item.name}
        confirm="重命名"
        onClose={close}
        onSubmit={async (name) => {
          const renamed = await window.notes.rename(item.path, name);
          if (!renamed.ok) return renamed.message;
          followed(item.path, renamed.value.path, renamed.value.updated);
        }}
      />,
    );

  const move = (item: ListedItem) =>
    setDialog(
      <MoveDialog
        item={item}
        libraryName={live.current.libraryName}
        onClose={close}
        onSubmit={async (folder) => {
          const moved = await window.notes.move(item.path, folder);
          if (!moved.ok) return moved.message;
          const wasOpen = live.current.note === item.path;
          followed(item.path, moved.value.path, moved.value.updated);
          // The open note moved: its new folder comes into view with it.
          if (wasOpen) live.current.showFolder(folder);
        }}
      />,
    );

  const trash = async (item: ListedItem) => {
    const deleted = await window.notes.trash(item.path);
    if (!deleted.ok) return live.current.notify(deleted.message);
    libraryChanged();
    setLastDeleted(item.path);
    const { note, folder } = live.current;
    if (note && within(note, item.path)) live.current.showNote(null);
    if (item.kind === "folder" && within(folder, item.path)) live.current.showFolder(parentOf(item.path));
  };

  const restore = async () => {
    if (!(await live.current.saveFirst())) return;
    const restored = await window.notes.restoreLastDeleted();
    if (!restored.ok) return live.current.notify(restored.message);
    libraryChanged();
    setLastDeleted(null);
    const path = restored.value;
    live.current.showFolder(isNote(path) ? parentOf(path) : path);
    if (isNote(path)) live.current.showNote(path);
  };

  // Anything that moves or removes an item saves the open note first.
  const saved = (step: () => unknown) => async () => {
    if (await live.current.saveFirst()) step();
  };

  const openMenu = (event: MouseEvent, items: Menu["items"]) => setMenu({ x: event.clientX, y: event.clientY, items });

  const itemMenu = (item: ListedItem, event: MouseEvent) => {
    const changes: Menu["items"] = [
      { label: "重命名…", run: saved(() => rename(item)) },
      { label: "移动到…", run: saved(() => move(item)) },
      "separator",
      { label: "移到废纸篓", run: saved(() => trash(item)) },
    ];
    if (item.kind === "note") return openMenu(event, changes);
    openMenu(event, [
      { label: "新建笔记", run: () => void newNote(item.path) },
      { label: "新建文件夹…", run: () => newFolder(item.path) },
      // The library folder itself stays where it is.
      ...(item.path ? (["separator", ...changes] as const) : []),
    ]);
  };

  const folderMenu = (path: string, name: string, event: MouseEvent) => itemMenu({ path, name, kind: "folder" }, event);

  const overlay = (
    <>
      {menu && <ContextMenu {...menu} onClose={() => setMenu(undefined)} />}
      {dialog}
    </>
  );

  return { newNote, itemMenu, folderMenu, restore, lastDeleted, overlay };
}

function ContextMenu({ x, y, items, onClose }: Menu & { onClose(): void }) {
  const ref = useRef<HTMLDivElement>(null);
  const [place, setPlace] = useState({ left: x, top: y });

  // Kept inside the window, opening up or to the left when there is no room below or right.
  useLayoutEffect(() => {
    const menu = ref.current!;
    const { width, height } = menu.getBoundingClientRect();
    setPlace({ left: x + width > innerWidth ? Math.max(0, x - width) : x, top: y + height > innerHeight ? Math.max(0, y - height) : y });
    menu.querySelector<HTMLElement>("[role=menuitem]")?.focus();
  }, [x, y]);

  useEffect(() => {
    const outside = (event: PointerEvent) => !ref.current?.contains(event.target as Node) && onClose();
    window.addEventListener("pointerdown", outside, true);
    window.addEventListener("blur", onClose);
    window.addEventListener("resize", onClose);
    return () => {
      window.removeEventListener("pointerdown", outside, true);
      window.removeEventListener("blur", onClose);
      window.removeEventListener("resize", onClose);
    };
  }, [onClose]);

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === "Escape") return onClose();
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    const all = [...ref.current!.querySelectorAll<HTMLElement>("[role=menuitem]")];
    const at = all.indexOf(document.activeElement as HTMLElement);
    all[(at + (event.key === "ArrowDown" ? 1 : all.length - 1)) % all.length]?.focus();
  };

  return (
    <div ref={ref} className="menu" role="menu" style={place} onKeyDown={onKeyDown} onContextMenu={(event) => event.preventDefault()}>
      {items.map((item, index) =>
        item === "separator" ? (
          <div key={index} className="menu-separator" role="separator" />
        ) : (
          <button
            key={item.label}
            className="menu-item"
            role="menuitem"
            onClick={() => {
              onClose();
              item.run();
            }}
          >
            {item.label}
          </button>
        ),
      )}
    </div>
  );
}

interface DialogProps {
  onClose(): void;
}

/** A floating panel over a dimmed window: Esc or a click outside closes it. */
function Dialog({ title, onClose, onSubmit, children }: DialogProps & { title: string; onSubmit(event: FormEvent): void; children: ReactNode }) {
  return (
    <div className="scrim" onPointerDown={(event) => event.target === event.currentTarget && onClose()}>
      <form
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit(event);
        }}
        onKeyDown={(event) => event.key === "Escape" && onClose()}
      >
        <h2>{title}</h2>
        {children}
      </form>
    </div>
  );
}

/** Runs a step that answers with what went wrong, if anything; while it runs, the dialog waits. */
function useStep(onClose: () => void) {
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  const run = async (step: () => Promise<string | void>) => {
    if (busy) return;
    setBusy(true);
    const problem = await step().catch((e: Error) => e.message);
    setBusy(false);
    if (problem) setError(problem);
    else onClose();
  };
  return { error, setError, busy, run };
}

interface NameDialogProps extends DialogProps {
  title: string;
  hint?: string;
  initial: string;
  confirm: string;
  /** Answers with why the name was refused; the dialog then stays open. */
  onSubmit(name: string): Promise<string | void>;
}

function NameDialog({ title, hint, initial, confirm, onSubmit, onClose }: NameDialogProps) {
  const [name, setName] = useState(initial);
  const { error, setError, busy, run } = useStep(onClose);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => input.current?.select(), []);
  return (
    <Dialog title={title} onClose={onClose} onSubmit={() => void run(() => onSubmit(name))}>
      {hint && <p className="dialog-hint">{hint}</p>}
      <input
        ref={input}
        className="dialog-input"
        aria-label="名称"
        value={name}
        spellCheck={false}
        onChange={(event) => {
          setName(event.target.value);
          setError(undefined);
        }}
      />
      {error && (
        <p className="dialog-error" role="alert">
          {error}
        </p>
      )}
      <div className="dialog-buttons">
        <button type="button" className="secondary" onClick={onClose}>
          取消
        </button>
        <button type="submit" className="primary" disabled={busy}>
          {confirm}
        </button>
      </div>
    </Dialog>
  );
}

interface MoveDialogProps extends DialogProps {
  item: ListedItem;
  libraryName: string;
  onSubmit(folder: string): Promise<string | void>;
}

function MoveDialog({ item, libraryName, onSubmit, onClose }: MoveDialogProps) {
  const [folders, setFolders] = useState<string[]>();
  const [target, setTarget] = useState<string>();
  const { error, busy, run } = useStep(onClose);
  useEffect(() => {
    window.notes.listFolders().then(setFolders, () => setFolders([]));
  }, []);
  // Where it is now, and (for a folder) inside itself, are no place to move to.
  const allowed = (folder: string) => folder !== parentOf(item.path) && !(item.kind === "folder" && within(folder, item.path));
  const submit = (folder = target) => folder !== undefined && void run(() => onSubmit(folder));
  return (
    <Dialog title={`移动“${item.name}”`} onClose={onClose} onSubmit={() => submit()}>
      <div className="dialog-list" role="listbox" aria-label="目标文件夹">
        {folders &&
          ["", ...folders].map((folder) => {
            const parts = folder ? folder.split("/") : [];
            return (
              <button
                type="button"
                key={folder}
                role="option"
                className="dialog-option"
                aria-label={folder ? parts.join(" / ") : libraryName}
                aria-selected={target === folder}
                disabled={!allowed(folder)}
                style={{ "--depth": parts.length } as CSSProperties}
                onClick={() => setTarget(folder)}
                onDoubleClick={() => submit(folder)}
              >
                <Folder size={icon.regular} weight={target === folder ? "fill" : "regular"} />
                <span className="label">{parts.at(-1) ?? libraryName}</span>
              </button>
            );
          })}
      </div>
      {error && (
        <p className="dialog-error" role="alert">
          {error}
        </p>
      )}
      <div className="dialog-buttons">
        <button type="button" className="secondary" onClick={onClose}>
          取消
        </button>
        <button type="submit" className="primary" disabled={busy || target === undefined}>
          移动
        </button>
      </div>
    </Dialog>
  );
}
