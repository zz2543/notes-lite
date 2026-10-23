// What a command-line agent says during 一轮, read from its output into the events the 助手栏 shows
// (their types live in shared/conversation, where the page folds them too).
import type { AgentId } from "../shared/agentKinds";
import type { AgentActivity, AgentEvent, PermissionMode } from "../shared/conversation";

export type { AgentActivity, AgentEvent, TurnEvent } from "../shared/conversation";

/** How one agent is run and read. */
export interface AgentAdapter {
  /**
   * The command line after the command; the prompt goes in on stdin. `model`, when chosen, overrides
   * the agent's own. `mode` 执行前询问 ("ask") runs it as `limits` says; full permissions otherwise.
   */
  args(session?: string, model?: string, mode?: PermissionMode): string[];
  /**
   * What 执行前询问 means for it: "ask", it stops before a command (or a file outside the folder) until
   * the user answers; "sandbox", it can't ask, so it runs shut in the folder without network; none, it
   * has no such mode and runs with full permissions either way.
   */
  limits?: "ask" | "sandbox";
  /** When it asks: what goes on stdin first (stdin then stays open for the answers, until its result). */
  input?(prompt: string): string;
  /** When it asks: the line that answers its `approval`. */
  answer?(approval: Extract<AgentEvent, { kind: "approval" }>, allowed: boolean): string;
  /** What it needs in its environment besides what the app passes on. */
  env?: Record<string, string>;
  /** Reads its output a line at a time. */
  reader(cwd: string): (line: string) => AgentEvent[];
  /** What to tell the user when it exits in error with this on stderr, if it means more than it says. */
  explainExit?(stderr: string): string | undefined;
}

/** One line of JSON output; anything else on stdout (a warning, say) is not the agent's. */
function parse<T>(raw: string): T | null {
  try {
    const value: unknown = JSON.parse(raw);
    return typeof value === "object" && value !== null ? (value as T) : null;
  } catch {
    return null;
  }
}

/** Replies that come whole, one after another, read as paragraphs. */
function paragraphs() {
  let last: "text" | "other" = "other";
  return (event: AgentEvent): AgentEvent => {
    const follows = last === "text";
    last = event.kind === "text" ? "text" : event.kind === "session" ? last : "other";
    return event.kind === "text" && follows ? { kind: "text", text: `\n\n${event.text}` } : event;
  };
}

// Tool names as Claude Code calls them, and as Pi and DeepSeek Harness do (lower case).
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
  read: "reading",
  read_image: "reading",
  ls: "reading",
  find: "searching",
  glob: "searching",
  grep: "searching",
  web_search: "searching",
  web_fetch: "searching",
  write: "writing",
  edit: "writing",
  bash: "running",
  powershell: "running",
  job_output: "running",
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

/** What a tool call works on, read from the start of its input while the model is still writing it. */
function partialDetail(json: string, cwd: string): string | undefined {
  const field = /"(?:file_path|notebook_path|path|command|pattern)"\s*:\s*"((?:[^"\\]|\\.)*)"/.exec(json);
  if (!field) return undefined;
  try {
    const value = JSON.parse(`"${field[1]}"`) as string;
    return /"(?:file_path|notebook_path|path)"/.test(field[0]) ? shortPath(value, cwd) : value;
  } catch {
    return undefined;
  }
}

/** A tool call began: what the figure shows of it, and what it works on. */
const toolEvent = (id: string, name: string, input: Record<string, unknown>, cwd: string): AgentEvent => ({
  kind: "tool",
  id,
  name,
  activity: activities[name] ?? "thinking",
  detail: detailOf(input, cwd),
});

/** Why a turn failed when the agent does not say. */
const unfinishedTurn = "Agent 没有完成这一轮。";

interface ClaudeLine {
  type?: string;
  /** A control request (执行前询问): the stdio permission prompt asking about a tool call. */
  request_id?: string;
  request?: { subtype?: string; tool_name?: string; input?: Record<string, unknown> };
  subtype?: string;
  session_id?: string;
  is_error?: boolean;
  result?: string;
  event?: {
    type?: string;
    index?: number;
    message?: { id?: string };
    content_block?: { type?: string; id?: string; name?: string };
    delta?: { type?: string; text?: string; partial_json?: string };
  };
  message?: { id?: string; content?: Array<{ type?: string; text?: string; id?: string; name?: string; input?: Record<string, unknown>; tool_use_id?: string; is_error?: boolean }> };
}

