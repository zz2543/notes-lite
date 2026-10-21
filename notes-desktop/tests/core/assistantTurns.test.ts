import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { assistantTurns, conversationStore, detectAgents, operationLog, snapshotStore, spaceLibrary, type TurnEvent } from "../../src/core";
import type { ReviewMode } from "../../src/shared/preferences";
import { installFakeAgent, type FakeScript } from "../support/fakeAgent";
import { fakeTrash, library, scratchFolder } from "../support/library";

// 助手栏 turns as main runs them: a conversation is begun or continued, the turn's events folded into
// it and passed on, and it is kept with the app.

async function setup(script: FakeScript | FakeScript[], review: ReviewMode = "review", files: Record<string, string> = { "随记.md": "随记\n" }) {
  const root = await library(files);
  const data = await scratchFolder("notes-desktop-data-");
  const trash = await fakeTrash();
  const snapshots = snapshotStore(join(data, "snapshots"), { trash: trash.trash });
  const agent = await installFakeAgent(join(data, "agents"), "claude", script);
  const conversations = conversationStore(join(data, "conversations"));
  const turns = assistantTurns({
    conversations,
    snapshots,
    log: (at) => operationLog(at, { trash: trash.trash, turns: snapshots.library(at) }),
    agents: () => detectAgents({ path: join(data, "agents"), pathext: process.env.PATHEXT }),
    env: async () => process.env,
    reviewMode: () => review,
    spaces: (at: string) => spaceLibrary(at),
  });
  const events: Array<[string, TurnEvent]> = [];
  const ended = () => new Promise<void>((done) => {
    const check = setInterval(() => {
      if (events.some(([, e]) => e.kind === "end")) {
        clearInterval(check);
        done();
      }
    }, 20);
  });
  const start = (request: { conversation?: string | null; text: string; agent?: "claude" | "codex"; space?: string }, at = root) =>
    turns.start(at, { conversation: null, agent: "claude", folder: "", notes: [], ...request }, (id, event) => events.push([id, event]));
  const log = operationLog(root, { trash: trash.trash, turns: snapshots.library(root) });
  return { root, data, agent, conversations, turns, events, ended, start, log };
}

describe("助手栏的一轮", () => {
  it("begins a conversation, passes the turn's events on and keeps the conversation with the reply folded in", async () => {
    const lib = await setup({ session: "s-1", steps: [{ say: "好的。" }] });

    const started = await lib.start({ text: "你好" });
    expect(started.ok).toBe(true);
    if (!started.ok) return;
    expect(started.conversation.messages.map((m) => m.role)).toEqual(["user", "assistant"]);
    await lib.ended();

    expect(lib.events.every(([id]) => id === started.conversation.id)).toBe(true);
    await expect.poll(async () => (await lib.conversations.read(started.conversation.id)).session).toBe("s-1");
    const kept = await lib.conversations.read(started.conversation.id);
    expect(kept.messages[1]).toMatchObject({ role: "assistant", done: true, parts: [{ kind: "text", text: "好的。" }] });
  });

  it("continues a kept conversation with its session, and refuses one still running or from another library", async () => {
    const lib = await setup({ session: "s-1", steps: [{ waitFor: "go" }, { say: "好的。" }] });
    const first = await lib.start({ text: "你好" });
    if (!first.ok) throw new Error(first.message);
    const id = first.conversation.id;

    expect(await lib.start({ conversation: id, text: "再说" })).toEqual({ ok: false, message: "上一轮还没有结束。" });
    lib.turns.stop(id);
    await lib.ended();
    await expect.poll(async () => (await lib.conversations.read(id)).messages.at(-1)).toMatchObject({ done: true });

    const other = await library({});
    expect(await lib.start({ conversation: id, text: "再说" }, other)).toEqual({ ok: false, message: "这个对话属于另一个笔记库。" });
    const again = await lib.start({ conversation: id, text: "再说" });
    expect(again.ok && again.conversation.messages.map((m) => m.role)).toEqual(["user", "assistant", "user", "assistant"]);
    lib.turns.stopAll();
    await expect.poll(async () => (await lib.conversations.read(id)).messages).toHaveLength(4);
    await expect.poll(async () => (await lib.conversations.read(id)).messages.at(-1)).toMatchObject({ done: true, failed: "已停止。" });
  });

  it("tells the agent of the library's spaces and their authoring guide, and which space is open", async () => {
    const lib = await setup({ steps: [{ say: "好的。" }] }, "review", { "健身/训练.md": "# 训练\n", ".notes/空间/健身.html": '<meta name="space-scope" content="健身">\n' });
    await lib.start({ text: "做一个健身主页", space: "健身" });
    await lib.ended();
    const [run] = await lib.agent.runs();
    expect(run!.stdin).toContain("请先完整阅读并遵守编写说明：.notes/空间/编写说明.md");
    expect(run!.stdin).toContain("- 健身：.notes/空间/健身.html（当前打开）");
  });

  it("says so when no library is open or the agent is gone", async () => {
    const lib = await setup({ steps: [] });
    expect(await lib.turns.start(null, { conversation: null, agent: "claude", folder: "", notes: [], text: "x" }, () => {})).toEqual({ ok: false, message: "请先打开笔记库。" });
    expect(await lib.start({ text: "x", agent: "codex" })).toEqual({ ok: false, message: "没有找到这个对话所用的 Agent，请确认它仍然安装着。" });
  });
});

