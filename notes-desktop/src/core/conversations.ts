// 对话记录 (assistant-spec): kept in the app's own data folder, one JSON file per conversation, never
// in the library.
import { randomUUID } from "node:crypto";
import { mkdir, readdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { AgentId } from "../shared/agentKinds";
import type { Conversation, ConversationSummary } from "../shared/conversation";

export interface ConversationStore {
  /** A new conversation, not yet kept. */
  start(begin: { agent: AgentId; root: string; folder: string; model?: string }): Conversation;
  save(conversation: Conversation): Promise<void>;
  read(id: string): Promise<Conversation>;
  /** 对话历史: the library's kept conversations, the latest kept first. */
  list(root: string): Promise<ConversationSummary[]>;
}

export function conversationStore(base: string, now: () => Date = () => new Date()): ConversationStore {
  const fileOf = (id: string) => join(base, `${id.replace(/[^\w-]/g, "")}.json`);
  return {
    start: ({ agent, root, folder, model }) => ({ id: randomUUID(), agent, root, folder, ...(model ? { model } : {}), created: now().toISOString(), messages: [] }),
    save: async (conversation) => {
      await mkdir(base, { recursive: true });
      const file = fileOf(conversation.id);
      await writeFile(`${file}.tmp`, JSON.stringify({ ...conversation, updated: now().toISOString() }));
      await rename(`${file}.tmp`, file);
    },
    read: async (id) => JSON.parse(await readFile(fileOf(id), "utf8")) as Conversation,
    list: async (root) => {
      const names = (await readdir(base).catch(() => [] as string[])).filter((name) => name.endsWith(".json"));
      const kept = await Promise.all(
        // One that cannot be read is left out, not the whole list.
        names.map((name) => readFile(join(base, name), "utf8").then((text) => JSON.parse(text) as Conversation, () => null)),
      );
      return kept
        .filter((c): c is Conversation => c !== null && c.root === root)
        .map((c) => ({ id: c.id, agent: c.agent, folder: c.folder, title: titleOf(c), updated: c.updated ?? c.created }))
        .sort((a, b) => b.updated.localeCompare(a.updated));
    },
  };
}

const titleOf = (conversation: Conversation) => {
  const first = conversation.messages.find((m) => m.role === "user");
  return first?.role === "user" ? (first.shown ?? first.text).trim().split("\n")[0]! : "";
};
