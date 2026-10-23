// 对话: what the 助手栏 shows and the app keeps of a conversation, and the events of a turn that
// build it. No Node here, so the page folds a turn's events with the same code the main process
// stores them with.
import type { AgentId } from "./agentKinds";

/** What a turn did to one file of the library. */
export type ChangeKind = "added" | "modified" | "deleted";

/** One file a turn changed, as its review card lists it. */
export interface TurnChange {
  /** Library-relative, "/"-separated. */
  path: string;
  kind: ChangeKind;
  /** False for an attachment the snapshot could only note the size and time of: it cannot be put back. */
  restorable: boolean;
  /** Taken back since, on its own or with the whole turn. */
  reverted: boolean;
  /** For text, the lines it gained and lost. */
  lines?: { added: number; removed: number };
}

/** What the figure shows while a tool runs: 思考, 搜索, 读取, 写入 or 运行命令. */
export type AgentActivity = "thinking" | "searching" | "reading" | "writing" | "running";

export type AgentEvent =
  /** The agent's own id for the conversation, to continue it next turn. */
  | { kind: "session"; id: string }
  /** More of the reply. */
  | { kind: "text"; text: string }
  /** A tool call began: what it is and what it works on. */
  | { kind: "tool"; id: string; name: string; activity: AgentActivity; detail: string; /** The file it writes, as the agent named it. */ writes?: string }
  /** A tool call still being written by the model (a whole homepage, say): how much so far, and what it works on once that is known. */
  | { kind: "toolInput"; id: string; size: number; detail?: string }
  | { kind: "toolDone"; id: string; failed: boolean }
  /** 执行前询问: the agent waits for the user to allow (or not) a tool call it is about to make. */
  | { kind: "approval"; id: string; name: string; activity: AgentActivity; detail: string; /** The call as the agent sent it: main keeps it to answer with, the page never sees it. */ input?: Record<string, unknown> }
  /** The user answered it (or the turn went on without an answer). */
  | { kind: "approvalDone"; id: string; allowed: boolean }
  /** The agent finished, or failed with a message. */
  | { kind: "result"; failed?: string };

/** How a turn ends: what it changed, to review and take back. */
export interface TurnEnd {
  kind: "end";
  /** Its id among the snapshots. */
  turn?: string;
  /** Its operation-log entry, when it changed anything in the library. */
  entry?: string;
  /** What it changed in the library. */
  changes: TurnChange[];
  /** Files it wrote outside the library, by real path: no snapshot has them, so they can't be undone. */
  outside?: string[];
  /** Where its review card stands, when it changed anything. */
  review?: ReviewState;
  failed?: string;
}

/** A turn's review (写入审查): waiting on the card, kept, or taken back whole. */
export type ReviewState = "pending" | "kept" | "reverted";

/** What the review card asks of a turn: keep it all, or take back (撤回) a note or the turn. */
export type ReviewChoice = "keep" | "revert";

/** A change the review card can still take back. */
export const canRevert = (change: TurnChange) => change.restorable && !change.reverted;

/** One turn's events: the agent's, then the end with what the turn changed. */
export type TurnEvent = AgentEvent | TurnEnd;

/** A tool call, one line of a reply's timeline. */
export interface Step {
  id: string;
  name: string;
  activity: AgentActivity;
  detail: string;
  done: boolean;
  failed: boolean;
  /** While the model is still writing the call: its length so far, in characters. */
  size?: number;
}

/** A reply is its text with the tool calls between, consecutive calls folded into one timeline. */
export type ReplyPart = { kind: "text"; text: string } | { kind: "steps"; steps: Step[] };

export interface UserMessage {
  role: "user";
  text: string;
  /** Notes put in the context, library-relative. */
  notes: string[];
}

export interface Reply {
  role: "assistant";
  parts: ReplyPart[];
  /** The turn is over. */
  done: boolean;
  failed?: string;
  /** What the turn changed in the library, once it is over. */
  changes?: TurnChange[];
  /** The turn among the snapshots, and its operation-log entry. */
  turn?: string;
  entry?: string;
  /** Files it wrote outside the library, which can't be undone. */
  outside?: string[];
  review?: ReviewState;
  /** A tool call waiting for the user to allow it (执行前询问). */
  asking?: Approval;
}

