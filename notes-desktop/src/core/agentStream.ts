// What a command-line agent says during 一轮, read from its output into the events the 助手栏 shows
// (their types live in shared/conversation, where the page folds them too).
import type { AgentId } from "../shared/agentKinds";
import type { AgentActivity, AgentEvent } from "../shared/conversation";

export type { AgentActivity, AgentEvent, TurnEvent } from "../shared/conversation";

/** How one agent is run and read. */
export interface AgentAdapter {
  /** The command line after the command; the prompt goes in on stdin. */
  args(session?: string): string[];
  /** Reads its output a line at a time. */
  reader(cwd: string): (line: string) => AgentEvent[];
}

const activities: Record<string, AgentActivity> = {
  Read: "reading",
  NotebookRead: "reading",
  LS: "reading",
  Glob: "searching",
  Grep: "searching",
  WebSearch: "searching",
  WebFetch: "searching",
  Write: "writing",
  Edit: "writing",
  MultiEdit: "writing",
  NotebookEdit: "writing",
  Bash: "running",
  BashOutput: "running",
};

/** A path as short as the timeline can show it: relative to the working directory when inside it. */
function shortPath(path: string, cwd: string): string {
  const slashed = (p: string) => p.replace(/\\/g, "/");
  const file = slashed(path);
  const base = slashed(cwd).replace(/\/$/, "");
  return file.startsWith(`${base}/`) ? file.slice(base.length + 1) : file;
}

const textOf = (input: Record<string, unknown>, key: string) => (typeof input[key] === "string" ? (input[key] as string) : undefined);
const pathOf = (input: Record<string, unknown>) => textOf(input, "file_path") ?? textOf(input, "notebook_path") ?? textOf(input, "path");

function detailOf(input: Record<string, unknown>, cwd: string): string {
  const path = pathOf(input);
  if (path) return shortPath(path, cwd);
  return textOf(input, "command") ?? textOf(input, "pattern") ?? textOf(input, "query") ?? textOf(input, "url") ?? textOf(input, "description") ?? "";
}

interface ClaudeLine {
  type?: string;
  subtype?: string;
  session_id?: string;
  is_error?: boolean;
  result?: string;
  event?: { type?: string; message?: { id?: string }; delta?: { type?: string; text?: string } };
  message?: { id?: string; content?: Array<{ type?: string; text?: string; id?: string; name?: string; input?: Record<string, unknown>; tool_use_id?: string; is_error?: boolean }> };
}

/**
 * Claude Code in print mode: `-p` with stream-json output (which needs --verbose), partial messages for
 * a reply that streams, and --dangerously-skip-permissions so it never stops to ask (assistant-spec).
 */
export const claudeCode: AgentAdapter = {
  args: (session) => [
    "-p",
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
    "--dangerously-skip-permissions",
    ...(session ? ["--resume", session] : []),
  ],
  reader: (cwd) => {
    // A message whose text came in pieces arrives whole afterwards too; that copy is not shown again.
    const streamed = new Set<string>();
    let current: string | undefined;
    let session: string | undefined;
    return (raw) => {
      let line: ClaudeLine;
      try {
        line = JSON.parse(raw) as ClaudeLine;
      } catch {
        return [];
      }
      const events: AgentEvent[] = [];
      if (line.session_id && line.session_id !== session) {
        session = line.session_id;
        events.push({ kind: "session", id: session });
      }
      if (line.type === "stream_event") {
        const event = line.event;
        if (event?.type === "message_start") current = event.message?.id;
        if (event?.type === "content_block_delta" && event.delta?.type === "text_delta" && event.delta.text) {
          if (current) streamed.add(current);
          events.push({ kind: "text", text: event.delta.text });
        }
      } else if (line.type === "assistant") {
        const id = line.message?.id;
        for (const block of line.message?.content ?? []) {
          if (block.type === "text" && block.text && !(id && streamed.has(id))) events.push({ kind: "text", text: block.text });
          if (block.type === "tool_use" && block.id && block.name) {
            const input = block.input ?? {};
            const activity = activities[block.name] ?? "thinking";
            const writes = activity === "writing" ? pathOf(input) : undefined;
            events.push({ kind: "tool", id: block.id, name: block.name, activity, detail: detailOf(input, cwd), ...(writes ? { writes } : {}) });
          }
        }
      } else if (line.type === "user") {
        for (const block of line.message?.content ?? [])
          if (block.type === "tool_result" && block.tool_use_id) events.push({ kind: "toolDone", id: block.tool_use_id, failed: Boolean(block.is_error) });
      } else if (line.type === "result") {
        events.push(line.is_error ? { kind: "result", failed: line.result || "Agent 没有完成这一轮。" } : { kind: "result" });
      }
      return events;
    };
  },
};

/** The adapter for an agent; the others come with ticket 30. */
export function agentAdapter(id: AgentId): AgentAdapter | null {
  return id === "claude" ? claudeCode : null;
}
