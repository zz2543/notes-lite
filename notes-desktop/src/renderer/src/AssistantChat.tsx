import { ArrowUp, CaretRight, Check, FileText, MagnifyingGlass, PencilSimple, Plus, Sparkle, Stop, TerminalWindow, Warning, X, type Icon } from "@phosphor-icons/react";
import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import type { SearchHit } from "../../core";
import type { AgentActivity } from "../../shared/conversation";
import { agents, type AgentId } from "../../shared/agentKinds";
import { stoppedTurn, withEvent, type Conversation, type ConversationSummary, type Reply, type ReviewChoice, type Step } from "../../shared/conversation";
import type { TurnEvent } from "../../shared/conversation";
import { noteTitle } from "../../shared/paths";
import type { FigureState } from "./figureModel";
import { MarkdownView } from "./ReplyMarkdown";
import { icon } from "./tokens";
import { TurnReview, type ReviewAction } from "./TurnReview";

// 一轮 in the 助手栏 (assistant-spec): the conversation, its messages streaming in with tool calls
// folded into a timeline, and the input with the notes it attaches.

/** How long the figure shows 完成 before it goes back to 待命. */
const doneFor = 1600;

const titleOf = noteTitle;

/** The conversation in the 助手栏 and what the figure shows of it. */
export function useAssistant() {
  const [conversation, setConversation] = useState<Conversation | null>(null);
  const [figure, setFigure] = useState<FigureState>("idle");
  const [problem, setProblem] = useState<string>();
  const current = useRef<string | null>(null);
  current.current = conversation?.id ?? null;

  // Events can come before the answer that says which conversation they belong to; they wait for it.
  const early = useRef<Array<[string, TurnEvent]>>([]);
  const apply = (event: TurnEvent) => {
    setConversation((now) => now && withEvent(now, event));
    if (event.kind === "tool") setFigure(event.activity);
    else if (event.kind === "text" || event.kind === "toolDone") setFigure("thinking");
    else if (event.kind === "end") setFigure(event.failed && event.failed !== stoppedTurn ? "error" : "done");
  };
  useEffect(
    () =>
      window.notes.onTurnEvent((id, event) => {
        if (id === current.current) apply(event);
        else early.current.push([id, event]);
      }),
    [],
  );
  // 完成 is brief: the figure goes back to 待命.
  useEffect(() => {
    if (figure !== "done") return;
    const timer = setTimeout(() => setFigure("idle"), doneFor);
    return () => clearTimeout(timer);
  }, [figure]);

  const running = conversation?.messages.at(-1)?.role === "assistant" && !(conversation.messages.at(-1) as Reply).done;

  /** Starts a turn: in the conversation shown, or, `fresh`, in a new one whatever is shown. */
  const send = async ({ fresh, ...start }: { agent: AgentId; folder: string; model?: string; text: string; notes: string[]; space?: string; fresh?: boolean }) => {
    setProblem(undefined);
    const started = await window.notes.startTurn({ conversation: fresh ? null : (conversation?.id ?? null), ...start });
    if (!started.ok) {
      setProblem(started.message);
      return false;
    }
    const id = started.conversation.id;
    current.current = id;
    setConversation(started.conversation);
    setFigure("thinking");
    const waiting = early.current.filter(([to]) => to === id);
    early.current = [];
    for (const [, event] of waiting) apply(event);
    return true;
  };
  /** Shows a kept conversation (对话历史), to read and continue. */
  const open = async (id: string) => {
    setProblem(undefined);
    const kept = await window.notes.openConversation(id);
    if (!kept) return setProblem("找不到这个对话了。");
    // Events that came before the answer are in it already.
    early.current = early.current.filter(([to]) => to !== id);
    current.current = id;
    setConversation(kept);
    const last = kept.messages.at(-1);
    setFigure(last?.role === "assistant" && !last.done ? "thinking" : "idle");
  };
  const stop = () => conversation && window.notes.stopTurn(conversation.id);
  /** What a turn's review card asks; answers why it couldn't be done, if it couldn't. */
  const review = async (turn: string, action: ReviewChoice, path?: string) => {
    if (!conversation) return;
    const reviewed = await window.notes.reviewTurn({ conversation: conversation.id, turn, action, ...(path !== undefined ? { path } : {}) });
    if (!reviewed.ok) return reviewed.message;
    setConversation((now) => (now?.id === reviewed.conversation.id ? reviewed.conversation : now));
  };
  const reset = () => {
    setConversation(null);
    setProblem(undefined);
    setFigure("idle");
  };
  return { conversation, figure, running, problem, send, open, stop, review, reset };
}

