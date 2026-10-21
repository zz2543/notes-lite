import { describe, expect, it } from "vitest";
import { emptyReply, withEvent, type Conversation, type TurnEvent } from "../../src/shared/conversation";

// The one rule that folds a turn's events into its conversation, used by main to keep it and by the
// 助手栏 to show it.

const started = (): Conversation => ({
  id: "c",
  agent: "claude",
  root: "/库",
  folder: "",
  created: "2026-10-20T00:00:00.000Z",
  messages: [{ role: "user", text: "写点东西", notes: [] }, emptyReply()],
});

describe("对话的折叠", () => {
  it("grows the running reply and keeps the agent's session id", () => {
    let conversation = started();
    const events: TurnEvent[] = [
      { kind: "session", id: "s-1" },
      { kind: "text", text: "好的，" },
      { kind: "tool", id: "t", name: "Write", activity: "writing", detail: "随记.md" },
      { kind: "toolDone", id: "t", failed: false },
      { kind: "text", text: "写好了。" },
      { kind: "end", changes: [{ path: "随记.md", kind: "modified", restorable: true, reverted: false }] },
    ];
    for (const event of events) conversation = withEvent(conversation, event);

    expect(conversation.session).toBe("s-1");
    expect(conversation.messages[1]).toEqual({
      role: "assistant",
      done: true,
      changes: [{ path: "随记.md", kind: "modified", restorable: true, reverted: false }],
      parts: [
        { kind: "text", text: "好的，" },
        { kind: "steps", steps: [{ id: "t", name: "Write", activity: "writing", detail: "随记.md", done: true, failed: false }] },
        { kind: "text", text: "写好了。" },
      ],
    });
  });

  it("leaves the conversation it was given as it was", () => {
    const before = started();
    withEvent(before, { kind: "text", text: "x" });
    expect(before).toEqual(started());
  });
});
