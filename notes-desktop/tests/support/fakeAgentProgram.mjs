// A fake command-line agent for tests (assistant-spec, 接缝 B): it speaks the output of the agent it stands
// in for, as the app's adapter reads it, plays a script of replies, tool calls and file writes, and never
// reaches a model. FAKE_AGENT_DIALECT says which agent: "claude" (print mode, stream-json with partial
// messages), "codex" (`codex exec --json`), "pi" (`pi --mode json`) or "dsh" (`dsh --profile headless --json`);
// the shapes follow what those CLIs printed (see tests/core/agentOutput). Each run appends what it was given
// (arguments, working directory, the prompt read from stdin, the permission mode DeepSeek Harness reads) to
// FAKE_AGENT_LOG as one JSON line.
//
// FAKE_AGENT_SCRIPT is a JSON file: { "session": "s1", "steps": [step…] }, each step one of
//   { "say": "text" }                                  a reply (streamed in pieces where the agent streams)
//   { "tool": "Write", "input": {…}, "write": { "path": "a.md", "text": "…" }, "waitFor": "/abs/file" }
//                                                      a tool call, by the agent's own name for it (for Codex, an item
//                                                      type: "command_execution", "file_change", "web_search"; any
//                                                      other is an MCP tool); `write` changes a file (relative to the
//                                                      working directory); `waitFor` holds the call open until that
//                                                      file exists
//   { "waitFor": "/abs/file" }                         holds until that file exists (so a test can look mid-turn)
//   { "fail": "message" }                              fails as that agent does
// For "dsh", `"tooOld": true` in the script answers as a DeepSeek Harness too old for JSON events does.
// `"models": ["gpt-a", …]` (Codex) or `["provider/id", …]` (Pi) is what listing its models prints.
// When FAKE_AGENT_SCRIPT names a JSON array, each run takes the next script (by how many runs the log holds).
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const stdin = await new Promise((done) => {
  let text = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => (text += chunk));
  process.stdin.on("end", () => done(text));
});

const argv = process.argv.slice(2);
const dialect = process.env.FAKE_AGENT_DIALECT ?? "claude";
const logFile = process.env.FAKE_AGENT_LOG;
const runs = logFile && existsSync(logFile) ? readFileSync(logFile, "utf8").split("\n").filter(Boolean).length : 0;
const permissionMode = process.env.DSH_PERMISSION_MODE;
const loaded = process.env.FAKE_AGENT_SCRIPT ? JSON.parse(readFileSync(process.env.FAKE_AGENT_SCRIPT, "utf8")) : { steps: [] };
// Listing its models (`codex debug models`, `pi --list-models`) is not a run: it prints the script's
// "models" as that agent does, or fails when the script has none, and is not logged.
const listing = (dialect === "codex" && argv[0] === "debug" && argv[1] === "models") || (dialect === "pi" && argv.includes("--list-models"));
if (listing) {
  const models = (Array.isArray(loaded) ? loaded[0] : loaded)?.models;
  if (!models) process.exit(1);
  if (dialect === "codex") {
    process.stdout.write(JSON.stringify({ models: models.map((slug, priority) => ({ slug, display_name: slug, visibility: "list", priority })) }, null, 2) + "\n");
  } else {
    const width = Math.max(5, ...models.map((m) => m.split("/")[1].length));
    process.stdout.write(["provider", "model".padEnd(width), "context", "max-out", "thinking", "images"].join(" ") + "\n");
    for (const m of models) process.stdout.write([m.split("/")[0].padEnd(8), m.split("/")[1].padEnd(width), "200K   ", "64K    ", "yes     ", "yes"].join(" ") + "\n");
  }
  process.exit(0);
}
if (logFile) appendFileSync(logFile, JSON.stringify({ argv, cwd: process.cwd(), stdin, ...(permissionMode ? { permissionMode } : {}) }) + "\n");

