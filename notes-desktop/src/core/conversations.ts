// 对话记录 (assistant-spec): kept in the app's own data folder, one JSON file per conversation, never
// in the library.
import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { AgentId } from "./agentKinds";
import type { Conversation } from "./conversation";

export interface ConversationStore {
  /** A new conversation, not yet kept. */
  start(begin: { agent: AgentId; root: string; folder: string }): Conversation;
  save(conversation: Conversation): Promise<void>;
  read(id: string): Promise<Conversation>;
}

export function conversationStore(base: string, now: () => Date = () => new Date()): ConversationStore {
  const fileOf = (id: string) => join(base, `${id.replace(/[^\w-]/g, "")}.json`);
  return {
    start: ({ agent, root, folder }) => ({ id: randomUUID(), agent, root, folder, created: now().toISOString(), messages: [] }),
    save: async (conversation) => {
      await mkdir(base, { recursive: true });
      const file = fileOf(conversation.id);
      await writeFile(`${file}.tmp`, JSON.stringify(conversation));
      await rename(`${file}.tmp`, file);
    },
    read: async (id) => JSON.parse(await readFile(fileOf(id), "utf8")) as Conversation,
  };
}
