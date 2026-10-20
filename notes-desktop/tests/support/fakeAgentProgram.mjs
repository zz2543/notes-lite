// A fake Claude Code for tests (assistant-spec, 接缝 B): it speaks Claude Code's print mode with
// `--output-format stream-json --verbose --include-partial-messages`, plays a script of replies, tool
// calls and file writes, and never reaches a model. Each run appends what it was given (arguments,
// working directory, the prompt read from stdin) to FAKE_AGENT_LOG as one JSON line.
//
// FAKE_AGENT_SCRIPT is a JSON file: { "session": "s1", "steps": [step…] }, each step one of
//   { "say": "text" }                                  a reply, streamed in pieces
//   { "tool": "Write", "input": {…}, "write": { "path": "a.md", "text": "…" }, "waitFor": "/abs/file" }
//                                                      a tool call; `write` changes a file (relative to the working
//                                                      directory); `waitFor` holds the call open until that file exists
//   { "waitFor": "/abs/file" }                         holds until that file exists (so a test can look mid-turn)
//   { "fail": "message" }                              stops with an error on stderr and exit code 1
// When FAKE_AGENT_SCRIPT names a JSON array, each run takes the next script (by how many runs the log holds).
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const stdin = await new Promise((done) => {
  let text = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => (text += chunk));
  process.stdin.on("end", () => done(text));
});

const logFile = process.env.FAKE_AGENT_LOG;
const runs = logFile && existsSync(logFile) ? readFileSync(logFile, "utf8").split("\n").filter(Boolean).length : 0;
if (logFile) appendFileSync(logFile, JSON.stringify({ argv: process.argv.slice(2), cwd: process.cwd(), stdin }) + "\n");

const loaded = process.env.FAKE_AGENT_SCRIPT ? JSON.parse(readFileSync(process.env.FAKE_AGENT_SCRIPT, "utf8")) : { steps: [] };
const script = Array.isArray(loaded) ? loaded[Math.min(runs, loaded.length - 1)] : loaded;
const resumed = process.argv.indexOf("--resume");
const session = resumed >= 0 ? process.argv[resumed + 1] : (script.session ?? "fake-session");

const emit = (value) => process.stdout.write(JSON.stringify({ ...value, session_id: session }) + "\n");
const pause = (ms) => new Promise((done) => setTimeout(done, ms));

emit({ type: "system", subtype: "init", cwd: process.cwd(), tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] });
let message = 0;
let tool = 0;
const replies = [];
for (const step of script.steps ?? []) {
  if (step.say !== undefined) {
    const id = `msg_${++message}`;
    emit({ type: "stream_event", event: { type: "message_start", message: { id, role: "assistant", content: [] } } });
    emit({ type: "stream_event", event: { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } } });
    // In pieces, as a model streams it.
    const pieces = step.say.match(/[\s\S]{1,4}/g) ?? [];
    for (const piece of pieces) {
      emit({ type: "stream_event", event: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: piece } } });
      await pause(5);
    }
    emit({ type: "stream_event", event: { type: "content_block_stop", index: 0 } });
    emit({ type: "assistant", message: { id, role: "assistant", content: [{ type: "text", text: step.say }] } });
    emit({ type: "stream_event", event: { type: "message_stop" } });
    replies.push(step.say);
  } else if (step.tool !== undefined) {
    const id = `msg_${++message}`;
    const use = `toolu_${++tool}`;
    emit({ type: "stream_event", event: { type: "message_start", message: { id, role: "assistant", content: [] } } });
    emit({ type: "assistant", message: { id, role: "assistant", content: [{ type: "tool_use", id: use, name: step.tool, input: step.input ?? {} }] } });
    if (step.write) {
      const file = resolve(process.cwd(), step.write.path);
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, step.write.text);
    }
    await pause(5);
    if (step.waitFor) while (!existsSync(step.waitFor)) await pause(20);
    emit({ type: "user", message: { role: "user", content: [{ type: "tool_result", tool_use_id: use, content: "ok", is_error: Boolean(step.toolFails) }] } });
  } else if (step.waitFor !== undefined) {
    while (!existsSync(step.waitFor)) await pause(20);
  } else if (step.fail !== undefined) {
    process.stderr.write(step.fail + "\n");
    process.exit(1);
  }
}
emit({ type: "result", subtype: "success", is_error: false, result: replies.join("\n\n"), num_turns: message });