/**
 * Claude Code in print mode: `-p` with stream-json output (which needs --verbose), partial messages for
 * a reply that streams, and --dangerously-skip-permissions so it never stops to ask (assistant-spec).
 */
export const claudeCode: AgentAdapter = {
  args: (session, model, mode) => [
    "-p",
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
    // 执行前询问: edits in the folder go ahead (each turn can be undone); commands, the web and files
    // elsewhere ask, through the stdio permission prompt, which needs the prompt as stream-json too.
    ...(mode === "ask"
      ? ["--input-format", "stream-json", "--permission-prompt-tool", "stdio", "--permission-mode", "acceptEdits"]
      : ["--dangerously-skip-permissions"]),
    ...(model ? ["--model", model] : []),
    ...(session ? ["--resume", session] : []),
  ],
  limits: "ask",
  input: (prompt) =>
    [
      { type: "control_request", request_id: "notes-init", request: { subtype: "initialize", hooks: null } },
      { type: "user", session_id: "", parent_tool_use_id: null, message: { role: "user", content: [{ type: "text", text: prompt }] } },
    ]
      .map((line) => JSON.stringify(line) + "\n")
      .join(""),
  answer: (approval, allowed) =>
    JSON.stringify({
      type: "control_response",
      response: {
        subtype: "success",
        request_id: approval.id,
        response: allowed ? { behavior: "allow", updatedInput: approval.input ?? {} } : { behavior: "deny", message: "用户没有允许这个操作。请换一种不需要它的做法，或者说明为什么需要。" },
      },
    }) + "\n",
  reader: (cwd) => {
    // A message whose text came in pieces arrives whole afterwards too; that copy is not shown again.
    const streamed = new Set<string>();
    let current: string | undefined;
    let session: string | undefined;
    // Tool calls the model is still writing, by block: shown at once, and how far along (a homepage can take minutes).
    const writing = new Map<number, { id: string; name: string; json: string; shown: number; detail?: string }>();
    return (raw) => {
      const line = parse<ClaudeLine>(raw);
      if (!line) return [];
      const events: AgentEvent[] = [];
      if (line.session_id && line.session_id !== session) {
        session = line.session_id;
        events.push({ kind: "session", id: session });
      }
      if (line.type === "control_request" && line.request?.subtype === "can_use_tool" && line.request_id && line.request.tool_name) {
        const input = line.request.input ?? {};
        const { id: _, kind: __, ...call } = toolEvent(line.request_id, line.request.tool_name, input, cwd) as Extract<AgentEvent, { kind: "tool" }>;
        events.push({ kind: "approval", id: line.request_id, ...call, input });
      } else if (line.type === "stream_event") {
        const event = line.event;
        if (event?.type === "message_start") current = event.message?.id;
        const block = event?.content_block;
        if (event?.type === "content_block_start" && block?.type === "tool_use" && block.id && block.name) {
          writing.set(event.index ?? 0, { id: block.id, name: block.name, json: "", shown: 0 });
          events.push(toolEvent(block.id, block.name, {}, cwd));
        }
        const call = writing.get(event?.index ?? 0);
        if (event?.type === "content_block_delta" && event.delta?.type === "input_json_delta" && call) {
          call.json += event.delta.partial_json ?? "";
          const found = call.detail ? undefined : partialDetail(call.json, cwd);
          if (found) call.detail = found;
          if (found || call.json.length - call.shown >= 1024) {
            call.shown = call.json.length;
            events.push({ kind: "toolInput", id: call.id, size: call.json.length, ...(found ? { detail: found } : {}) });
          }
        }
        if (event?.type === "content_block_stop") writing.delete(event.index ?? 0);
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
            const writes = activities[block.name] === "writing" ? pathOf(input) : undefined;
            events.push({ ...toolEvent(block.id, block.name, input, cwd), ...(writes ? { writes } : {}) } as AgentEvent);
          }
        }
      } else if (line.type === "user") {
        for (const block of line.message?.content ?? [])
          if (block.type === "tool_result" && block.tool_use_id) events.push({ kind: "toolDone", id: block.tool_use_id, failed: Boolean(block.is_error) });
      } else if (line.type === "result") {
        events.push(line.is_error ? { kind: "result", failed: line.result || unfinishedTurn } : { kind: "result" });
      }
      return events;
    };
  },
};

