import { Books, DotsThree, Plus, SquaresFour } from "@phosphor-icons/react";
import { AnimatePresence, motion, Reorder } from "motion/react";
import { useEffect, useRef, useState, type MouseEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import type { SpaceDraft, SpaceScope } from "../../core";
import type { SpaceInfo } from "../../shared/api";
import { scopeLabel } from "../../shared/spaceScope";
import { travel } from "./motion";
import { useMotion } from "./MotionProvider";
import { FolderChecklist } from "./FolderPicker";
import { ContextMenu, Dialog, useStep, type Menu } from "./Organize";
import { SelectionPill } from "./SelectionPill";
import "./spaces.css";
import { icon } from "./tokens";

// 空间 in the side panel: the list of spaces (dragged to reorder), its menu, and the form that
// creates or edits a space. The space files live in the library's `.notes/空间/`; the core library
// does the work. Opening a space (its page and scoped tree) is ticket 19.

export type SideMode = "library" | "spaces";

/**
 * “资料库 | 空间”: one switch, pressed to go to the other. It names the side shown, beside a knob that
 * slides (滑移) to the other end on each press, the way TRAE's SOLO | IDE switch does. As a switch it is
 * 空间, on while the spaces show.
 */
export function SideSwitch({ mode, onChange }: { mode: SideMode; onChange(mode: SideMode): void }) {
  const { slide } = useMotion();
  const spaces = mode === "spaces";
  const Icon = spaces ? SquaresFour : Books;
  return (
    <button
      className={`side-switch ${spaces ? "on" : ""}`}
      role="switch"
      aria-checked={spaces}
      aria-label="空间"
      title={spaces ? "回到资料库" : "切换到空间"}
      onClick={() => onChange(spaces ? "library" : "spaces")}
    >
      <motion.span key={mode} layout="position" transition={slide} initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="side-switch-label">
        {spaces ? "空间" : "资料库"}
      </motion.span>
      <motion.span layout="position" transition={slide} className="side-switch-knob" aria-hidden>
        <Icon size={icon.small} weight="fill" />
      </motion.span>
    </button>
  );
}

/**
 * The side panel's pages share one place, lying left to right: 资料库, the space list, then (单栏导航)
 * an open space. Going to a page further right slides the content left, going back slides it right,
 * fading as it goes. A switch midway turns the slide around.
 */
export function SidePages({ page, rank, children }: { page: string; rank: number; children: ReactNode }) {
  const { slide, amplitude } = useMotion();
  const distance = travel.sideSwitch * amplitude;
  // Which way the page now arriving came from: +1 from the right, -1 from the left.
  const last = useRef({ page, rank, way: 1 });
  if (last.current.page !== page) last.current = { page, rank, way: rank > last.current.rank ? 1 : -1 };
  const way = last.current.way;
  return (
    <div className="side-pages">
      <AnimatePresence initial={false} mode="popLayout" custom={way}>
        <motion.div
          key={page}
          className="side-page"
          custom={way}
          variants={{
            enter: (from: number) => ({ x: from * distance, opacity: 0 }),
            shown: { x: 0, opacity: 1 },
            // The page leaving goes the other way from the one arriving.
            leave: (from: number) => ({ x: -from * distance, opacity: 0 }),
          }}
          initial="enter"
          animate="shown"
          exit="leave"
          transition={slide}
        >
          {children}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

const touchesSpaces =(path: string) => path === "" || path === ".notes" || path.startsWith(".notes/空间");

/** The open library's spaces, read again whenever a space file changes, by this app or any other program. */
function useSpaceList(): [SpaceInfo[] | undefined, (spaces: SpaceInfo[]) => void, () => void] {
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
  const reload = () => setRevision((n) => n + 1);
  useEffect(() => window.notes.onLibraryChanged((paths) => paths.some(touchesSpaces) && reload()), []);
  return [spaces, setSpaces, reload];
}

interface SpacePanelProps {
  /** The place in the title bar's row for 更多新建方式 and 新建空间. */
  tools: HTMLElement | null;
  libraryName: string;
  /** The space last clicked, if any. */
  selected: string | null;
  onSelect(name: string | null): void;
  notify(message: string): void;
  /** Has 助手 write the space's homepage. */
  onGenerate(name: string): void;
}

export function SpacePanel({ tools, libraryName, selected, onSelect, notify, onGenerate }: SpacePanelProps) {
  const [spaces, setSpaces, reload] = useSpaceList();
  const [menu, setMenu] = useState<Menu>();
  const [dialog, setDialog] = useState<ReactNode>();
  const close = () => setDialog(undefined);
  // The order on screen while a row is dragged; saved once it is dropped.
  const order = useRef<string[]>([]);
  order.current = spaces?.map((space) => space.name) ?? [];

  const create = () =>
    setDialog(
      <SpaceDialog
        title="新建空间"
        confirm="新建"
        libraryName={libraryName}
        onClose={close}
        onSubmit={async (draft) => {
          const created = await window.notes.createSpace(draft);
          if (!created.ok) return created.message;
          reload();
          onSelect(created.value.name);
          // 助手 writes its homepage at once, in the column (2026-10-21 用户反馈).
          onGenerate(created.value.name);
        }}
      />,
    );

  // 新建示例空间: its homepage is written by the app, so 助手 is not asked for one.
  const createExample = async () => {
    const created = await window.notes.createExampleSpace();
    if (!created.ok) return notify(created.message);
    reload();
    onSelect(created.value.name);
  };

  const openNewMenu = (event: MouseEvent<HTMLButtonElement>) => {
    const { left, bottom } = event.currentTarget.getBoundingClientRect();
    setMenu({ x: left, y: bottom + 4, items: [{ label: "新建空间…", run: create }, { label: "新建示例空间", run: () => void createExample() }] });
  };

  const edit = (space: SpaceInfo) =>
    setDialog(
      <SpaceDialog
        title="编辑空间"
        confirm="保存"
        libraryName={libraryName}
        space={space}
        onClose={close}
        onSubmit={async (draft) => {
          const edited = await window.notes.updateSpace(space.name, draft);
          if (!edited.ok) return edited.message;
          reload();
          if (selected === space.name) onSelect(edited.value.name);
        }}
      />,
    );

  const remove = async (space: SpaceInfo) => {
    const sure = await window.notes.confirm({
      message: `删除空间“${space.name}”？`,
      detail: "只删除这个空间的主页文件，范围内的笔记不会被改动。",
      action: "删除空间",
    });
    if (!sure) return;
    const deleted = await window.notes.deleteSpace(space.name);
    if (!deleted.ok) return notify(deleted.message);
    reload();
    if (selected === space.name) onSelect(null);
  };

  const copyPrompt = async (space: SpaceInfo) => {
    const copied = await window.notes.copySpacePrompt(space.name);
    notify(copied.ok ? "提示词已复制到剪贴板，粘贴给外部 agent 即可生成空间主页。" : copied.message);
  };

  const revealSource = async (space: SpaceInfo) => {
    const shown = await window.notes.revealSpaceSource(space.name);
    if (!shown.ok) notify(shown.message);
  };

  const saveOrder = async () => {
    const saved = await window.notes.reorderSpaces(order.current);
    if (!saved.ok) {
      notify(saved.message);
      reload();
    }
  };

  const openMenu = (space: SpaceInfo, event: MouseEvent) => {
    event.preventDefault();
    setMenu({
      x: event.clientX,
      y: event.clientY,
      items: [
        { label: "编辑空间…", run: () => edit(space) },
        { label: "让助手生成主页", run: () => onGenerate(space.name) },
        { label: "复制给 agent 的提示词", run: () => void copyPrompt(space) },
        { label: "显示源文件", run: () => void revealSource(space) },
        "separator",
        { label: "删除空间…", run: () => void remove(space) },
      ],
    });
  };

  return (
    <>
      {tools &&
        createPortal(
          <>
            <button className="icon-button small" onClick={openNewMenu} aria-label="更多新建方式" title="更多新建方式">
              <DotsThree size={icon.small} weight="bold" />
            </button>
            <button className="icon-button small" onClick={create} aria-label="新建空间" title="新建空间">
              <Plus size={icon.small} />
            </button>
          </>,
          tools,
        )}
      <div className="space-scroll">
        {spaces && spaces.length > 0 && (
          <Reorder.Group
            axis="y"
            className="space-list"
            aria-label="空间"
            values={spaces}
            onReorder={(next: SpaceInfo[]) => setSpaces(next)}
          >
            {spaces.map((space) => (
              <Reorder.Item key={space.name} value={space} className="space-item" onDragEnd={() => void saveOrder()}>
                <button
                  className={`row space-row ${selected === space.name ? "on" : ""}`}
                  aria-label={space.name}
                  aria-current={selected === space.name ? "true" : undefined}
                  title={`${space.name} · ${scopeLabel(space.scope)}`}
                  onClick={() => onSelect(space.name)}
                  onContextMenu={(event) => openMenu(space, event)}
                >
                  {selected === space.name && <SelectionPill group="space" />}
                  <span className="space-icon" aria-hidden>
                    {space.icon || <SquaresFour size={icon.regular} />}
                  </span>
                  <span className="label">{space.name}</span>
                </button>
              </Reorder.Item>
            ))}
          </Reorder.Group>
        )}
        {spaces?.length === 0 && (
          <div className="space-empty">
            <button className="secondary" onClick={create}>
              新建空间
            </button>
            <p>空间围绕一个主题，把相关文件夹放在一起，并有一个由 agent 生成的主页。</p>
            <p>
              不知道从哪开始？
              <button className="link-button" onClick={() => void createExample()}>
                新建示例空间
              </button>
              看看主页能放哪些组件。
            </p>
          </div>
        )}
      </div>
      {menu && <ContextMenu {...menu} onClose={() => setMenu(undefined)} />}
      <AnimatePresence>{dialog}</AnimatePresence>
    </>
  );
}

interface SpaceDialogProps {
  title: string;
  confirm: string;
  libraryName: string;
  /** The space being edited; none when creating one. */
  space?: SpaceInfo;
  onClose(): void;
  /** Answers with why the space was refused; the dialog then stays open. */
  onSubmit(draft: SpaceDraft): Promise<string | void>;
}

/** 新建空间 / 编辑空间: name, emoji and scope. */
function SpaceDialog({ title, confirm, libraryName, space, onClose, onSubmit }: SpaceDialogProps) {
  const [name, setName] = useState(space?.name ?? "");
  const [emoji, setEmoji] = useState(space?.icon ?? "✨");
  const [whole, setWhole] = useState(space?.scope.library ?? false);
  const [chosen, setChosen] = useState<ReadonlySet<string>>(() => new Set(space && !space.scope.library ? space.scope.folders : []));
  const [folders, setFolders] = useState<string[]>();
  const { error, setError, busy, run } = useStep(onClose);
  const nameInput = useRef<HTMLInputElement>(null);
  useEffect(() => {
    nameInput.current?.select();
    window.notes.listFolders().then(setFolders, () => setFolders([]));
  }, []);

  // The name, until typed, follows the first folder ticked: ticking 健身 names the space 健身.
  const [named, setNamed] = useState(Boolean(space));
  const choose = (next: ReadonlySet<string>) => {
    setError(undefined);
    setChosen(next);
    const first = (folders ?? []).find((f) => next.has(f));
    if (!named) setName(first?.split("/").at(-1) ?? "");
  };
  const submit = () => {
    // Folders keep the library's order, whatever order they were ticked in.
    const scope: SpaceScope = whole ? { library: true } : { library: false, folders: (folders ?? []).filter((f) => chosen.has(f)) };
    void run(() => onSubmit({ name: name.trim(), icon: emoji.trim(), scope }));
  };

  return (
    <Dialog title={title} onClose={onClose} onSubmit={submit}>
      <div className="space-name">
        <input
          className="dialog-input space-emoji"
          aria-label="空间图标"
          value={emoji}
          spellCheck={false}
          onChange={(event) => setEmoji(event.target.value)}
        />
        <input
          ref={nameInput}
          className="dialog-input"
          aria-label="空间名称"
          placeholder="空间名称，例如：健身"
          value={name}
          spellCheck={false}
          onChange={(event) => {
            setName(event.target.value);
            setNamed(event.target.value !== "");
            setError(undefined);
          }}
        />
      </div>
      <p className="dialog-hint">范围：空间主页只能读取和写入范围内的笔记。选中的文件夹包括它里面的所有子文件夹。</p>
      <label className="space-check">
        <input
          type="checkbox"
          checked={whole}
          onChange={(event) => {
            setWhole(event.target.checked);
            setError(undefined);
          }}
        />
        <span className="label">整个笔记库</span>
      </label>
      {!whole && folders && (
        <FolderChecklist
          folders={folders}
          chosen={chosen}
          onChange={choose}
          label={`${libraryName}中的文件夹`}
          empty={<p className="dialog-hint">笔记库里还没有文件夹，可以选择整个笔记库。</p>}
        />
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
        <button type="submit" className="primary" disabled={busy}>
          {confirm}
        </button>
      </div>
    </Dialog>
  );
}
