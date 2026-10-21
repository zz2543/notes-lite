import { readFile, realpath } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { addEvent, conversationStore, emptyReply, operationLog, runTurn, snapshotStore, spaceLibrary, turnSpaces, type AgentId, type TurnEvent, type TurnSpaces } from "../../src/core";
import { installFakeAgent, type FakeScript } from "../support/fakeAgent";
import { contents, fakeTrash, library, scratchFolder } from "../support/library";

// 一轮 (assistant-spec): the library is snapshotted, the agent runs in the working directory with full
// permissions, its replies and tool calls stream out, and what it changed becomes one operation-log entry.

async function setup(files: Record<string, string>, script: FakeScript | FakeScript[], id: AgentId = "claude") {
  const root = await library(files);
  const data = await scratchFolder("notes-desktop-data-");
  const trash = await fakeTrash();
  const snapshots = snapshotStore(join(data, "snapshots"), { trash: trash.trash }).library(root);
  const log = operationLog(root, { trash: trash.trash, turns: snapshots });
  const agent = await installFakeAgent(join(data, "agents"), id, script);
  const events: TurnEvent[] = [];
  const turn = (request: { folder: string; text: string; notes?: string[]; session?: string; signal?: AbortSignal; spaces?: TurnSpaces }) =>
    runTurn({ agent: { id, path: agent.path }, root, snapshots, log, notes: [], ...request, onEvent: (event) => events.push(event) });
  return { root, agent, events, turn, log };
}

describe("一轮", () => {
  it("runs Claude Code with full permissions in the working directory, streams its reply and logs what it changed", async () => {
    const lib = await setup({ "日记/周一.md": "# 周一\n", "随记.md": "随记\n" }, {
      session: "s-1",
      steps: [
        { say: "我来补充周一的计划。" },
        { tool: "Edit", input: { file_path: "周一.md" }, write: { path: "周一.md", text: "# 周一\n\n- 跑步\n" } },
        { say: "已经加上了。" },
      ],
    });
    const before = await contents(lib.root);

    const outcome = await lib.turn({ folder: "日记", text: "补充计划", notes: ["日记/周一.md", "随记.md"] });

    const [run] = await lib.agent.runs();
    expect(run!.argv).toContain("--dangerously-skip-permissions");
    expect(await realpath(run!.cwd)).toBe(await realpath(join(lib.root, "日记")));
    // The prompt goes in on stdin, with the attached notes relative to the working directory.
    expect(run!.stdin).toContain("补充计划");
    expect(run!.stdin).toContain("周一.md");
    expect(run!.stdin).toContain("../随记.md");

    // The reply streamed in pieces; the tool call came and went.
    const text = lib.events.filter((e) => e.kind === "text").map((e) => (e.kind === "text" ? e.text : ""));
    expect(text.length).toBeGreaterThan(2);
    expect(text.join("")).toBe("我来补充周一的计划。已经加上了。");
    expect(lib.events).toContainEqual(expect.objectContaining({ kind: "tool", name: "Edit", activity: "writing", detail: "周一.md" }));
    expect(lib.events).toContainEqual(expect.objectContaining({ kind: "toolDone", failed: false }));
    expect(lib.events.at(-1)).toEqual({ kind: "end", changes: [{ path: "日记/周一.md", kind: "modified" }] });

    expect(outcome.session).toBe("s-1");
    expect(outcome.failed).toBeUndefined();
    const [entry] = await lib.log.entries();
    expect(entry).toMatchObject({ kind: "agentTurn", space: "助手", files: [{ path: "日记/周一.md", kind: "modified" }] });

    // Undoing the entry puts the whole turn back.
    await lib.log.undo(entry!.id);
    expect(await contents(lib.root)).toEqual({ ...before, ".notes/操作记录.json": expect.any(String) });
  });

  it("continues the agent's conversation on the next turn", async () => {
    const lib = await setup({ "随记.md": "随记\n" }, { session: "s-7", steps: [{ say: "好的。" }] });
    const first = await lib.turn({ folder: "", text: "你好" });
    await lib.turn({ folder: "", text: "再来", session: first.session });
    const runs = await lib.agent.runs();
    expect(runs[0]!.argv).not.toContain("--resume");
    expect(runs[1]!.argv).toEqual(expect.arrayContaining(["--resume", "s-7"]));
    // Nothing changed, so nothing is logged.
    expect(await lib.log.entries()).toEqual([]);
  });

  it("an agent that fails still has what it changed listed and logged, and says why", async () => {
    const lib = await setup({ "随记.md": "随记\n" }, {
      steps: [{ tool: "Write", input: { file_path: "新.md" }, write: { path: "新.md", text: "新\n" } }, { fail: "额度已用完" }],
    });
    const outcome = await lib.turn({ folder: "", text: "写一篇" });
    expect(outcome.failed).toBe("额度已用完");
    expect(lib.events.at(-1)).toEqual({ kind: "end", changes: [{ path: "新.md", kind: "added" }], failed: "额度已用完" });
    expect(await lib.log.entries()).toHaveLength(1);
  });

  it("stops the agent when asked", async () => {
    const root = await scratchFolder("notes-desktop-hold-");
    const lib = await setup({ "随记.md": "随记\n" }, { steps: [{ say: "开始" }, { waitFor: join(root, "never") }] });
    const stop = new AbortController();
    const running = runTurnStopping(lib, stop);
    await expect.poll(() => lib.events.some((e) => e.kind === "text")).toBe(true);
    stop.abort();
    expect((await running).failed).toBe("已停止。");
  });
});