const script = Array.isArray(loaded) ? loaded[Math.min(runs, loaded.length - 1)] : loaded;
const after = (flag) => (argv.indexOf(flag) >= 0 ? argv[argv.indexOf(flag) + 1] : undefined);
const resumed = {
  claude: () => after("--resume"),
  codex: () => (argv[1] === "resume" ? argv.at(-2) : undefined),
  pi: () => after("--session"),
  dsh: () => after("--session-id"),
}[dialect]();
const session = resumed ?? script.session ?? "fake-session";

const line = (value) => process.stdout.write(JSON.stringify(value) + "\n");
const pause = (ms) => new Promise((done) => setTimeout(done, ms));
const pieces = (text) => text.match(/[\s\S]{1,4}/g) ?? [];
const doWrite = (step) => {
  if (!step.write) return;
  const file = resolve(process.cwd(), step.write.path);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, step.write.text);
};
const hold = async (file) => {
  while (!existsSync(file)) await pause(20);
};

// Each dialect: how a run opens, says something, calls a tool, fails and ends.
const dialects = {
  claude: () => {
    const emit = (value) => line({ ...value, session_id: session });
    let message = 0;
    let tool = 0;
    const replies = [];
    return {
      open: () => emit({ type: "system", subtype: "init", cwd: process.cwd(), tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] }),
      say: async (text) => {
        const id = `msg_${++message}`;
        emit({ type: "stream_event", event: { type: "message_start", message: { id, role: "assistant", content: [] } } });
        emit({ type: "stream_event", event: { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } } });
        for (const piece of pieces(text)) {
          emit({ type: "stream_event", event: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: piece } } });
          await pause(5);
        }
        emit({ type: "stream_event", event: { type: "content_block_stop", index: 0 } });
        emit({ type: "assistant", message: { id, role: "assistant", content: [{ type: "text", text }] } });
        emit({ type: "stream_event", event: { type: "message_stop" } });
        replies.push(text);
      },
      tool: async (step, run) => {
        const id = `msg_${++message}`;
        const use = `toolu_${++tool}`;
        emit({ type: "stream_event", event: { type: "message_start", message: { id, role: "assistant", content: [] } } });
        emit({ type: "assistant", message: { id, role: "assistant", content: [{ type: "tool_use", id: use, name: step.tool, input: step.input ?? {} }] } });
        await run();
        emit({ type: "user", message: { role: "user", content: [{ type: "tool_result", tool_use_id: use, content: "ok", is_error: Boolean(step.toolFails) }] } });
      },
      fail: (message) => {
        process.stderr.write(message + "\n");
        process.exit(1);
      },
      end: () => emit({ type: "result", subtype: "success", is_error: false, result: replies.join("\n\n"), num_turns: message }),
    };
  },
  codex: () => {
    let item = 0;
    return {
      open: () => {
        line({ type: "thread.started", thread_id: session });
        line({ type: "turn.started" });
      },
      say: async (text) => line({ type: "item.completed", item: { id: `item_${item++}`, type: "agent_message", text } }),
      tool: async (step, run) => {
        const id = `item_${item++}`;
        const input = step.input ?? {};
        const shape =
          step.tool === "command_execution"
            ? { type: "command_execution", command: `/bin/bash -lc '${input.command ?? ""}'`, aggregated_output: "", exit_code: null, status: "in_progress" }
            : step.tool === "file_change"
              ? { type: "file_change", changes: [{ path: resolve(process.cwd(), step.write?.path ?? input.path ?? ""), kind: "update" }], status: "in_progress" }
              : step.tool === "web_search"
                ? { type: "web_search", query: input.query ?? "" }
                : { type: "mcp_tool_call", server: "fake", tool: step.tool, arguments: input, status: "in_progress" };
        line({ type: "item.started", item: { id, ...shape } });
        await run();
        const failed = Boolean(step.toolFails);
        const done = shape.type === "command_execution" ? { exit_code: failed ? 1 : 0, status: failed ? "failed" : "completed" } : { status: failed ? "failed" : "completed" };
        line({ type: "item.completed", item: { id, ...shape, ...done } });
      },
      fail: (message) => {
        line({ type: "error", message });
        line({ type: "turn.failed", error: { message } });
        process.exit(1);
      },
      end: () => line({ type: "turn.completed", usage: { input_tokens: 1, cached_input_tokens: 0, output_tokens: 1, reasoning_output_tokens: 0 } }),
    };
  },
  pi: () => {
    let call = 0;
    const assistant = (extra) => ({ role: "assistant", content: [], api: "fake", provider: "fake", model: "fake", ...extra });
    return {
      open: () => {
        line({ type: "session", version: 3, id: session, timestamp: new Date().toISOString(), cwd: process.cwd() });
        line({ type: "agent_start" });
        line({ type: "turn_start" });
      },
      say: async (text) => {
        line({ type: "message_start", message: assistant({ stopReason: "pending" }) });
        line({ type: "message_update", assistantMessageEvent: { type: "text_start", contentIndex: 0 } });
        for (const piece of pieces(text)) {
          line({ type: "message_update", assistantMessageEvent: { type: "text_delta", contentIndex: 0, delta: piece } });
          await pause(5);
        }
        line({ type: "message_update", assistantMessageEvent: { type: "text_end", contentIndex: 0, content: text } });
        line({ type: "message_end", message: assistant({ content: [{ type: "text", text }], stopReason: "stop" }) });
      },
      tool: async (step, run) => {
        const id = `call_${++call}`;
        const args = step.input ?? {};
        line({ type: "message_end", message: assistant({ content: [{ type: "toolCall", id, name: step.tool, arguments: args }], stopReason: "toolUse" }) });
        line({ type: "tool_execution_start", toolCallId: id, toolName: step.tool, args });
        await run();
        line({ type: "tool_execution_end", toolCallId: id, toolName: step.tool, result: { content: [{ type: "text", text: "ok" }] }, isError: Boolean(step.toolFails) });
      },
      // Pi exits 0 when the model service fails: the reply's stopReason says so.
      fail: (message) => {
        line({ type: "message_end", message: assistant({ stopReason: "error", errorMessage: message }) });
        line({ type: "agent_end", messages: [], willRetry: false });
        line({ type: "agent_settled", aborted: false });
        process.exit(0);
      },
      end: () => {
        line({ type: "agent_end", messages: [], willRetry: false });
        line({ type: "agent_settled", aborted: false });
      },
    };
  },
  dsh: () => {
    let call = 0;
    let last = "";
    return {
      open: () => {
        // DeepSeek Harness before 0.1.7 has no JSON events: it stops at the flag, as 0.1.5 does.
        if (script.tooOld) {
          process.stderr.write("error: unknown option '--json'\n");
          process.exit(1);
        }
        if (after("--session-id") && script.unknownSession) {
          line({ type: "error", message: `session "${session}" does not exist; omit --session-id to start a new Session` });
          process.exit(1);
        }
        line({ type: "session", sessionId: session, cwd: process.cwd() });
        line({ type: "status", phase: "turn_start", turn: 1 });
      },
      say: async (text) => {
        line({ type: "text", text });
        last = text;
      },
      tool: async (step, run) => {
        const callId = `toolu_${++call}`;
        line({ type: "tool_call", callId, tool: step.tool, input: step.input ?? {} });
        await run();
        line({ type: "tool_result", callId, status: step.toolFails ? "error" : "completed", result: "ok" });
      },
      fail: (message) => {
        line({ type: "status", phase: "turn_end", turn: 1, reason: { kind: "error", error: { message, code: "FAKE" } } });
        line({ type: "final", text: "" });
        process.stderr.write(`dsh: FAKE: ${message}\n`);
        process.exit(1);
      },
      end: () => {
        line({ type: "status", phase: "turn_end", turn: 1, reason: { kind: "completed" } });
        line({ type: "final", text: last });
      },
    };
  },
};

const agent = dialects[dialect]();
agent.open();
for (const step of script.steps ?? []) {
  if (step.say !== undefined) await agent.say(step.say);
  else if (step.tool !== undefined)
    await agent.tool(step, async () => {
      doWrite(step);
      await pause(5);
      if (step.waitFor) await hold(step.waitFor);
    });
  else if (step.waitFor !== undefined) await hold(step.waitFor);
  else if (step.fail !== undefined) agent.fail(step.fail);
}
agent.end();
