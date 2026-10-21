// 一轮 (assistant-spec, ADR 0005): snapshot the library, run the agent in the working directory with
// full permissions and pass on what it says, snapshot again, and log what it changed as one entry
// that undoes the whole turn.
import { spawn } from "node:child_process";
import { join, relative } from "node:path";
import { agentAdapter, type AgentEvent, type TurnEvent } from "./agentStream";
import type { AgentId } from "../shared/agentKinds";
import { stoppedTurn } from "../shared/conversation";
import { turnEntry, type LogEntry, type OperationLog } from "./operationLog";
import type { TurnSnapshots } from "./snapshots";
import { spaceGuideName, spacesFolder, type SpaceLibrary } from "./spaces";

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
  /** The library's spaces, so a homepage it writes follows the authoring guide. */
  spaces?: TurnSpaces;
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

/** A library's spaces as a turn's context (assistant-spec 20); paths library-relative. */
export interface TurnSpaces {
  /** The authoring guide (编写说明). */
  guide: string;
  /** Each space by name, with its file. */
  spaces: Array<{ name: string; path: string }>;
  /** The space open in the app, if any. */
  open?: string;
}

/**
 * The library's spaces for a turn, the authoring guide installed so the agent can read it; undefined
 * when it has none. `open`: the space open in the app.
 */
export async function turnSpaces(library: SpaceLibrary, open?: string): Promise<TurnSpaces | undefined> {
  const spaces = await library.spaces();
  if (spaces.length === 0) return undefined;
  await library.installGuide();
  return {
    guide: spacesGuidePath,
    spaces: spaces.map(({ name, path }) => ({ name, path })),
    ...(open && spaces.some((space) => space.name === open) ? { open } : {}),
  };
}

const spacesGuidePath = `${spacesFolder}/${spaceGuideName}`;

/**
 * What the agent is asked: the user's words, then the notes in context and the library's spaces with
 * their authoring guide, paths relative to the working directory.
 */
export function turnPrompt({ root, folder, text, notes, spaces }: Pick<TurnRequest, "root" | "folder" | "text" | "notes" | "spaces">): string {
  const cwd = at(root, folder);
  const rel = (path: string) => relative(cwd, at(root, path)).split("\\").join("/");
  const parts = [text];
  if (notes.length > 0) parts.push(`附带的笔记（路径相对于当前工作目录）：\n${notes.map((note) => `- ${rel(note)}`).join("\n")}\n`);
  if (spaces)
    parts.push(
      [
        `笔记库的空间主页（路径相对于当前工作目录）。编写或修改空间主页前，请先完整阅读并遵守编写说明：${rel(spaces.guide)}`,
        ...spaces.spaces.map(({ name, path }) => `- ${name}：${rel(path)}${name === spaces.open ? "（当前打开）" : ""}`),
      ].join("\n") + "\n",
    );
  return parts.length === 1 ? text : parts.join("\n\n");
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
  const env = adapter.env ? { ...(request.env ?? process.env), ...adapter.env } : request.env;
  const cwd = at(root, folder);
  const id = await snapshots.begin();
  const outcome: TurnOutcome = {};
  let failed: string | undefined;
  try {
    failed = await new Promise<string | undefined>((done) => {
      const child = start(agent.path, adapter.args(request.session), cwd, env);
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
      // Stopped while the snapshot was still being taken: the agent goes as soon as it starts.
      if (request.signal?.aborted) stop();
      else request.signal?.addEventListener("abort", stop, { once: true });
      child.on("error", (error) => done(`无法启动 Agent：${error.message}`));
      child.on("close", (code) => {
        request.signal?.removeEventListener("abort", stop);
        if (pending) pass(pending);
        if (request.signal?.aborted) return done(stoppedTurn);
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
