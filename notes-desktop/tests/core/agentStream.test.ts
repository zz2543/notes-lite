import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { agentAdapter, type AgentEvent, type AgentId } from "../../src/core";

// 适配层 (assistant-spec, ticket 30): each agent's full-permission command line and its output read into
// the 助手栏's events. The fixtures in agentOutput/ are what the real CLIs printed (Codex 0.163.0, Pi 1.3.0,
// DeepSeek Harness 0.2.1-rc.2) against a local stand-in for the model service, Pi's system prompt and
// usage left out; they write a.md with a shell command and b.md with their own file tool.

const fixture = (name: string) => readFileSync(join(__dirname, "agentOutput", name), "utf8").split("\n").filter(Boolean);
const read = (id: AgentId, cwd: string, lines: string[]): AgentEvent[] => {
  const reader = agentAdapter(id).reader(cwd);
  return lines.flatMap((line) => reader(line));
};
const replyOf = (events: AgentEvent[]) => events.map((e) => (e.kind === "text" ? e.text : "")).join("");

describe("Codex", () => {
  it("runs codex exec with JSON events, no sandbox and no approvals, the prompt on stdin", () => {
    const codex = agentAdapter("codex");
    expect(codex.args()).toEqual(["exec", "--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox", "-"]);
    expect(codex.args("t-1")).toEqual(["exec", "resume", "--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox", "t-1", "-"]);
  });

  it("reads the thread, its commands and file changes, the reply and the end", () => {
    const events = read("codex", "/tmp/cx2", fixture("codex-turn.jsonl"));
    expect(events[0]).toEqual({ kind: "session", id: "01a15d68-6a3a-7a10-b7cf-c92a54fa302c" });
    expect(events).toContainEqual({ kind: "tool", id: "item_0", name: "命令", activity: "running", detail: "echo hello > a.md" });
    expect(events).toContainEqual({ kind: "toolDone", id: "item_0", failed: false });
    expect(events).toContainEqual({ kind: "tool", id: "item_1", name: "改文件", activity: "writing", detail: "b.md" });
    expect(events).toContainEqual({ kind: "toolDone", id: "item_1", failed: false });
    expect(replyOf(events)).toBe("写好了。");
    expect(events.at(-1)).toEqual({ kind: "result" });
  });

  it("a failed turn says why; reconnecting along the way is not a failure", () => {
    const events = read("codex", "/tmp/cx", fixture("codex-failed.jsonl"));
    expect(events.filter((e) => e.kind === "result")).toEqual([
      { kind: "result", failed: "unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: https://api.openai.com/v1/responses" },
    ]);
    expect(events.some((e) => e.kind === "text")).toBe(false);
  });

  it("a command that exits non-zero, or a patch that fails, is a failed step", () => {
    const lines = [
      { type: "item.started", item: { id: "i1", type: "command_execution", command: "/bin/zsh -lc 'false'", status: "in_progress" } },
      { type: "item.completed", item: { id: "i1", type: "command_execution", command: "/bin/zsh -lc 'false'", exit_code: 1, status: "failed" } },
      { type: "item.completed", item: { id: "i2", type: "file_change", changes: [{ path: "/w/a.md", kind: "update" }], status: "failed" } },
      { type: "item.started", item: { id: "i3", type: "web_search", query: "天气" } },
      { type: "item.completed", item: { id: "i3", type: "web_search", query: "天气" } },
    ].map((line) => JSON.stringify(line));
    const events = read("codex", "/w", lines);
    expect(events).toEqual([
      { kind: "tool", id: "i1", name: "命令", activity: "running", detail: "false" },
      { kind: "toolDone", id: "i1", failed: true },
      { kind: "tool", id: "i2", name: "改文件", activity: "writing", detail: "a.md" },
      { kind: "toolDone", id: "i2", failed: true },
      { kind: "tool", id: "i3", name: "搜索网页", activity: "searching", detail: "天气" },
      { kind: "toolDone", id: "i3", failed: false },
    ]);
  });
});

