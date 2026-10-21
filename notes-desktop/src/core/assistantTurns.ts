// 助手栏 turns as the app runs them (assistant-spec): a conversation is begun or continued, a turn
// at a time; its events are folded into it (shared/conversation's one rule) and passed on as they
// come, and it is kept with the app (对话记录) once the turn is over.
import type { AgentId } from "../shared/agentKinds";
import { emptyReply, stoppedTurn, withEvent, type Conversation, type ConversationSummary, type TurnEvent } from "../shared/conversation";
import type { InstalledAgent } from "./agents";
import type { ConversationStore } from "./conversations";
import type { OperationLog } from "./operationLog";
import type { SnapshotStore } from "./snapshots";
import type { SpaceLibrary } from "./spaces";
import { runTurn, turnSpaces } from "./turns";

export interface TurnStart {
  /** The conversation to continue; null begins one. */
  conversation: string | null;
  /** For a new conversation: its agent and its working directory (library-relative). */
  agent: AgentId;
  folder: string;
  text: string;
  /** Notes put in the context, library-relative. */
  notes: string[];
  /** The space open in the app, by name, if any. */
  space?: string;
}

export type TurnStarted = { ok: true; conversation: Conversation } | { ok: false; message: string };

export interface AssistantTurnsOptions {
  conversations: ConversationStore;
  snapshots: SnapshotStore;
  /** The library's operation log, which a turn's changes are recorded in. */
  log(root: string): OperationLog;
  /** The agents installed now, looked for at each turn. */
  agents(): Promise<InstalledAgent[]>;
  /** What an agent runs with. */
  env(): Promise<NodeJS.ProcessEnv>;
  /** The spaces of the library at `root`, told to the agent with their authoring guide each turn. */
  spaces?(root: string): SpaceLibrary;
}

export interface AssistantTurns {
  /**
   * Begins (or continues) a conversation's turn in the library at `root` (null: none is open). Answers
   * at once with the conversation as it now stands; `send` gets the turn's events as they come.
   */
  start(root: string | null, request: TurnStart, send: (conversation: string, event: TurnEvent) => void): Promise<TurnStarted>;
  /** 对话历史: the kept conversations of the library at `root`, the latest first. */
  history(root: string | null): Promise<ConversationSummary[]>;
  /** A conversation of the library at `root` as it stands, to show and continue; null when there is none. */
  open(root: string | null, conversation: string): Promise<Conversation | null>;
  /** Stops the conversation's running turn. */
  stop(conversation: string): void;
  /** Stops every running turn, as when the app quits. */
  stopAll(): void;
}

export function assistantTurns(options: AssistantTurnsOptions): AssistantTurns {
  const { conversations } = options;
  // The conversations of this run stay in memory too.
  const open = new Map<string, Conversation>();
  const running = new Map<string, AbortController>();

  const start: AssistantTurns["start"] = async (root, request, send) => {
    if (!root) return { ok: false, message: "请先打开笔记库。" };
    const known = request.conversation
      ? (open.get(request.conversation) ?? (await conversations.read(request.conversation).catch(() => undefined)))
      : undefined;
    let conversation = known ?? conversations.start({ agent: request.agent, root, folder: request.folder });
    if (conversation.root !== root) return { ok: false, message: "这个对话属于另一个笔记库。" };
    if (running.has(conversation.id)) return { ok: false, message: "上一轮还没有结束。" };
    const agent = (await options.agents()).find((a) => a.id === conversation.agent);
    if (!agent) return { ok: false, message: "没有找到这个对话所用的 Agent，请确认它仍然安装着。" };
    conversation = { ...conversation, messages: [...conversation.messages, { role: "user", text: request.text, notes: request.notes }, emptyReply()] };
    const id = conversation.id;
    open.set(id, conversation);
    await conversations.save(conversation);
    const stop = new AbortController();
    running.set(id, stop);
    const pass = (event: TurnEvent) => {
      open.set(id, withEvent(open.get(id)!, event));
      send(id, event);
    };
    const turns = options.snapshots.library(root);
    void runTurn({
      agent,
      root,
      folder: conversation.folder,
      text: request.text,
      notes: request.notes,
      session: conversation.session,
      // Without them the turn still runs.
      spaces: options.spaces ? await turnSpaces(options.spaces(root), request.space).catch(() => undefined) : undefined,
      snapshots: turns,
      log: options.log(root),
      env: await options.env(),
      signal: stop.signal,
      onEvent: pass,
    })
      .catch((error: Error) => {
        // The snapshots themselves failed: the turn ends saying why.
        const reply = open.get(id)!.messages.at(-1);
        if (reply?.role === "assistant" && !reply.done) pass({ kind: "end", changes: [], failed: error.message });
      })
      .finally(() => {
        running.delete(id);
        void conversations.save(open.get(id)!).catch(() => undefined);
      });
    return { ok: true, conversation };
  };

  const open_: AssistantTurns["open"] = async (root, id) => {
    const conversation = open.get(id) ?? (await conversations.read(id).catch(() => undefined));
    if (!root || !conversation || conversation.root !== root) return null;
    const reply = conversation.messages.at(-1);
    // A turn the app quit in the middle of ended there.
    if (!running.has(id) && reply?.role === "assistant" && !reply.done) return withEvent(conversation, { kind: "end", changes: [], failed: stoppedTurn });
    return conversation;
  };

  return {
    start,
    history: async (root) => (root ? conversations.list(root) : []),
    open: open_,
    stop: (id) => running.get(id)?.abort(),
    stopAll: () => running.forEach((turn) => turn.abort()),
  };
}