export type AssistantState = ReturnType<typeof useAssistant>;

const verbs: Record<AgentActivity, string> = { reading: "读取", searching: "搜索", writing: "写入", running: "运行", thinking: "" };
/** How much of a call the model has written so far: 18 KB. */
const sizeText = (size: number) => (size < 1024 ? `${size} 字符` : `${Math.round(size / 1024)} KB`);
const stepText = (step: Step) =>
  [verbs[step.activity] || step.name, step.detail].filter(Boolean).join(" ") + (!step.done && step.size ? ` · 已写 ${sizeText(step.size)}` : "");

/** Seconds as the waiting line says them: 42 秒, 3 分 05 秒. */
const elapsedText = (seconds: number) =>
  seconds < 60 ? `${seconds} 秒` : `${Math.floor(seconds / 60)} 分 ${String(seconds % 60).padStart(2, "0")} 秒`;

/**
 * The turn is still going though nothing new has shown for a while (the model thinking, or writing
 * something long it shows only when done): say so, and for how long, so it never looks stuck.
 */
function StillWorking({ immediate }: { immediate: boolean }) {
  const [seconds, setSeconds] = useState(0);
  useEffect(() => {
    const start = Date.now();
    const timer = setInterval(() => setSeconds(Math.floor((Date.now() - start) / 1000)), 1000);
    return () => clearInterval(timer);
  }, []);
  if (!immediate && seconds < 5) return null;
  return (
    <p className="reply-waiting" role="status">
      正在思考…{seconds >= 5 && <span className="reply-waiting-time"> {elapsedText(seconds)}</span>}
    </p>
  );
}

const stepIcons: Record<AgentActivity, Icon> = { reading: FileText, searching: MagnifyingGlass, writing: PencilSimple, running: TerminalWindow, thinking: Sparkle };
const stepKinds: AgentActivity[] = ["running", "reading", "searching", "writing", "thinking"];

/** What a folded timeline did, by kind: 运行 3 · 读取 1. */
const tally = (steps: Step[]) =>
  stepKinds
    .map((kind) => [verbs[kind] || "思考", steps.filter((step) => step.activity === kind).length] as const)
    .filter(([, count]) => count > 0)
    .map(([verb, count]) => `${verb} ${count}`)
    .join(" · ");

/** One step: what kind it is, and what it worked on — a command in code type, cut to one line until opened. */
function StepRow({ step }: { step: Step }) {
  const [open, setOpen] = useState(false);
  const Glyph = step.failed ? Warning : stepIcons[step.activity];
  const state = step.failed ? "failed" : step.done ? "done" : "running";
  const verb = verbs[step.activity] || step.name;
  const detail = step.detail.replace(/\s+/g, " ").trim();
  return (
    <li className={`timeline-step ${state}${open ? " open" : ""}`}>
      <button className="step-row" aria-expanded={detail ? open : undefined} title={open ? undefined : stepText(step)} onClick={() => setOpen(!open)}>
        <Glyph size={icon.caret} className="step-icon" aria-hidden />
        <span className="step-verb">{verb}</span>{detail && " "}
        {detail && <span className={step.activity === "running" ? "step-detail code" : "step-detail"}>{open ? step.detail : detail}</span>}
        {!step.done && step.size ? <span className="step-size"> · 已写 {sizeText(step.size)}</span> : null}
        {step.done && !step.failed && <Check size={icon.caret} className="step-done" aria-hidden />}
      </button>
    </li>
  );
}

/** Consecutive tool calls, folded to one line; open, each call on a line of its own. */
function Timeline({ steps, live }: { steps: Step[]; live: boolean }) {
  const [open, setOpen] = useState(false);
  const last = steps.at(-1)!;
  const working = live && !last.done;
  const failed = steps.filter((step) => step.failed).length;
  return (
    <div className="assistant-timeline">
      <button className="timeline-head" aria-expanded={open} onClick={() => setOpen(!open)}>
        <CaretRight size={icon.caret} className="timeline-caret" />
        <span>{working ? `${steps.length} 个步骤 · 正在${stepText(last)}` : `${steps.length} 个步骤`}</span>
        {!working && <span className="timeline-tally">{tally(steps)}</span>}
        {!working && failed > 0 && <span className="timeline-failed">{failed} 个失败</span>}
      </button>
      {open && (
        <ol className="timeline-steps" aria-label="时间线">
          {steps.map((step) => (
            <StepRow key={step.id} step={step} />
          ))}
        </ol>
      )}
    </div>
  );
}

