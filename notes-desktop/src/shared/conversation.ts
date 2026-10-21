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
  | { kind: "toolDone"; id: string; failed: boolean }
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
  failed?: string;
}

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
}

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
  /** ISO 8601. */
  created: string;
  messages: Message[];
}

export const emptyReply = (): Reply => ({ role: "assistant", parts: [], done: false });

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
      const step: Step = { id: event.id, name: event.name, activity: event.activity, detail: event.detail, done: false, failed: false };
      if (last?.kind === "steps") parts[parts.length - 1] = { kind: "steps", steps: [...last.steps, step] };
      else parts.push({ kind: "steps", steps: [step] });
      return { ...reply, parts };
    }
    case "toolDone":
      return {
        ...reply,
        parts: parts.map((part) =>
          part.kind === "steps" ? { kind: "steps", steps: part.steps.map((s) => (s.id === event.id ? { ...s, done: true, failed: event.failed } : s)) } : part,
        ),
      };
    case "end": {
      const { kind: _, ...end } = event;
      return { ...reply, ...end, done: true };
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