/** A tool call the agent asks to make, as the 助手栏 shows it. */
export interface Approval {
  id: string;
  name: string;
  activity: AgentActivity;
  detail: string;
}

/** 助手权限: ask before a command or a file outside the folder, or run with full permissions. */
export type PermissionMode = "ask" | "full";

export type Message = UserMessage | Reply;

export interface Conversation {
  id: string;
  /** Chosen when it began; it stays. */
  agent: AgentId;
  /** The library. */
  root: string;
  /** The working directory, library-relative, fixed when it began. */
  folder: string;
  /** The agent's own id for it, to continue it. */
  session?: string;
  /** The model chosen when it began, passed on every turn; none leaves it to the agent's settings. */
  model?: string;
  /** ISO 8601. */
  created: string;
  /** ISO 8601: when it was last kept. */
  updated?: string;
  messages: Message[];
}

/** A conversation as 对话历史 lists it. */
export interface ConversationSummary {
  id: string;
  agent: AgentId;
  folder: string;
  /** The first line of its first message. */
  title: string;
  /** ISO 8601: when it was last kept. */
  updated: string;
}

/** What a turn ends with when the user stopped it, or the app quit in the middle of it. */
export const stoppedTurn = "已停止。";

export const emptyReply = (): Reply => ({ role: "assistant", parts: [], done: false });

const mapStep = (parts: ReplyPart[], id: string, change: (step: Step) => Step): ReplyPart[] =>
  parts.map((part) => (part.kind === "steps" && part.steps.some((s) => s.id === id) ? { kind: "steps", steps: part.steps.map((s) => (s.id === id ? change(s) : s)) } : part));

/** The reply with one more event of its turn. */
export function addEvent(reply: Reply, event: TurnEvent): Reply {
  const parts = [...reply.parts];
  const last = parts.at(-1);
  switch (event.kind) {
    case "text":
      if (last?.kind === "text") parts[parts.length - 1] = { kind: "text", text: last.text + event.text };
      else parts.push({ kind: "text", text: event.text });
      return { ...reply, parts };
    case "tool": {
      // The same call again, now whole (it showed while the model wrote it): the step takes what it says.
      if (parts.some((part) => part.kind === "steps" && part.steps.some((s) => s.id === event.id)))
        return { ...reply, parts: mapStep(parts, event.id, (s) => ({ ...s, name: event.name, activity: event.activity, detail: event.detail || s.detail, size: undefined })) };
      const step: Step = { id: event.id, name: event.name, activity: event.activity, detail: event.detail, done: false, failed: false };
      if (last?.kind === "steps") parts[parts.length - 1] = { kind: "steps", steps: [...last.steps, step] };
      else parts.push({ kind: "steps", steps: [step] });
      return { ...reply, parts };
    }
    case "toolInput":
      return { ...reply, parts: mapStep(parts, event.id, (s) => ({ ...s, size: event.size, ...(event.detail ? { detail: event.detail } : {}) })) };
    case "toolDone":
      return {
        ...reply,
        parts: parts.map((part) =>
          part.kind === "steps" ? { kind: "steps", steps: part.steps.map((s) => (s.id === event.id ? { ...s, done: true, failed: event.failed } : s)) } : part,
        ),
      };
    case "approval": {
      const { kind: _, input: __, ...asking } = event;
      return { ...reply, asking };
    }
    case "approvalDone": {
      if (reply.asking?.id !== event.id) return reply;
      const { asking: _, ...rest } = reply;
      return rest;
    }
    case "end": {
      const { kind: _, ...end } = event;
      const { asking: __, ...rest } = reply;
      return { ...rest, ...end, done: true };
    }
    default:
      return reply;
  }
}

/**
 * The conversation with one more event of its running turn: the reply at its end grows, and the
 * agent's session id is kept to continue it. The one rule main keeps a conversation by and the
 * 助手栏 shows it by.
 */
export function withEvent(conversation: Conversation, event: TurnEvent): Conversation {
  const messages = [...conversation.messages];
  const reply = messages.at(-1);
  if (reply?.role === "assistant") messages[messages.length - 1] = addEvent(reply, event);
  return { ...conversation, messages, ...(event.kind === "session" ? { session: event.id } : {}) };
}