describe("审查一轮", () => {
  const edits: FakeScript = {
    steps: [
      { tool: "Write", input: { file_path: "随记.md" }, write: { path: "随记.md", text: "随记\n补一行\n" } },
      { tool: "Write", input: { file_path: "新.md" }, write: { path: "新.md", text: "新\n" } },
    ],
  };
  const read = (root: string, path: string) => readFile(join(root, path), "utf8").catch(() => null);

  async function reviewed(lib: Awaited<ReturnType<typeof setup>>) {
    const started = await lib.start({ text: "改一改" });
    if (!started.ok) throw new Error(started.message);
    await lib.ended();
    const id = started.conversation.id;
    await expect.poll(async () => (await lib.conversations.read(id)).messages.at(-1)).toMatchObject({ done: true });
    const reply = (await lib.conversations.read(id)).messages.at(-1)!;
    if (reply.role !== "assistant" || !reply.turn) throw new Error("no turn");
    return { id, turn: reply.turn, reply };
  }

  it("leaves a turn that changed notes waiting on its card, and keeps it all in one click", async () => {
    const lib = await setup(edits);
    const { id, turn, reply } = await reviewed(lib);
    expect(reply).toMatchObject({ review: "pending", changes: [{ path: "新.md", kind: "added" }, { path: "随记.md", kind: "modified", lines: { added: 1, removed: 0 } }] });

    const kept = await lib.turns.review(lib.root, { conversation: id, turn, action: "keep" });
    expect(kept.ok && kept.conversation.messages.at(-1)).toMatchObject({ review: "kept" });
    expect((await lib.conversations.read(id)).messages.at(-1)).toMatchObject({ review: "kept" });
    expect(await read(lib.root, "新.md")).toBe("新\n");
    expect((await lib.log.entries())[0]).toMatchObject({ kind: "agentTurn", undone: false });
  });

  it("shows one note's diff and takes back just that note, then the rest with the whole turn", async () => {
    const lib = await setup(edits);
    const { id, turn } = await reviewed(lib);

    expect(await lib.turns.diff(lib.root, turn, "随记.md")).toEqual({ ok: true, lines: [{ sign: "+", text: "补一行" }] });
    const one = await lib.turns.review(lib.root, { conversation: id, turn, action: "revert", path: "随记.md" });
    expect(one.ok && one.conversation.messages.at(-1)).toMatchObject({
      review: "pending",
      changes: [{ path: "新.md", reverted: false }, { path: "随记.md", reverted: true }],
    });
    expect(await read(lib.root, "随记.md")).toBe("随记\n");
    expect(await read(lib.root, "新.md")).toBe("新\n");

    const all = await lib.turns.review(lib.root, { conversation: id, turn, action: "revert" });
    expect(all.ok && all.conversation.messages.at(-1)).toMatchObject({ review: "reverted", changes: [{ reverted: true }, { reverted: true }] });
    expect(await read(lib.root, "新.md")).toBeNull();
    // Taken back whole is the same as undoing it in 操作记录.
    expect((await lib.log.entries())[0]).toMatchObject({ kind: "agentTurn", undone: true });
  });

  it("counts a turn whose every note was taken back one by one as taken back, in 操作记录 too", async () => {
    const lib = await setup({ steps: [edits.steps[0]!] });
    const { id, turn } = await reviewed(lib);
    const one = await lib.turns.review(lib.root, { conversation: id, turn, action: "revert", path: "随记.md" });
    expect(one.ok && one.conversation.messages.at(-1)).toMatchObject({ review: "reverted" });
    expect((await lib.log.entries())[0]).toMatchObject({ undone: true });
  });

  it("says why a note can't be taken back once it changed again, and leaves it as it is", async () => {
    const lib = await setup(edits);
    const { id, turn } = await reviewed(lib);
    // Another size, so it reads as changed whatever the clock.
    await writeFile(join(lib.root, "随记.md"), "我又改了\n");

    const one = await lib.turns.review(lib.root, { conversation: id, turn, action: "revert", path: "随记.md" });
    expect(one).toMatchObject({ ok: false, message: "随记.md 在这一轮之后又被修改过，为避免覆盖，没有撤销。" });
    expect(await read(lib.root, "随记.md")).toBe("我又改了\n");
    expect((await lib.conversations.read(id)).messages.at(-1)).toMatchObject({ review: "pending" });
  });

  it("takes back a turn already undone in 操作记录 without undoing it twice", async () => {
    const lib = await setup(edits);
    const { id, turn } = await reviewed(lib);
    await lib.log.undo((await lib.log.entries())[0]!.id);
    const all = await lib.turns.review(lib.root, { conversation: id, turn, action: "revert" });
    expect(all.ok && all.conversation.messages.at(-1)).toMatchObject({ review: "reverted" });
  });

  it("keeps a turn's changes without a card in 直接保留 mode, still undoable in 操作记录", async () => {
    const lib = await setup(edits, "keep");
    const { reply } = await reviewed(lib);
    expect(reply).toMatchObject({ review: "kept" });
    await lib.log.undo((await lib.log.entries())[0]!.id);
    expect(await read(lib.root, "新.md")).toBeNull();
  });

  it("keeps the last turn's changes when the next one begins, and asks no review of a turn that changed nothing", async () => {
    const lib = await setup([edits, { steps: [{ say: "好的。" }] }]);
    const { id } = await reviewed(lib);
    lib.events.length = 0;
    const again = await lib.start({ conversation: id, text: "再说" });
    expect(again.ok && again.conversation.messages[1]).toMatchObject({ review: "kept" });
    await lib.ended();
    await expect.poll(async () => (await lib.conversations.read(id)).messages.at(-1)).toMatchObject({ done: true });
    expect((await lib.conversations.read(id)).messages.at(-1)).not.toHaveProperty("review");
  });
});
