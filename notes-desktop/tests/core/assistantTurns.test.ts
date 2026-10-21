import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { assistantTurns, conversationStore, detectAgents, operationLog, snapshotStore, spaceLibrary, type TurnEvent } from "../../src/core";
import { installFakeAgent, type FakeScript } from "../support/fakeAgent";
import { fakeTrash, library, scratchFolder } from "../support/library";

// 助手栏 turns as main runs them: a conversation is begun or continued, the turn's events folded into
// it and passed on, and it is kept with the app.

async function setup(script: FakeScript | FakeScript[], files: Record<string, string> = { "随记.md": "随记\n" }) {
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
  return { root, data, agent, conversations, turns, events, ended, start };
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
    const lib = await setup({ steps: [{ say: "好的。" }] }, { "健身/训练.md": "# 训练\n", ".notes/空间/健身.html": '<meta name="space-scope" content="健身">\n' });
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
