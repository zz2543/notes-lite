import { Check, Copy, Globe, House, ListChecks, PencilSimpleLine, Sparkle, Warning, X } from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import type { SpaceNetwork, SpaceScope } from "../../core";
import type { SpaceInfo, SpaceNote, SpacePageProblem, SpaceBackdrop } from "../../shared/api";
import { scopeLabel } from "../../shared/spaceScope";
import { useMotion } from "./MotionProvider";
import { useOverlayOpen } from "./Organize";
import { SelectionPill } from "./SelectionPill";
import { icon } from "./tokens";

// An open space: its notes in the middle column with 主页 pinned on top, and on the card its
// homepage (run by main in a sandbox laid over the card) or, when a note is chosen, the editor.
// Its head opens the operation log (OperationLog.tsx), which takes entries back one by one.

const touchesSpaces = (path: string) => path === "" || path === ".notes" || path.startsWith(".notes/空间");

/** The space named `name` as it is now, read again whenever a space file changes. */
export function useSpace(name: string | null): SpaceInfo | null | undefined {
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
  useEffect(() => window.notes.onLibraryChanged((paths) => paths.some(touchesSpaces) && setRevision((n) => n + 1)), []);
  if (name === null) return null;
  return spaces && (spaces.find((space) => space.name === name) ?? null);
}

/**
 * 联网: the sites the homepage names and whether the user allowed them, read again when a space file
 * changes; `decide` answers (null: ask again).
 */
function useSpaceNetwork(name: string) {
  const [network, setNetwork] = useState<{ name: string; state: SpaceNetwork }>();
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    void window.notes.spaceNetwork(name).then((read) => live && read.ok && setNetwork({ name, state: read.value }));
    return () => {
      live = false;
    };
  }, [name, revision]);
  useEffect(() => window.notes.onLibraryChanged((paths) => paths.some(touchesSpaces) && setRevision((n) => n + 1)), []);
  const decide = async (allowed: boolean | null) => {
    const done = await window.notes.setSpaceNetwork(name, allowed);
    if (done.ok) setNetwork({ name, state: done.value });
  };
  const state = network?.name === name && network.state.hosts.length > 0 ? network.state : undefined;
  return { state, decide };
}

/** The notes in the space's scope, read again when the library changes. */
function useSpaceNotes(name: string): SpaceNote[] | undefined {
  const [notes, setNotes] = useState<{ name: string; notes: SpaceNote[] }>();
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    void window.notes.spaceNotes(name).then((listed) => live && setNotes({ name, notes: listed.ok ? listed.value : [] }));
    return () => {
      live = false;
    };
  }, [name, revision]);
  useEffect(() => window.notes.onLibraryChanged(() => setRevision((n) => n + 1)), []);
  return notes?.name === name ? notes.notes : undefined;
}

interface SpaceContentsProps {
  space: SpaceInfo;
  /** The list column (双栏导航), or under the spaces in the side panel (单栏导航). */
  place: "list" | "side";
  showingHome: boolean;
  openNote: string | null;
  onHome(): void;
  onOpenNote(path: string): void;
}

/** An open space's contents: 主页, then every note in its scope. */
export function SpaceContents({ space, place, showingHome, openNote, onHome, onOpenNote }: SpaceContentsProps) {
  const notes = useSpaceNotes(space.name);
  const name = (
    <>
      {space.icon && <span aria-hidden>{space.icon} </span>}
      {space.name}
    </>
  );
  return (
    <>
      {place === "list" ? (
        <header className="list-head">
          <h1>{name}</h1>
        </header>
      ) : (
        <div className="side-label">
          <span className="label">{name}</span>
        </div>
      )}
      <ul className="items" aria-label="空间内容">
        <li>
          <button className={`item ${showingHome ? "on" : ""}`} aria-current={showingHome || undefined} onClick={onHome}>
            {showingHome && <SelectionPill group="list" />}
            <House size={icon.regular} />
            <span className="label">主页</span>
          </button>
        </li>
        {notes?.map((note) => {
          const on = !showingHome && openNote === note.path;
          return (
            <li key={note.path}>
              <button className={`item ${on ? "on" : ""}`} aria-current={on || undefined} title={note.path} onClick={() => onOpenNote(note.path)}>
                {on && <SelectionPill group="list" />}
                <span className="label">{note.title}</span>
              </button>
            </li>
          );
        })}
      </ul>
      {notes?.length === 0 && <p className="empty">范围内还没有笔记</p>}
    </>
  );
}

