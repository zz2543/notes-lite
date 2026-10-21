import { ArrowUp, CaretRight, Plus, Stop, X } from "@phosphor-icons/react";
import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import type { SearchHit } from "../../core";
import type { AgentActivity } from "../../shared/conversation";
import type { AgentId } from "../../shared/agentKinds";
import { withEvent, type Conversation, type Reply, type Step } from "../../shared/conversation";
import type { TurnEvent } from "../../shared/conversation";
import { noteTitle } from "../../shared/paths";
import type { FigureState } from "./figureModel";
import { icon } from "./tokens";
import { TurnReview, type ReviewAction } from "./TurnReview";

// 一轮 in the 助手栏 (assistant-spec): the conversation, its messages streaming in with tool calls
// folded into a timeline, and the input with the notes it attaches.

/** How long the figure shows 完成 before it goes back to 待命. */
const doneFor = 1600;
/** What a turn the user stopped ends with: no error for the figure. */
const stopped = "已停止。";

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
    else if (event.kind === "end") setFigure(event.failed && event.failed !== stopped ? "error" : "done");
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

  const send = async (start: { agent: AgentId; folder: string; text: string; notes: string[] }) => {
    setProblem(undefined);
    const started = await window.notes.startTurn({ conversation: conversation?.id ?? null, ...start });
    if (!started.ok) return setProblem(started.message);
    const id = started.conversation.id;
    current.current = id;
    setConversation(started.conversation);
    setFigure("thinking");
    const waiting = early.current.filter(([to]) => to === id);
    early.current = [];
    for (const [, event] of waiting) apply(event);
  };
  const stop = () => conversation && window.notes.stopTurn(conversation.id);
  /** What a turn's review card asks; answers why it couldn't be done, if it couldn't. */
  const review = async (turn: string, action: "keep" | "revert", path?: string) => {
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
  return { conversation, figure, running, problem, send, stop, review, reset };
}

export type AssistantState = ReturnType<typeof useAssistant>;

const verbs: Record<AgentActivity, string> = { reading: "读取", searching: "搜索", writing: "写入", running: "运行", thinking: "" };
const stepText = (step: Step) => [verbs[step.activity] || step.name, step.detail].filter(Boolean).join(" ");

/** Consecutive tool calls, folded to one line; open, each call on a line of its own. */
function Timeline({ steps, live }: { steps: Step[]; live: boolean }) {
  const [open, setOpen] = useState(false);
  const last = steps.at(-1)!;
  const summary = live && !last.done ? `正在${stepText(last)}` : `${steps.length} 个步骤`;
  return (
    <div className="assistant-timeline">
      <button className="timeline-head" aria-expanded={open} onClick={() => setOpen(!open)}>
        <CaretRight size={icon.caret} className="timeline-caret" />
        <span>{live && !last.done ? `${steps.length} 个步骤 · ${summary}` : summary}</span>
      </button>
      {open && (
        <ol className="timeline-steps" aria-label="时间线">
          {steps.map((step) => (
            <li key={step.id} className={step.failed ? "failed" : step.done ? "" : "running"}>
              {stepText(step)}
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

function ReplyView({ reply, onReview, onShowLog }: { reply: Reply; onReview: ReviewAction; onShowLog(): void }) {
  return (
    <div className="assistant-reply">
      {reply.parts.map((part, i) =>
        part.kind === "text" ? (
          <p key={i} className="reply-text">
            {part.text}
          </p>
        ) : (
          <Timeline key={i} steps={part.steps} live={!reply.done && i === reply.parts.length - 1} />
        ),
      )}
      {!reply.done && reply.parts.length === 0 && <p className="reply-waiting">正在思考…</p>}
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
  onReview(turn: string, action: "keep" | "revert", path?: string): Promise<string | undefined>;
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
  running: boolean;
  /** Something stands in the way of sending, such as no agent installed. */
  disabled: boolean;
  onSend(text: string, notes: string[]): void;
  onStop(): void;
  onNew(): void;
  hasConversation: boolean;
}

/** The input: what to ask, with the open note attached (it can be taken off) and notes mentioned with @. */
export function Composer({ note, running, disabled, onSend, onStop, onNew, hasConversation }: ComposerProps) {
  const [text, setText] = useState("");
  const [caret, setCaret] = useState(0);
  const [dropped, setDropped] = useState<string | null>(null);
  const [mentioned, setMentioned] = useState<string[]>([]);
  const [highlight, setHighlight] = useState(0);
  const field = useRef<HTMLTextAreaElement>(null);
  const query = mentionAt(text, caret);
  const hits = useMentions(query);
  const choices = query === null ? [] : hits;
  useEffect(() => {
    setHighlight(0);
  }, [query]);

  const attached = [...new Set([...(note && note !== dropped ? [note] : []), ...mentioned])];

  const mention = (hit: SearchHit) => {
    const before = text.slice(0, caret).replace(/@[^\s@]*$/, "");
    const after = text.slice(caret);
    setText(before + after);
    setCaret(before.length);
    setMentioned((now) => (now.includes(hit.path) ? now : [...now, hit.path]));
    if (hit.path === note) setDropped(null);
    requestAnimationFrame(() => {
      field.current?.focus();
      field.current?.setSelectionRange(before.length, before.length);
    });
  };
  const remove = (path: string) => {
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

  return (
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
      {attached.length > 0 && (
        <ul className="attached-notes" aria-label="附带的笔记">
          {attached.map((path) => (
            <li key={path} className="note-chip">
              <span>{titleOf(path)}</span>
              <button onClick={() => remove(path)} aria-label={`不附上 ${titleOf(path)}`} title="不附上">
                <X size={icon.caret} />
              </button>
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
        <button className="icon-button small" onClick={onNew} disabled={running || !hasConversation} aria-label="新对话" title="新对话">
          <Plus size={icon.small} />
        </button>
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
  );
}
