// 对话: what the 助手栏 shows and the app keeps of a conversation. No Node here, so the page folds a
// turn's events with the same code the main process stores them with.
import type { AgentActivity, TurnEvent } from "./agentStream";
import type { AgentId } from "./agentKinds";
import type { ChangeKind } from "./snapshots";

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
  changes?: Array<{ path: string; kind: ChangeKind }>;
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
    case "end":
      return { ...reply, done: true, changes: event.changes, ...(event.failed ? { failed: event.failed } : {}) };
    default:
      return reply;
  }
}
