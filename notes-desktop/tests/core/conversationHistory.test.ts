import { realpath } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { assistantTurns, conversationStore, detectAgents, emptyReply, operationLog, snapshotStore, type AgentId, type TurnEvent } from "../../src/core";
import { installFakeAgent } from "../support/fakeAgent";
import { fakeTrash, library, scratchFolder } from "../support/library";

// 对话历史 (assistant-spec 18): the conversations kept with the app, newest first, each opened again as
// it was and continued with the agent and working directory it began with.

async function setup() {
  const root = await library({ "日记/周一.md": "# 周一\n", "随记.md": "随记\n" });
  const data = await scratchFolder("notes-desktop-data-");
  const trash = await fakeTrash();
  const snapshots = snapshotStore(join(data, "snapshots"), { trash: trash.trash });
  const claude = await installFakeAgent(join(data, "agents"), "claude", { session: "c-1", steps: [{ say: "好的。" }] });
  const codex = await installFakeAgent(join(data, "agents"), "codex", { session: "x-1", steps: [{ say: "收到。" }] });
  // One second a save, so which is newer is plain.
  let tick = 0;
  const conversations = conversationStore(join(data, "conversations"), () => new Date(Date.UTC(2026, 9, 20, 8, 0, tick++)));
  const options = {
    conversations,
    snapshots,
    log: (at: string) => operationLog(at, { trash: trash.trash, turns: snapshots.library(at) }),
    agents: () => detectAgents({ path: join(data, "agents"), pathext: process.env.PATHEXT }),
    env: async () => process.env,
  };
  const turns = assistantTurns(options);
  const events: Array<[string, TurnEvent]> = [];
  const ends = (id: string) => events.filter(([to, e]) => to === id && e.kind === "end").length;
  /** Runs a turn to its end and answers its conversation's id. */
  const turn = async (request: { conversation?: string; agent?: AgentId; folder?: string; text: string }, at = root) => {
    const started = await turns.start(at, { conversation: null, agent: "claude", folder: "", notes: [], ...request }, (id, e) => events.push([id, e]));
    if (!started.ok) throw new Error(started.message);
    const id = started.conversation.id;
    const before = ends(id);
    await expect.poll(() => ends(id)).toBe(before + 1);
    // Kept once the turn is over.
    await expect.poll(async () => (await conversations.read(id)).messages.at(-1)).toMatchObject({ done: true });
    return id;
  };
  return { root, options, conversations, turns, claude, codex, turn };
}

describe("对话历史", () => {
  it("lists the library's conversations, the latest used first, each by its first message with its agent and working directory", async () => {
    const lib = await setup();
    const first = await lib.turn({ text: "帮我整理日记\n按周分", folder: "日记" });
    const second = await lib.turn({ text: "写一篇随记", agent: "codex" });
    const elsewhere = await lib.turn({ text: "别的库" }, await library({}));

    expect(await lib.turns.history(lib.root)).toEqual([
      { id: second, agent: "codex", folder: "", title: "写一篇随记", updated: expect.any(String) },
      { id: first, agent: "claude", folder: "日记", title: "帮我整理日记", updated: expect.any(String) },
    ]);
    // Continuing the older one brings it to the top.
    await lib.turn({ conversation: first, text: "再细一点" });
    expect((await lib.turns.history(lib.root)).map((c) => c.id)).toEqual([first, second]);
    expect((await lib.turns.history(lib.root)).map((c) => c.id)).not.toContain(elsewhere);
    expect(await lib.turns.history(null)).toEqual([]);
  });

  it("opens a kept conversation as it was, and continuing it keeps its agent and working directory", async () => {
    const lib = await setup();
    const id = await lib.turn({ text: "看看周一", agent: "codex", folder: "日记" });
    // As after the app started again: nothing of it in memory.
    const again = assistantTurns(lib.options);
    const opened = await again.open(lib.root, id);
    expect(opened).toMatchObject({ id, agent: "codex", folder: "日记", session: "x-1" });
    expect(opened!.messages).toMatchObject([
      { role: "user", text: "看看周一" },
      { role: "assistant", done: true, parts: [{ kind: "text", text: "收到。" }] },
    ]);

    // Continued from wherever the user is now, with whichever agent the switch shows: it stays the same.
    const started = await again.start(lib.root, { conversation: id, agent: "claude", folder: "", notes: [], text: "继续" }, () => {});
    expect(started.ok).toBe(true);
    await expect.poll(async () => (await lib.codex.runs()).length).toBe(2);
    const [, run] = await lib.codex.runs();
    expect(run!.argv).toContain("x-1");
    expect(await realpath(run!.cwd)).toBe(await realpath(join(lib.root, "日记")));
    expect(await lib.claude.runs()).toEqual([]);
  });

  it("opens nothing from another library or that is not there", async () => {
    const lib = await setup();
    const id = await lib.turn({ text: "你好" });
    expect(await lib.turns.open(await library({}), id)).toBeNull();
    expect(await lib.turns.open(lib.root, "missing")).toBeNull();
    expect(await lib.turns.open(null, id)).toBeNull();
  });

  it("a turn the app quit in the middle of opens as stopped", async () => {
    const lib = await setup();
    const conversation = lib.conversations.start({ agent: "claude", root: lib.root, folder: "" });
    conversation.messages.push({ role: "user", text: "写到一半", notes: [] }, { ...emptyReply(), parts: [{ kind: "text", text: "开始" }] });
    await lib.conversations.save(conversation);
    expect((await lib.turns.open(lib.root, conversation.id))!.messages.at(-1)).toEqual({
      role: "assistant",
      parts: [{ kind: "text", text: "开始" }],
      done: true,
      changes: [],
      failed: "已停止。",
    });
  });
});