interface SpaceHomeProps {
  space: SpaceInfo;
  notify(message: string): void;
  /** Opens 操作记录. */
  onShowLog(): void;
  /** 让助手生成主页: has 助手 write it. */
  onGenerate(): void;
  /** 让助手修改: opens 助手栏 to say what to change; the open space goes with it. */
  onAsk(): void;
  /** 让助手修复: the homepage's error, as the report for the agent and its one line. */
  onFix?(report: string, message: string): void;
  /** At the head's right end, as on a note's card. */
  headEnd?: ReactNode;
}

/**
 * The homepage's own backdrop (风格参考): the card around it, title row included, takes the page's top
 * colour and text colour, so the title sits on the page rather than in a band of the app's colour.
 */
function useSpaceBackdrop(name: string): CSSProperties | undefined {
  const [backdrop, setBackdrop] = useState<SpaceBackdrop | null>(null);
  useEffect(() => {
    setBackdrop(null);
    return window.notes.onSpacePageEvent((event) => {
      if (event.space !== name) return;
      if (event.kind === "backdrop") setBackdrop(event.backdrop);
    });
  }, [name]);
  if (!backdrop) return undefined;
  const { background, text } = backdrop;
  return {
    "--space-surface": background,
    "--card-fg": text,
    "--card-path": `color-mix(in srgb, ${text} 38%, transparent)`,
    "--space-muted": `color-mix(in srgb, ${text} 60%, transparent)`,
    "--hover": `color-mix(in srgb, ${text} 8%, transparent)`,
  } as CSSProperties;
}

/** The card while a space's homepage shows: its head, and the place main lays the homepage over. */
export function SpaceHome({ space, notify, onShowLog, onGenerate, onAsk, onFix, headEnd }: SpaceHomeProps) {
  const network = useSpaceNetwork(space.name);
  const backdrop = useSpaceBackdrop(space.name);
  const copyPrompt = async () => {
    const copied = await window.notes.copySpacePrompt(space.name);
    notify(copied.ok ? "提示词已复制到剪贴板，粘贴给 Claude Code、Codex 等外部 agent，就能生成空间主页。" : copied.message);
  };
  return (
    <article className="card" data-kind="space" aria-label="卡片" style={space.hasPage ? backdrop : undefined}>
      <SpaceTitle
        space={space}
        network={space.hasPage ? network.state : undefined}
        onNetwork={() => void network.decide(null)}
        onAsk={space.hasPage ? onAsk : onGenerate}
        headEnd={
          <>
            <button className="card-tool" onClick={onShowLog}>
              <ListChecks size={icon.small} />
              操作记录
            </button>
            {headEnd}
          </>
        }
      />
      {space.hasPage ? (
        <>
          <PageBars name={space.name} onShowLog={onShowLog} onFix={onFix} network={network.state} onNetwork={(allowed) => void network.decide(allowed)} />
          <PageSlot name={space.name} />
        </>
      ) : (
        <div className="space-empty space-no-page">
          <p>这个空间还没有主页。</p>
          <button className="primary" onClick={onGenerate}>
            让助手生成主页
          </button>
          <p>
            助手栏会打开并开始编写，写好后显示在这里。也可以
            <button className="link-button" onClick={() => void copyPrompt()}>
              复制提示词
            </button>
            交给外部 agent。
          </p>
        </div>
      )}
    </article>
  );
}

/** 范围：健身/、日记/, or 范围：整个笔记库. */
/** A tool over the page: its label beside the icon, only the icon (named all the same) in a narrow card. */
function TitleButton({ label, tip = label, onClick, children }: { label: string; tip?: string; onClick(): void; children: ReactNode }) {
  return (
    <button className="space-title-button" onClick={onClick} aria-label={label} title={tip}>
      {children}
      <span className="space-title-label">{label}</span>
    </button>
  );
}