// Codex, DeepSeek Harness and Pi each speak their own output and take their own flags (ADR 0005); a turn
// with any of them streams, continues and logs the same way.
const others = [
  { id: "codex", write: "file_change", fullPermission: ["--dangerously-bypass-approvals-and-sandbox"], resume: ["exec", "resume"] },
  { id: "dsh", write: "write", fullPermission: ["--profile", "headless"], resume: ["--session-id"] },
  { id: "pi", write: "write", fullPermission: ["--mode", "json"], resume: ["--session"] },
] as const;

describe.each(others)("一轮，用 $id", ({ id, write, fullPermission, resume }) => {
  it("runs it with full permissions in the working directory, streams its reply and logs what it changed", async () => {
    const lib = await setup(
      { "日记/周一.md": "# 周一\n" },
      {
        session: `${id}-1`,
        steps: [
          { say: "我来补充。" },
          { tool: write, input: { file_path: "周一.md" }, write: { path: "周一.md", text: "# 周一\n\n- 跑步\n" } },
          { say: "加上了。" },
        ],
      },
      id,
    );
    const outcome = await lib.turn({ folder: "日记", text: "补充计划" });

    const [run] = await lib.agent.runs();
    expect(run!.argv).toEqual(expect.arrayContaining([...fullPermission]));
    // DeepSeek Harness only gets full access when asked by its environment.
    if (id === "dsh") expect(run!.permissionMode).toBe("danger-full-access");
    expect(await realpath(run!.cwd)).toBe(await realpath(join(lib.root, "日记")));
    expect(run!.stdin).toContain("补充计划");

    const text = lib.events.filter((e) => e.kind === "text").map((e) => (e.kind === "text" ? e.text : ""));
    expect(text.join("")).toMatch(/^我来补充。(\n\n)?加上了。$/);
    expect(lib.events).toContainEqual(expect.objectContaining({ kind: "tool", activity: "writing" }));
    expect(lib.events).toContainEqual(expect.objectContaining({ kind: "toolDone", failed: false }));
    expect(lib.events.at(-1)).toEqual({ kind: "end", changes: [{ path: "日记/周一.md", kind: "modified" }] });
    expect(outcome.session).toBe(`${id}-1`);
    expect(outcome.failed).toBeUndefined();
    expect(await lib.log.entries()).toHaveLength(1);
  });

  it("continues its conversation on the next turn", async () => {
    const lib = await setup({ "随记.md": "随记\n" }, { session: `${id}-7`, steps: [{ say: "好的。" }] }, id);
    const first = await lib.turn({ folder: "", text: "你好" });
    const second = await lib.turn({ folder: "", text: "再来", session: first.session });
    const runs = await lib.agent.runs();
    expect(runs[0]!.argv).not.toContain(`${id}-7`);
    expect(runs[1]!.argv.join(" ")).toContain(resume.join(" "));
    expect(runs[1]!.argv).toContain(`${id}-7`);
    expect(second.session).toBe(`${id}-7`);
  });

  it("says why when it fails", async () => {
    const lib = await setup({ "随记.md": "随记\n" }, { steps: [{ say: "试试。" }, { fail: "额度已用完" }] }, id);
    const outcome = await lib.turn({ folder: "", text: "写一篇" });
    expect(outcome.failed).toBe("额度已用完");
    expect(lib.events.at(-1)).toEqual({ kind: "end", changes: [], failed: "额度已用完" });
  });
});

