import { Check, Folder } from "@phosphor-icons/react";
import { AnimatePresence, motion, useIsPresent } from "motion/react";
import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore, type CSSProperties, type FormEvent, type KeyboardEvent, type MouseEvent, type ReactNode } from "react";
import type { ListedItem } from "./FolderContentsList";
import { createPortal } from "react-dom";
import { openDialogs } from "./dialogs";
import { FolderChooser } from "./FolderPicker";
import { libraryChanged } from "./ipc";
import { useMotion } from "./MotionProvider";
import "./organize.css";
import { icon } from "./tokens";
import { SelectedIcon } from "./SelectedIcon";

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

export interface MenuItem {
  label: string;
  run(): void;
  /** Set for one of a set of choices (a menuitemradio): whether it is the current one. */
  checked?: boolean;
}

export type Menu = { x: number; y: number; items: Array<MenuItem | "separator"> };

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

  /** The open note renamed from its title above its text: by the same rules as 重命名…, saved first. */
  const renameNote = async (path: string, name: string): Promise<string | undefined> => {
    if (!(await live.current.saveFirst())) return "笔记还没有保存，暂时不能重命名。";
    const renamed = await window.notes.rename(path, name);
    if (!renamed.ok) return renamed.message;
    followed(path, renamed.value.path, renamed.value.updated);
  };

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
      <AnimatePresence>{dialog}</AnimatePresence>
    </>
  );

  return { newNote, newFolder, renameNote, itemMenu, folderMenu, restore, lastDeleted, overlay };
}

// Menus and dialogs float over the whole window. A space homepage is laid over the card by main,
// above anything this page draws, so it steps aside while one is open.
let overlays = 0;
const overlayListeners = new Set<() => void>();
const subscribeOverlays = (listener: () => void) => {
  overlayListeners.add(listener);
  return () => overlayListeners.delete(listener);
};

/** Marks a menu or dialog open for as long as the calling component is shown. */
export function useOverlay() {
  useLayoutEffect(() => {
    overlays += 1;
    overlayListeners.forEach((listener) => listener());
    return () => {
      overlays -= 1;
      overlayListeners.forEach((listener) => listener());
    };
  }, []);
}

/** Whether a menu or dialog is open anywhere in the window. */
export function useOverlayOpen(): boolean {
  return useSyncExternalStore(subscribeOverlays, () => overlays > 0);
}

const menuItemSelector = "[role=menuitem], [role=menuitemradio]";

/** A menu at a point: the right-click menus, and the list's “…” menu. */
export function ContextMenu({ x, y, items, onClose }: Menu & { onClose(): void }) {
  useOverlay();
  const ref = useRef<HTMLDivElement>(null);
  const [place, setPlace] = useState({ left: x, top: y, transformOrigin: "left top" });

  // Kept inside the window, opening up or to the left when there is no room below or right; it grows
  // from the corner at the pointer.
  useLayoutEffect(() => {
    const menu = ref.current!;
    // Its layout size: on screen it is still scaled down as it grows in.
    const { offsetWidth: width, offsetHeight: height } = menu;
    const left = x + width > innerWidth;
    const up = y + height > innerHeight;
    const at = { left: left ? Math.max(0, x - width) : x, top: up ? Math.max(0, y - height) : y };
    setPlace({ ...at, transformOrigin: `${x - at.left}px ${y - at.top}px` });
    (menu.querySelector<HTMLElement>("[aria-checked=true]") ?? menu.querySelector<HTMLElement>(menuItemSelector))?.focus();
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
    const all = [...ref.current!.querySelectorAll<HTMLElement>(menuItemSelector)];
    const at = all.indexOf(document.activeElement as HTMLElement);
    all[(at + (event.key === "ArrowDown" ? 1 : all.length - 1)) % all.length]?.focus();
  };

  // On the page itself, not inside the panel that opened it: a panel with a filter, a transform or a fade
  // would stop the menu's frosted glass from seeing (and blurring) what lies behind it.
  return createPortal(
    <div ref={ref} className="menu" role="menu" style={place} onKeyDown={onKeyDown} onContextMenu={(event) => event.preventDefault()}>
      {items.map((item, index) =>
        item === "separator" ? (
          <div key={index} className="menu-separator" role="separator" />
        ) : (
          <button
            key={item.label}
            className="menu-item"
            {...(item.checked === undefined ? { role: "menuitem" } : { role: "menuitemradio", "aria-checked": item.checked })}
            onClick={() => {
              onClose();
              item.run();
            }}
          >
            {item.checked !== undefined && <span className="menu-check">{item.checked && <Check size={icon.small} weight="bold" />}</span>}
            {item.label}
          </button>
        ),
      )}
    </div>,
    document.body,
  );
}

interface DialogProps {
  onClose(): void;
}


/** A floating panel over a dimmed window: Esc or a click outside closes it. */
export function Dialog({ title, onClose, onSubmit, children }: DialogProps & { title: string; onSubmit(event: FormEvent): void; children: ReactNode }) {
  useOverlay();
  const form = useRef<HTMLFormElement>(null);
  const closing = useRef(onClose);
  closing.current = onClose;
  useEffect(() => {
    const entry = { close: () => closing.current() };
    openDialogs.push(entry);
    // Opened from a menu, nothing in it has the focus yet: it takes it, so Esc and Tab start here.
    if (!form.current?.contains(document.activeElement)) form.current?.focus();
    const keys = (event: globalThis.KeyboardEvent) => {
      if (openDialogs.at(-1) !== entry) return;
      if (event.key === "Escape" && !event.isComposing) {
        event.preventDefault();
        event.stopPropagation();
        entry.close();
      }
    };
    window.addEventListener("keydown", keys, true);
    return () => {
      window.removeEventListener("keydown", keys, true);
      openDialogs.splice(openDialogs.indexOf(entry), 1);
    };
  }, []);
  // 浮现, as the settings panel does: the dialog grows into place out of a blur over a fading scrim, and
  // shrinks away when it closes, inert by then, so nothing waits on it and nothing in it answers twice.
  const { emerge, overlay } = useMotion();
  const present = useIsPresent();
  return (
    <motion.div
      className="scrim"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0, transition: overlay.exit.transition }}
      transition={emerge}
      inert={!present}
      onPointerDown={(event) => event.target === event.currentTarget && onClose()}
    >
      <motion.form
        initial={overlay.initial}
        animate={overlay.animate}
        exit={overlay.exit}
        transition={emerge}
        ref={form}
        tabIndex={-1}
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit(event);
        }}
      >
        <h2>{title}</h2>
        {children}
      </motion.form>
    </motion.div>
  );
}

/** Runs a step that answers with what went wrong, if anything; while it runs, the dialog waits. */
export function useStep(onClose: () => void) {
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
      {folders && (
        <FolderChooser folders={folders} libraryName={libraryName} near={parentOf(item.path)} chosen={target} allowed={allowed} onChoose={setTarget} onConfirm={submit} />
      )}
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