const scopeLine = (scope: SpaceScope) => `范围：${scopeLabel(scope, { asFolders: true })}`;

interface SpaceTitleProps {
  space: SpaceInfo;
  /** 让助手修改: the assistant on this page, or, while there is no page yet, 让助手生成主页. */
  onAsk(): void;
  /** 联网, when the homepage names sites; pressing it asks again. */
  network?: SpaceNetwork;
  onNetwork(): void;
  /** What follows the page's tools in the card's top row: 操作记录, then the window's own buttons. */
  headEnd: ReactNode;
}

/**
 * Over the homepage, one row only: the space's icon, name and scope, then 让助手修改 (and 联网 when asked),
 * 操作记录 and the window's buttons, so the page keeps the card's height. 复制提示词 and 显示源文件 are in
 * the space's right-click menu.
 */
function SpaceTitle({ space, network, onNetwork, onAsk, headEnd }: SpaceTitleProps) {
  return (
    <section className="space-head" aria-label="空间标题">
      <header className="card-head">
        <div className="space-title">
          <h1>
            {space.icon && (
              <span className="space-title-icon" aria-hidden>
                {space.icon}
              </span>
            )}
            {space.name}
          </h1>
          <p className="space-title-scope">{scopeLine(space.scope)}</p>
        </div>
        <div className="space-title-tools">
          {network && network.decision !== "ask" && (
            <TitleButton label={network.decision === "allowed" ? "已允许联网" : "未允许联网"} tip={`可访问：${network.hosts.join("、")}。点按重新选择。`} onClick={onNetwork}>
              <Globe size={icon.small} aria-hidden />
            </TitleButton>
          )}
          <TitleButton label={space.hasPage ? "让助手修改" : "让助手生成主页"} onClick={onAsk}>
            <Sparkle size={icon.small} aria-hidden />
          </TitleButton>
        </div>
        {headEnd}
      </header>
    </section>
  );
}

/** How long 写入提示 stays after the homepage's last write. */
const noticeTime = 8000;
/** The 错误条 keeps the last few distinct problems. */
const keptProblems = 5;

const sameProblem = (a: SpacePageProblem, b: SpacePageProblem) => a.message === b.message && a.location === b.location && a.stack === b.stack;

/**
 * Above the homepage: the 错误条 when it went wrong (with 复制错误给 agent), and 写入提示 after it wrote.
 * Both open on 展开, pushing the page down rather than covering it.
 */