describe("Pi", () => {
  it("runs pi in JSON mode (it never asks before a tool), continuing a session by its id", () => {
    const pi = agentAdapter("pi");
    expect(pi.args()).toEqual(["--mode", "json"]);
    expect(pi.args("p-1")).toEqual(["--mode", "json", "--session", "p-1"]);
  });

  it("reads the session, the streamed reply, the tools and the end", () => {
    const events = read("pi", "/tmp/pi1", fixture("pi-turn.jsonl"));
    expect(events[0]).toEqual({ kind: "session", id: "01a15d69-45ed-7500-92f1-fbafb4ccc27e" });
    expect(events).toContainEqual({ kind: "tool", id: "call_1_0", name: "bash", activity: "running", detail: "echo hello > a.md" });
    expect(events).toContainEqual({ kind: "tool", id: "call_1_1", name: "write", activity: "writing", detail: "b.md" });
    expect(events).toContainEqual({ kind: "toolDone", id: "call_1_1", failed: false });
    // In pieces, as it streamed.
    expect(events.filter((e) => e.kind === "text")).toEqual([
      { kind: "text", text: "写" },
      { kind: "text", text: "好了。" },
    ]);
    expect(events.at(-1)).toEqual({ kind: "result" });
  });

  it("a turn the model service refused is a failure, though pi exits 0", () => {
    const events = read("pi", "/tmp/pi1", fixture("pi-failed.jsonl"));
    expect(events.at(-1)).toEqual({ kind: "result", failed: '401: {"message":"Invalid API key","type":"invalid_request_error"}' });
  });
});

describe("DeepSeek Harness", () => {
  it("runs the headless profile with JSON events and full access (no sandbox, no approvals)", () => {
    const dsh = agentAdapter("dsh");
    expect(dsh.args()).toEqual(["--profile", "headless", "--json", "-"]);
    expect(dsh.args("session-1")).toEqual(["--profile", "headless", "--json", "--session-id", "session-1", "-"]);
    expect(dsh.env).toEqual({ DSH_PERMISSION_MODE: "danger-full-access" });
  });

  it("reads the session, the tools, the reply and the end", () => {
    const events = read("dsh", "/tmp/ds1", fixture("dsh-turn.jsonl"));
    expect(events[0]).toEqual({ kind: "session", id: "session-d2f53dd1-464a-4a71-a961-cf40a1e75a0c" });
    expect(events).toContainEqual({ kind: "tool", id: "toolu_0_1792568719506", name: "bash", activity: "running", detail: "echo hello > a.md && echo out > /tmp/ds-outside.txt" });
    expect(events).toContainEqual({ kind: "tool", id: "toolu_1_1792568719506", name: "write", activity: "writing", detail: "b.md" });
    expect(events).toContainEqual({ kind: "toolDone", id: "toolu_1_1792568719506", failed: false });
    expect(replyOf(events)).toBe("写好了。");
    expect(events.at(-1)).toEqual({ kind: "result" });
  });

  it("a turn that ended in error says why; an error outside a turn too", () => {
    expect(read("dsh", "/tmp/ds1", fixture("dsh-failed.jsonl")).at(-1)).toEqual({ kind: "result", failed: "Invalid API key" });
    const unknown = JSON.stringify({ type: "error", message: 'session "s-x" does not exist; omit --session-id to start a new Session' });
    expect(read("dsh", "/w", [unknown])).toEqual([{ kind: "result", failed: 'session "s-x" does not exist; omit --session-id to start a new Session' }]);
  });
});

describe("every agent", () => {
  it("separates replies that come whole, one after another", () => {
    const codex = [
      { type: "item.completed", item: { id: "a", type: "agent_message", text: "第一段。" } },
      { type: "item.completed", item: { id: "b", type: "agent_message", text: "第二段。" } },
    ].map((line) => JSON.stringify(line));
    expect(replyOf(read("codex", "/w", codex))).toBe("第一段。\n\n第二段。");
    const dsh = [{ type: "text", text: "第一段。" }, { type: "text", text: "第二段。" }].map((line) => JSON.stringify(line));
    expect(replyOf(read("dsh", "/w", dsh))).toBe("第一段。\n\n第二段。");
  });

  it("ignores what is not JSON", () => {
    for (const id of ["claude", "codex", "dsh", "pi"] as const) expect(read(id, "/w", ["WARNING: something", ""])).toEqual([]);
  });
});