// 空间主页 (assistant-spec 20): whatever the user asks, the agent knows where the library's spaces are and
// that the authoring guide comes first when it writes one — the space open now named.
describe("空间主页的编写说明", () => {
  const files = {
    "日记/周一.md": "# 周一\n",
    ".notes/空间/读书.html": '<meta name="space-scope" content="读书">\n',
    ".notes/空间/健身.html": '<meta name="space-scope" content="健身">\n<p>主页</p>',
    ".notes/空间/顺序.json": JSON.stringify(["读书", "健身"]),
  };

  it("lists the spaces, in the user's order, with the guide, installed, and the one open", async () => {
    const root = await library(files);
    const spaces = await turnSpaces(spaceLibrary(root), "健身");
    expect(spaces).toEqual({
      guide: ".notes/空间/编写说明.md",
      list: [
        { name: "读书", path: ".notes/空间/读书.html" },
        { name: "健身", path: ".notes/空间/健身.html" },
      ],
      open: "健身",
    });
    expect(await readFile(join(root, ".notes", "空间", "编写说明.md"), "utf8")).toContain("空间主页编写说明");
    // A space that is not there is not open.
    expect((await turnSpaces(spaceLibrary(root), "没有"))?.open).toBeUndefined();
  });

  it("says nothing of spaces in a library without any", async () => {
    expect(await turnSpaces(spaceLibrary(await library({ "随记.md": "随记\n" })))).toBeUndefined();
  });

  it("puts them in the prompt, relative to the working directory", async () => {
    const lib = await setup(files, { steps: [{ say: "好的。" }] });
    await lib.turn({ folder: "日记", text: "改一下健身主页", spaces: (await turnSpaces(spaceLibrary(lib.root), "健身"))! });
    const [run] = await lib.agent.runs();
    expect(run!.stdin).toContain("改一下健身主页");
    expect(run!.stdin).toContain("请先完整阅读并遵守编写说明：../.notes/空间/编写说明.md");
    expect(run!.stdin).toContain("- 健身：../.notes/空间/健身.html（当前打开）");
    expect(run!.stdin).toContain("- 读书：../.notes/空间/读书.html\n");
  });
});

describe("对话记录", () => {
  it("folds a turn into a reply, tool calls into one timeline, and keeps it in the app's data folder", async () => {
    const lib = await setup({ "日记/周一.md": "# 周一\n" }, {
      steps: [
        { say: "先看看。" },
        { tool: "Read", input: { file_path: "周一.md" } },
        { tool: "Bash", input: { command: "ls" }, toolFails: true },
        { say: "看完了。" },
      ],
    });
    const data = await scratchFolder("notes-desktop-conversations-");
    const store = conversationStore(data);
    const conversation = store.start({ agent: "claude", root: lib.root, folder: "日记" });
    await lib.turn({ folder: "日记", text: "看看" });
    const reply = lib.events.reduce(addEvent, emptyReply());
    conversation.messages.push({ role: "user", text: "看看", notes: [] }, reply);
    await store.save(conversation);

    const kept = await store.read(conversation.id);
    expect(kept).toMatchObject({ agent: "claude", folder: "日记" });
    expect(kept.messages[1]).toEqual({
      role: "assistant",
      done: true,
      changes: [],
      parts: [
        { kind: "text", text: "先看看。" },
        {
          kind: "steps",
          steps: [
            { id: "toolu_1", name: "Read", activity: "reading", detail: "周一.md", done: true, failed: false },
            { id: "toolu_2", name: "Bash", activity: "running", detail: "ls", done: true, failed: true },
          ],
        },
        { kind: "text", text: "看完了。" },
      ],
    });
    // Nothing of the conversation is written into the library.
    expect(Object.keys(await contents(lib.root))).toEqual(["日记/周一.md"]);
  });
});

function runTurnStopping(lib: Awaited<ReturnType<typeof setup>>, stop: AbortController) {
  return lib.turn({ folder: "", text: "等着", signal: stop.signal });
}