function PageBars({ name, onShowLog, onFix, network, onNetwork }: { name: string; onShowLog(): void; onFix?(report: string, message: string): void; network?: SpaceNetwork; onNetwork(allowed: boolean): void }) {
  const [problems, setProblems] = useState<SpacePageProblem[]>([]);
  const [wrote, setWrote] = useState<{ changes: number; onlyRecords: boolean } | null>(null);
  const [copied, setCopied] = useState(false);
  const { expand } = useMotion();

  useEffect(() => {
    setProblems([]);
    setWrote(null);
    let hideNotice: ReturnType<typeof setTimeout> | undefined;
    const stop = window.notes.onSpacePageEvent((event) => {
      if (event.space !== name) return;
      if (event.kind === "loaded") setProblems([]);
      else if (event.kind === "problem") {
        const { problem } = event;
        setProblems((kept) => (kept.some((p) => sameProblem(p, problem)) ? kept : [...kept, problem].slice(-keptProblems)));
      } else if (event.kind === "wrote") {
        setWrote((now) => ({ changes: (now?.changes ?? 0) + event.changes, onlyRecords: (now?.onlyRecords ?? true) && event.records === event.changes }));
        clearTimeout(hideNotice);
        hideNotice = setTimeout(() => setWrote(null), noticeTime);
      }
    });
    return () => {
      stop();
      clearTimeout(hideNotice);
    };
  }, [name]);

  useEffect(() => {
    if (!copied) return;
    const back = setTimeout(() => setCopied(false), 1600);
    return () => clearTimeout(back);
  }, [copied]);

  const problem = problems.at(-1);
  // A new problem has not been copied yet.
  useEffect(() => setCopied(false), [problem]);
  const copy = async () => {
    if (!problem) return;
    const done = await window.notes.copySpaceError(name, problem);
    if (done.ok) setCopied(true);
  };
  const fix = async () => {
    if (!problem || !onFix) return;
    const report = await window.notes.spaceErrorReport(name, problem);
    if (report.ok) onFix(report.value, problem.message);
  };
  const bar = { initial: { height: 0, opacity: 0 }, animate: { height: "auto", opacity: 1 }, exit: { height: 0, opacity: 0 }, transition: expand };

  return (
    <div className="space-bars">
      <AnimatePresence initial={false}>
        {network?.decision === "ask" && (
          <motion.div key="network" className="space-bar-frame" {...bar}>
            <div className="space-bar notice" role="alert" aria-label="主页想联网">
              <Globe size={icon.small} className="space-bar-icon" aria-hidden />
              <div className="space-bar-text">
                <strong>这个主页想联网，访问 {network.hosts.join("、")}</strong>
                <span className="space-bar-detail">{network.reason ? `用途：${network.reason}。` : ""}不允许时，它只能使用笔记里的数据。</span>
              </div>
              <button type="button" className="space-bar-button" onClick={() => onNetwork(false)}>
                不允许
              </button>
              <button type="button" className="space-bar-button" onClick={() => onNetwork(true)}>
                允许联网
              </button>
            </div>
          </motion.div>
        )}
        {problem && (
          <motion.div key="problem" className="space-bar-frame" {...bar}>
            <div className="space-bar problem" role="alert" aria-label="主页出错了">
              <Warning size={icon.small} weight="fill" className="space-bar-icon" aria-hidden />
              <div className="space-bar-text">
                <strong>主页出错了{problems.length > 1 ? `（${problems.length} 个错误）` : ""}</strong>
                <span className="space-bar-detail">
                  {problem.message}
                  {problem.location && ` · ${problem.location}`}
                </span>
              </div>
              {onFix && (
                <button type="button" className="space-bar-button" onClick={() => void fix()}>
                  <Sparkle size={icon.small} aria-hidden />
                  让助手修复
                </button>
              )}
              <button type="button" className="space-bar-button" onClick={() => void copy()}>
                {copied ? <Check size={icon.small} aria-hidden /> : <Copy size={icon.small} aria-hidden />}
                {copied ? "已复制" : "复制错误给 agent"}
              </button>
              <button type="button" className="space-bar-close" aria-label="关闭错误提示" onClick={() => setProblems([])}>
                <X size={icon.caret} weight="bold" aria-hidden />
              </button>
            </div>
          </motion.div>
        )}
        {wrote && (
          <motion.div key="wrote" className="space-bar-frame" {...bar}>
            <div className="space-bar notice" role="status" aria-label="主页写入">
              <PencilSimpleLine size={icon.small} className="space-bar-icon" aria-hidden />
              <span className="space-bar-text">
                主页刚修改了 <strong>{wrote.changes}</strong> {wrote.onlyRecords ? "条记录" : "处内容"}
              </span>
              <button type="button" className="space-bar-link" onClick={onShowLog}>
                查看
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

/** Where the homepage goes; main keeps it over this box, and takes it away while a menu or dialog is open. */
function PageSlot({ name }: { name: string }) {
  const slot = useRef<HTMLDivElement>(null);
  const covered = useOverlayOpen();
  useLayoutEffect(() => {
    const box = slot.current;
    if (!box || covered) return window.notes.hideSpacePage();
    const place = () => {
      const { x, y, width, height } = box.getBoundingClientRect();
      window.notes.showSpacePage(name, { x, y, width, height });
    };
    place();
    const watch = new ResizeObserver(place);
    watch.observe(box);
    window.addEventListener("resize", place);
    return () => {
      watch.disconnect();
      window.removeEventListener("resize", place);
      window.notes.hideSpacePage();
    };
  }, [name, covered]);
  return <div ref={slot} className="space-page-slot" aria-label="空间主页" role="region" />;
}