/** Changes whenever the reply shows something new: its parts, a step's progress or end, more text. */
const progressKey = (reply: Reply) =>
  reply.parts.map((part) => (part.kind === "text" ? part.text.length : part.steps.map((s) => `${s.id}${s.done ? "+" : ""}${s.size ?? ""}`).join())).join("|");

/** A tool call is on (its line says what it does), so the reply is not waiting on the model. */
const stepRunning = (reply: Reply) => {
  const last = reply.parts.at(-1);
  return last?.kind === "steps" && !last.steps.at(-1)!.done;
};

function ReplyView({ reply, onReview, onShowLog }: { reply: Reply; onReview: ReviewAction; onShowLog(): void }) {
  return (
    <div className="assistant-reply">
      {reply.parts.map((part, i) =>
        part.kind === "text" ? (
          <MarkdownView key={i} className="reply-text" text={part.text} />
        ) : (
          <Timeline key={i} steps={part.steps} live={!reply.done && i === reply.parts.length - 1} />
        ),
      )}
      {!reply.done && !stepRunning(reply) && <StillWorking key={progressKey(reply)} immediate={reply.parts.length === 0} />}
      {reply.failed && (
        <p className="reply-failed" role="alert">
          {reply.failed}
        </p>
      )}
      {reply.done && ((reply.changes?.length ?? 0) > 0 || (reply.outside?.length ?? 0) > 0) && (
        <TurnReview reply={reply} onReview={onReview} onShowLog={onShowLog} />
      )}
    </div>
  );
}

export interface ConversationViewProps {
  conversation: Conversation;
  /** What a turn's review card asks, by turn. */
  onReview(turn: string, action: ReviewChoice, path?: string): Promise<string | undefined>;
  onShowLog(): void;
}

export function ConversationView({ conversation, onReview, onShowLog }: ConversationViewProps) {
  const end = useRef<HTMLDivElement>(null);
  const last = conversation.messages.at(-1);
  // Follows the reply as it grows. (Braces: scrollIntoView answers a promise now, not a cleanup.)
  useEffect(() => {
    end.current?.scrollIntoView({ block: "end" });
  }, [last]);
  return (
    <div className="assistant-messages" role="log" aria-label="对话">
      {conversation.messages.map((message, i) =>
        message.role === "user" ? (
          <div key={i} className="assistant-user">
            <p>{message.text}</p>
            {message.notes.length > 0 && <p className="user-notes">{message.notes.map(titleOf).join("、")}</p>}
          </div>
        ) : (
          <ReplyView key={i} reply={message} onReview={(action, path) => onReview(message.turn!, action, path)} onShowLog={onShowLog} />
        ),
      )}
      <div ref={end} />
    </div>
  );
}

const historyTime = new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });

/** 对话历史: the library's kept conversations, the latest first; picking one shows it. */
export function ConversationHistory({ current, libraryName, onPick }: { current: string | null; libraryName: string; onPick(id: string): void }) {
  const [items, setItems] = useState<ConversationSummary[]>();
  useEffect(() => {
    let live = true;
    void window.notes.conversations().then((list) => live && setItems(list));
    return () => {
      live = false;
    };
  }, []);
  return (
    <nav className="assistant-messages assistant-history" aria-label="对话历史">
      {items?.length === 0 && <p className="history-empty">还没有对话。</p>}
      {items && items.length > 0 && (
        <ul>
          {items.map((item) => (
            <li key={item.id}>
              <button className="history-item" aria-current={item.id === current || undefined} onClick={() => onPick(item.id)}>
                <span className="history-title">{item.title || "（空）"}</span>
                <span className="history-meta">
                  {[agents.find((a) => a.id === item.agent)?.name ?? item.agent, folderName(item.folder, libraryName), historyTime.format(new Date(item.updated))].join(" · ")}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </nav>
  );
}

/** A working directory as the 助手栏 names it: its last folder, or the library's name at the top. */
export const folderName = (folder: string, libraryName: string) => (folder ? folder.slice(folder.lastIndexOf("/") + 1) : libraryName);

/** The note being mentioned after an @, up to the caret; null when none is. */
const mentionAt = (text: string, caret: number) => /(?:^|\s)@([^\s@]*)$/.exec(text.slice(0, caret))?.[1] ?? null;

function useMentions(query: string | null) {
  const [hits, setHits] = useState<SearchHit[]>([]);
  useEffect(() => {
    if (query === null) {
      setHits([]);
      return;
    }
    let live = true;
    void window.notes.search(query, { limit: 6 }).then(
      (results) => live && setHits(results.hits),
      () => live && setHits([]),
    );
    return () => {
      live = false;
    };
  }, [query]);
  return hits;
}

export interface ComposerProps {
  /** The open note, attached each turn unless taken off. */
  note: string | null;
  /**
   * In a conversation, the notes its last turn was sent with: they stay its context, whatever note is
   * opened meanwhile, until the user changes them or starts a new conversation. Undefined before one.
   */
  conversationNotes?: string[] | undefined;
  running: boolean;
  /** Something stands in the way of sending, such as no agent installed. */
  disabled: boolean;
  onSend(text: string, notes: string[]): void;
  onStop(): void;
  hasConversation: boolean;
  /** Each new value puts the caret in the message field (让助手修改 on a space's title). */
  focusRequest?: number;
}

/** The input: what to ask, with the open note attached (it can be taken off) and notes mentioned with @. */
export function Composer({ note, conversationNotes, running, disabled, onSend, onStop, hasConversation, focusRequest = 0 }: ComposerProps) {
  const [text, setText] = useState("");
  const [caret, setCaret] = useState(0);
  const [dropped, setDropped] = useState<string | null>(null);
  const [mentioned, setMentioned] = useState<string[]>([]);
  const [highlight, setHighlight] = useState(0);
  const field = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    if (focusRequest > 0) field.current?.focus();
  }, [focusRequest]);
  const query = mentionAt(text, caret);
  const hits = useMentions(query);
  const choices = query === null ? [] : hits;
  useEffect(() => {
    setHighlight(0);
  }, [query]);

  // A new conversation takes the open note; once started, its context stays as the user left it.
  const [edited, setEdited] = useState<string[] | null>(null);
  const sentKey = conversationNotes === undefined ? null : JSON.stringify(conversationNotes);
  useEffect(() => {
    setEdited(null);
    // A new conversation starts afresh: the open note back on, nothing mentioned.
    if (sentKey === null) {
      setDropped(null);
      setMentioned([]);
    }
  }, [sentKey]);
  const pinned = conversationNotes === undefined ? null : (edited ?? conversationNotes);
  const attached = pinned ?? [...new Set([...(note && note !== dropped ? [note] : []), ...mentioned])];
  const edit = (change: (notes: string[]) => string[]) => setEdited(change(pinned!));

  const mention = (hit: SearchHit) => {
    const before = text.slice(0, caret).replace(/@[^\s@]*$/, "");
    const after = text.slice(caret);
    setText(before + after);
    setCaret(before.length);
    add(hit.path);
    requestAnimationFrame(() => {
      field.current?.focus();
      field.current?.setSelectionRange(before.length, before.length);
    });
  };
  const remove = (path: string) => {
    if (pinned) return edit((notes) => notes.filter((p) => p !== path));
    if (path === note) setDropped(path);
    setMentioned((now) => now.filter((p) => p !== path));
  };
  const send = () => {
    const words = text.trim();
    if (!words || running || disabled) return;
    onSend(words, attached);
    setText("");
    setCaret(0);
    setMentioned([]);
  };
  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.nativeEvent.isComposing) return;
    if (choices.length > 0) {
      const step = { ArrowDown: 1, ArrowUp: -1 }[event.key];
      if (step) {
        event.preventDefault();
        return setHighlight((highlight + step + choices.length) % choices.length);
      }
      if (event.key === "Enter" || event.key === "Tab") {
        event.preventDefault();
        return mention(choices[highlight]!);
      }
    }
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      send();
    }
  };
  const track = (target: HTMLTextAreaElement) => setCaret(target.selectionStart);

  function add(path: string) {
    if (pinned) return edit((notes) => (notes.includes(path) ? notes : [...notes, path]));
    setMentioned((now) => (now.includes(path) ? now : [...now, path]));
    if (path === note) setDropped(null);
  }

  return (
    <div className="composer-stack">
      {/* The notes going with the message float above it as capsules: take one off, or add another. */}
      <div className="composer-chips">
        {running ? (
          // The turn under way keeps the notes it was sent with, whatever is opened meanwhile.
          attached.length > 0 && (
            <ul className="attached-notes" aria-label="这一轮附带的笔记">
              {attached.map((path) => (
                <li key={path} className="note-chip locked" title={`${path}（这一轮正在用，结束后可以更改）`}>
                  <FileText size={icon.caret} className="note-chip-icon" aria-hidden />
                  <span className="note-chip-title">{titleOf(path)}</span>
                </li>
              ))}
            </ul>
          )
        ) : (
          <>
            {attached.length > 0 && (
              <ul className="attached-notes" aria-label="附带的笔记">
                {attached.map((path) => (
                  <li key={path} className="note-chip" title={path}>
                    <FileText size={icon.caret} className="note-chip-icon" aria-hidden />
                    <span className="note-chip-title">{titleOf(path)}</span>
                    <button onClick={() => remove(path)} aria-label={`不附上 ${titleOf(path)}`} title="不附上">
                      <X size={icon.caret} />
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <NotePicker attached={attached} onPick={add} />
          </>
        )}
      </div>
      <div className="assistant-composer">
        {choices.length > 0 && (
          <ul className="mention-list" role="listbox" aria-label="提及笔记">
            {choices.map((hit, i) => (
              <li
                key={hit.path}
                role="option"
                aria-selected={i === highlight}
                onMouseDown={(event) => {
                  event.preventDefault();
                  mention(hit);
                }}
              >
                <span className="mention-title">{hit.title}</span>
                {hit.folder && <span className="mention-folder">{hit.folder}</span>}
              </li>
            ))}
          </ul>
        )}
        <textarea
          ref={field}
          rows={3}
          aria-label="给助手的消息"
          placeholder={hasConversation ? "继续对话，@ 提及笔记" : "问问助手，@ 提及笔记"}
          value={text}
          onChange={(event) => {
            setText(event.target.value);
            track(event.target);
          }}
          onSelect={(event) => track(event.currentTarget)}
          onKeyDown={onKeyDown}
        />
        <div className="composer-actions">
          {running ? (
            <button className="icon-button small" onClick={onStop} aria-label="停止" title="停止">
              <Stop size={icon.small} weight="fill" />
            </button>
          ) : (
            <button className="composer-send" onClick={send} disabled={disabled || !text.trim()} aria-label="发送" title="发送">
              <ArrowUp size={icon.small} weight="bold" />
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

/** 提及笔记: a capsule that opens a search for one more note to send with the message. */
function NotePicker({ attached, onPick }: { attached: string[]; onPick(path: string): void }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [highlight, setHighlight] = useState(0);
  const hits = useMentions(open ? query : null).filter((hit) => !attached.includes(hit.path));
  useEffect(() => {
    setHighlight(0);
  }, [query]);
  const close = () => {
    setOpen(false);
    setQuery("");
  };
  const pick = (hit: SearchHit) => {
    onPick(hit.path);
    close();
  };
  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.nativeEvent.isComposing) return;
    const step = { ArrowDown: 1, ArrowUp: -1 }[event.key];
    if (step && hits.length > 0) {
      event.preventDefault();
      setHighlight((highlight + step + hits.length) % hits.length);
    } else if (event.key === "Enter" && hits[highlight]) {
      event.preventDefault();
      pick(hits[highlight]);
    } else if (event.key === "Escape") {
      event.preventDefault();
      close();
    }
  };
  return (
    <div className="note-picker">
      <button className="note-chip note-chip-add" aria-expanded={open} aria-label="提及笔记…" title="提及笔记" onClick={() => (open ? close() : setOpen(true))}>
        <Plus size={icon.caret} aria-hidden />
        {attached.length === 0 && <span>提及笔记</span>}
      </button>
      {open && (
        <div className="mention-picker">
          <input
            autoFocus
            aria-label="搜索要提及的笔记"
            placeholder="搜索笔记"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={onKeyDown}
            onBlur={close}
          />
          {hits.length > 0 ? (
            <ul className="mention-list inline" role="listbox" aria-label="选择笔记">
              {hits.map((hit, i) => (
                <li
                  key={hit.path}
                  role="option"
                  aria-selected={i === highlight}
                  onMouseDown={(event) => {
                    event.preventDefault();
                    pick(hit);
                  }}
                >
                  <span className="mention-title">{hit.title}</span>
                  {hit.folder && <span className="mention-folder">{hit.folder}</span>}
                </li>
              ))}
            </ul>
          ) : (
            <p className="mention-empty">{query ? "没有找到笔记" : "没有更多笔记"}</p>
          )}
        </div>
      )}
    </div>
  );
}