/** A shell command as the timeline shows it: what the agent asked for, without the shell that runs it. */
function commandOf(command: string): string {
  const wrapped = /^(?:\S*[\\/])?(?:ba|z)?sh -l?c (['"])([\s\S]*)\1$/.exec(command.trim());
  return wrapped ? wrapped[2]! : command;
}

interface CodexItem {
  id?: string;
  type?: string;
  text?: string;
  command?: string;
  exit_code?: number | null;
  status?: string;
  changes?: Array<{ path?: string }>;
  query?: string;
  server?: string;
  tool?: string;
}

interface CodexLine {
  type?: string;
  thread_id?: string;
  item?: CodexItem;
  error?: { message?: string };
  message?: string;
}

/**
 * Codex (`codex exec`): JSON events, the prompt on stdin (`-`), with neither sandbox nor approvals
 * (`--dangerously-bypass-approvals-and-sandbox`), outside a Git repository too. A thread goes on with
 * `exec resume <id>`. Replies come whole, not streamed.
 */
export const codex: AgentAdapter = {
  limits: "sandbox",
  args: (session, model, mode) => {
    // 执行前询问: codex exec can't ask, so it is shut in the folder without network instead.
    // The override goes before the subcommand, where `exec resume` takes it too.
    const sandbox = mode === "ask" ? ["-c", "sandbox_mode=workspace-write"] : [];
    const options = ["--json", "--skip-git-repo-check", ...(mode === "ask" ? [] : ["--dangerously-bypass-approvals-and-sandbox"]), ...(model ? ["-m", model] : [])];
    return session ? [...sandbox, "exec", "resume", ...options, session, "-"] : [...sandbox, "exec", ...options, "-"];
  },
  reader: (cwd) => {
    const started = new Set<string>();
    const paragraph = paragraphs();
    const step = (item: CodexItem): Omit<Extract<AgentEvent, { kind: "tool" }>, "id" | "kind"> | null => {
      switch (item.type) {
        case "command_execution":
          return { name: "命令", activity: "running", detail: commandOf(item.command ?? "") };
        case "file_change":
          return { name: "改文件", activity: "writing", detail: (item.changes ?? []).map((c) => shortPath(c.path ?? "", cwd)).join("、") };
        case "web_search":
          return { name: "搜索网页", activity: "searching", detail: item.query ?? "" };
        case "mcp_tool_call":
          return { name: item.tool ?? "工具", activity: "thinking", detail: item.server ?? "" };
        default:
          return null;
      }
    };
    return (raw) => {
      const line = parse<CodexLine>(raw);
      if (!line) return [];
      const events: AgentEvent[] = [];
      const item = line.item;
      if (line.type === "thread.started" && line.thread_id) events.push({ kind: "session", id: line.thread_id });
      else if ((line.type === "item.started" || line.type === "item.completed") && item?.id) {
        if (item.type === "agent_message" && line.type === "item.completed" && item.text) events.push({ kind: "text", text: item.text });
        const tool = step(item);
        if (tool && !started.has(item.id)) {
          started.add(item.id);
          events.push({ kind: "tool", id: item.id, ...tool });
        }
        if (tool && line.type === "item.completed") {
          const failed = item.status === "failed" || item.status === "declined" || (typeof item.exit_code === "number" && item.exit_code !== 0);
          events.push({ kind: "toolDone", id: item.id, failed });
        }
      } else if (line.type === "turn.completed") events.push({ kind: "result" });
      else if (line.type === "turn.failed") events.push({ kind: "result", failed: line.error?.message || unfinishedTurn });
      // A top-level `error` is also how Codex says it is reconnecting; the turn's end says whether it failed.
      return events.map(paragraph);
    };
  },
};

interface PiMessage {
  role?: string;
  stopReason?: string;
  errorMessage?: string;
}

interface PiLine {
  type?: string;
  id?: string;
  message?: PiMessage;
  assistantMessageEvent?: { type?: string; delta?: string };
  toolCallId?: string;
  toolName?: string;
  args?: Record<string, unknown>;
  isError?: boolean;
}

/**
 * Pi in JSON mode (`--mode json`): the prompt on stdin. Pi never asks before a tool runs, so it has full
 * permissions as it is. It exits 0 when the model service fails too: the assistant message's
 * `stopReason` says so. A session goes on with `--session <id>`.
 */
export const pi: AgentAdapter = {
  args: (session, model) => ["--mode", "json", ...(model ? ["--model", model] : []), ...(session ? ["--session", session] : [])],
  reader: (cwd) => {
    let failed: string | undefined;
    return (raw) => {
      const line = parse<PiLine>(raw);
      if (!line) return [];
      switch (line.type) {
        case "session":
          return line.id ? [{ kind: "session", id: line.id }] : [];
        case "message_update": {
          const update = line.assistantMessageEvent;
          return update?.type === "text_delta" && update.delta ? [{ kind: "text", text: update.delta }] : [];
        }
        case "message_end":
          // The last word on a reply: it ended as asked, or with an error (which a retry may still clear).
          if (line.message?.role === "assistant")
            failed = line.message.stopReason === "error" ? line.message.errorMessage || unfinishedTurn : undefined;
          return [];
        case "tool_execution_start": {
          if (!line.toolCallId || !line.toolName) return [];
          const name = line.toolName;
          return [toolEvent(line.toolCallId, name, line.args ?? {}, cwd)];
        }
        case "tool_execution_end":
          return line.toolCallId ? [{ kind: "toolDone", id: line.toolCallId, failed: Boolean(line.isError) }] : [];
        case "agent_settled":
          return [failed ? { kind: "result", failed } : { kind: "result" }];
        default:
          return [];
      }
    };
  },
};

/** DeepSeek Harness before 0.1.7 has no `--json` (nor `--session-id`), and says so in its own words. */
const dshTooOld = "DeepSeek Harness 版本太旧，用不了助手。请在终端运行 npm install -g @deepseek-ai/dsh@latest 升级，然后再试。";

interface DshLine {
  type?: string;
  sessionId?: string;
  text?: string;
  callId?: string;
  tool?: string;
  input?: unknown;
  status?: string;
  phase?: string;
  reason?: { kind?: string; error?: { message?: string } };
  message?: string;
}

/**
 * DeepSeek Harness (`dsh`), its headless profile: JSON events, the task on stdin (`-`). Full access is
 * the `danger-full-access` permission mode, which also turns approvals off; it is chosen through the
 * environment, as the profile reads it. A session goes on with `--session-id`. Replies come whole.
 */
export const deepseekHarness: AgentAdapter = {
  // No model on the command line: DeepSeek Harness takes it from its settings alone.
  args: (session) => ["--profile", "headless", "--json", ...(session ? ["--session-id", session] : []), "-"],
  env: { DSH_PERMISSION_MODE: "danger-full-access" },
  explainExit: (stderr) => (/unknown option '--(json|session-id)'/.test(stderr) ? dshTooOld : undefined),
  reader: (cwd) => {
    const paragraph = paragraphs();
    let ended = false;
    return (raw) => {
      const line = parse<DshLine>(raw);
      if (!line) return [];
      const events: AgentEvent[] = [];
      if (line.type === "session" && line.sessionId) events.push({ kind: "session", id: line.sessionId });
      else if (line.type === "text" && line.text) events.push({ kind: "text", text: line.text });
      else if (line.type === "tool_call" && line.callId && line.tool) {
        const input = typeof line.input === "object" && line.input !== null ? (line.input as Record<string, unknown>) : {};
        events.push(toolEvent(line.callId, line.tool, input, cwd));
      } else if (line.type === "tool_result" && line.callId) events.push({ kind: "toolDone", id: line.callId, failed: line.status === "error" });
      else if (line.type === "status" && line.phase === "turn_end" && !ended) {
        ended = true;
        const kind = line.reason?.kind;
        events.push(kind === "completed" ? { kind: "result" } : { kind: "result", failed: line.reason?.error?.message || unfinishedTurn });
      } else if (line.type === "error" && !ended) {
        ended = true;
        events.push({ kind: "result", failed: line.message || unfinishedTurn });
      }
      return events.map(paragraph);
    };
  },
};

const adapters: Record<AgentId, AgentAdapter> = { claude: claudeCode, codex, dsh: deepseekHarness, pi };

/** The adapter for an agent. */
export function agentAdapter(id: AgentId): AgentAdapter {
  return adapters[id];
}
