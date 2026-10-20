import { realpath } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { operationLog, runTurn, snapshotStore, type TurnEvent } from "../../src/core";
import { installFakeAgent, type FakeScript } from "../support/fakeAgent";
import { contents, fakeTrash, library, scratchFolder } from "../support/library";

// 一轮 (assistant-spec): the library is snapshotted, the agent runs in the working directory with full
// permissions, its replies and tool calls stream out, and what it changed becomes one operation-log entry.

async function setup(files: Record<string, string>, script: FakeScript | FakeScript[]) {
  const root = await library(files);
  const data = await scratchFolder("notes-desktop-data-");
  const trash = await fakeTrash();
  const snapshots = snapshotStore(join(data, "snapshots"), { trash: trash.trash }).library(root);
  const log = operationLog(root, { trash: trash.trash, turns: snapshots });
  const agent = await installFakeAgent(join(data, "agents"), "claude", script);
  const events: TurnEvent[] = [];
  const turn = (request: { folder: string; text: string; notes?: string[]; session?: string }) =>
    runTurn({ agent: { id: "claude", path: agent.path }, root, snapshots, log, notes: [], ...request, onEvent: (event) => events.push(event) });
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
});
