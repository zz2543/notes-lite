// 一轮 (assistant-spec, ADR 0005): snapshot the library, run the agent in the working directory with
// full permissions and pass on what it says, snapshot again, and log what it changed as one entry
// that undoes the whole turn.
import { spawn } from "node:child_process";
import { join, relative } from "node:path";
import { agentAdapter, type AgentEvent, type TurnEvent } from "./agentStream";
import type { AgentId } from "./agentKinds";
import { turnEntry, type LogEntry, type OperationLog } from "./operationLog";
import type { TurnSnapshots } from "./snapshots";

export interface TurnRequest {
  agent: { id: AgentId; path: string };
  /** The library. */
  root: string;
  /** The working directory, library-relative ("" for the library itself). */
  folder: string;
  /** What the user wrote. */
  text: string;
  /** Notes put in the context, library-relative. */
  notes: string[];
  /** The agent's conversation to continue, if this is not the first turn. */
  session?: string;
  snapshots: TurnSnapshots;
  log: OperationLog;
  /** The agent's environment; this process's by default. */
  env?: NodeJS.ProcessEnv;
  /** Stops the agent. */
  signal?: AbortSignal;
  onEvent(event: TurnEvent): void;
}

export interface TurnOutcome {
  /** The agent's conversation id, to continue it. */
  session?: string;
  /** The operation-log entry, when the turn changed anything. */
  entry?: LogEntry;
  failed?: string;
}

const at = (root: string, path: string) => join(root, ...path.split("/").filter(Boolean));

/** What the agent is asked: the user's words, then the notes in context, relative to the working directory. */
export function turnPrompt({ root, folder, text, notes }: Pick<TurnRequest, "root" | "folder" | "text" | "notes">): string {
  if (notes.length === 0) return text;
  const cwd = at(root, folder);
  const listed = notes.map((note) => `- ${relative(cwd, at(root, note)).split("\\").join("/")}`);
  return `${text}\n\n附带的笔记（路径相对于当前工作目录）：\n${listed.join("\n")}\n`;
}

/** Runs the command; a Windows .cmd or .bat shim goes through the shell, which Node requires. */
function start(path: string, args: string[], cwd: string, env: NodeJS.ProcessEnv | undefined) {
  const shim = process.platform === "win32" && /\.(cmd|bat)$/i.test(path);
  // The arguments are fixed words the shell leaves alone; the prompt goes in on stdin.
  return shim
    ? spawn(`"${path}"`, args, { cwd, env, shell: true, windowsHide: true })
    : spawn(path, args, { cwd, env, windowsHide: true });
}

/** One turn, start to end; never throws for the agent's failures, which arrive as `failed`. */
export async function runTurn(request: TurnRequest): Promise<TurnOutcome> {
  const { agent, root, folder, snapshots, log, onEvent } = request;
  const adapter = agentAdapter(agent.id);
  if (!adapter) {
    const failed = "这个 Agent 还不能在助手栏里使用。";
    onEvent({ kind: "end", changes: [], failed });
    return { failed };
  }
  const cwd = at(root, folder);
  const id = await snapshots.begin();
  const outcome: TurnOutcome = {};
  let failed: string | undefined;
  try {
    failed = await new Promise<string | undefined>((done) => {
      const child = start(agent.path, adapter.args(request.session), cwd, request.env);
      const read = adapter.reader(cwd);
      let result: AgentEvent | undefined;
      let stderr = "";
      let pending = "";
      const pass = (line: string) => {
        for (const event of read(line)) {
          if (event.kind === "session") outcome.session = event.id;
          if (event.kind === "result") result = event;
          else onEvent(event);
        }
      };
      child.stdout.setEncoding("utf8");
      child.stdout.on("data", (chunk: string) => {
        pending += chunk;
        const lines = pending.split("\n");
        pending = lines.pop()!;
        lines.forEach(pass);
      });
      child.stderr.setEncoding("utf8");
      child.stderr.on("data", (chunk: string) => (stderr = (stderr + chunk).slice(-2000)));
      // On Windows the shim's shell would go and leave the agent running; the whole tree goes there.
      const stop = () =>
        process.platform === "win32" && child.pid
          ? spawn("taskkill", ["/pid", String(child.pid), "/T", "/F"], { windowsHide: true }).on("error", () => child.kill())
          : child.kill();
      request.signal?.addEventListener("abort", stop, { once: true });
      child.on("error", (error) => done(`无法启动 Agent：${error.message}`));
      child.on("close", (code) => {
        request.signal?.removeEventListener("abort", stop);
        if (pending) pass(pending);
        if (request.signal?.aborted) return done("已停止。");
        if (result?.kind === "result" && result.failed) return done(result.failed);
        if (code !== 0) return done(stderr.trim() || `Agent 异常退出（代码 ${code}）。`);
        done(undefined);
      });
      child.stdin.on("error", () => {});
      child.stdin.end(turnPrompt(request));
    });
  } finally {
    // Whatever happened, what the agent changed is listed and can be undone.
    const turn = await snapshots.finish(id);
    const changes = turn.changes.map(({ path, kind }) => ({ path, kind }));
    if (changes.length > 0) [outcome.entry] = await log.record([turnEntry(turn)]);
    if (failed) outcome.failed = failed;
    onEvent({ kind: "end", changes, ...(failed ? { failed } : {}) });
  }
  return outcome;
}
