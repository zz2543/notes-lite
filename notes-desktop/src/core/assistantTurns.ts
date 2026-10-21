// 助手栏 turns as the app runs them (assistant-spec): a conversation is begun or continued, a turn
// at a time; its events are folded into it (shared/conversation's one rule) and passed on as they
// come, and it is kept with the app (对话记录) once the turn is over.
import type { AgentId } from "../shared/agentKinds";
import { canRevert, emptyReply, stoppedTurn, withEvent, type Conversation, type ConversationSummary, type Message, type Reply, type ReviewChoice, type TurnChange, type TurnEvent } from "../shared/conversation";
import type { ReviewMode } from "../shared/preferences";
import type { InstalledAgent } from "./agents";
import type { ConversationStore } from "./conversations";
import { OperationLogError, type OperationLog } from "./operationLog";
import { SnapshotError, type DiffLine, type SnapshotStore } from "./snapshots";
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

/** What the review card asks of a turn: keep it all, or take back one note or the whole turn. */
export interface TurnReviewRequest {
  conversation: string;
  turn: string;
  action: ReviewChoice;
  /** The note to take back alone (library-relative); none takes back the whole turn. */
  path?: string;
}

/** Answered like a turn's start: the conversation as it now stands, or why not. */
export type TurnReviewed = TurnStarted;

export type TurnDiff = { ok: true; lines: DiffLine[] | null } | { ok: false; message: string };

export interface AssistantTurnsOptions {
  conversations: ConversationStore;
  snapshots: SnapshotStore;
  /** The library's operation log, which a turn's changes are recorded in. */
  log(root: string): OperationLog;
  /** The agents installed now, looked for at each turn. */
  agents(): Promise<InstalledAgent[]>;
  /** What an agent runs with. */
  env(): Promise<NodeJS.ProcessEnv>;
  /** The 写入审查 setting now: a card after each turn, or keep it all. */
  reviewMode(): ReviewMode;
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
  /** Does what the review card asks and answers with the conversation as it now stands. */
  review(root: string | null, request: TurnReviewRequest): Promise<TurnReviewed>;
  /** One note's lines as the turn changed them; null for an attachment. */
  diff(root: string | null, turn: string, path: string): Promise<TurnDiff>;
}

/** A turn with something to review gets a card, unless the setting keeps it all. */
const reviewOf = (end: { changes: TurnChange[]; outside?: string[] }, mode: ReviewMode) =>
  end.changes.length === 0 && !end.outside?.length ? undefined : mode === "keep" ? "kept" : "pending";

/** Going on with the conversation keeps what earlier turns left waiting: 全部保留 is the default. */
const keepWaiting = (message: Message): Message => (message.role === "assistant" && message.review === "pending" ? { ...message, review: "kept" } : message);

/** Why the snapshots or the log refused, to tell the user; anything else is a bug and is thrown on. */
const knownReason = (error: unknown) => {
  if (error instanceof SnapshotError || error instanceof OperationLogError) return error.message;
  throw error;
}

export function assistantTurns(options: AssistantTurnsOptions): AssistantTurns {
  const { conversations } = options;
  // The conversations of this run stay in memory too.
  const live = new Map<string, Conversation>();
  const running = new Map<string, AbortController>();
  // Kept one save at a time, each the conversation as it stands then.
  let saving = Promise.resolve();
  const keep = (id: string) => {
    saving = saving.then(() => conversations.save(live.get(id)!)).catch(() => undefined);
  };
  const loaded = async (id: string) => live.get(id) ?? (await conversations.read(id).catch(() => undefined));

  const start: AssistantTurns["start"] = async (root, request, send) => {
    if (!root) return { ok: false, message: "请先打开笔记库。" };
    const known = request.conversation ? await loaded(request.conversation) : undefined;
    let conversation = known ?? conversations.start({ agent: request.agent, root, folder: request.folder });
    if (conversation.root !== root) return { ok: false, message: "这个对话属于另一个笔记库。" };
    if (running.has(conversation.id)) return { ok: false, message: "上一轮还没有结束。" };
    const agent = (await options.agents()).find((a) => a.id === conversation.agent);
    if (!agent) return { ok: false, message: "没有找到这个对话所用的 Agent，请确认它仍然安装着。" };
    conversation = {
      ...conversation,
      messages: [...conversation.messages.map(keepWaiting), { role: "user", text: request.text, notes: request.notes }, emptyReply()],
    };
    const id = conversation.id;
    live.set(id, conversation);
    await conversations.save(conversation);
    const stop = new AbortController();
    running.set(id, stop);
    const pass = (turnEvent: TurnEvent) => {
      const review = turnEvent.kind === "end" ? reviewOf(turnEvent, options.reviewMode()) : undefined;
      const event: TurnEvent = review && turnEvent.kind === "end" ? { ...turnEvent, review } : turnEvent;
      const before = live.get(id)!;
      live.set(id, withEvent(before, event));
      // The agent's id for it is kept at once, so it can be continued even if the app quits mid-turn.
      if (event.kind === "session" && event.id !== before.session) keep(id);
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
        const reply = live.get(id)!.messages.at(-1);
        if (reply?.role === "assistant" && !reply.done) pass({ kind: "end", changes: [], failed: error.message });
      })
      .finally(() => {
        running.delete(id);
        keep(id);
      });
    return { ok: true, conversation };
  };

  const review: AssistantTurns["review"] = async (root, request) => {
    if (!root) return { ok: false, message: "请先打开笔记库。" };
    const conversation = await loaded(request.conversation);
    if (!conversation || conversation.root !== root) return { ok: false, message: "找不到这个对话。" };
    const at = conversation.messages.findIndex((m) => m.role === "assistant" && m.turn === request.turn);
    const reply = conversation.messages[at] as Reply | undefined;
    if (!reply) return { ok: false, message: "找不到这一轮。" };
    let next: Reply;
    try {
      next = request.action === "keep" ? { ...reply, review: "kept" } : await revert(root, reply, request.path);
    } catch (error) {
      return { ok: false, message: knownReason(error) };
    }
    const updated = { ...conversation, messages: conversation.messages.map((m, i) => (i === at ? next : m)) };
    live.set(updated.id, updated);
    await conversations.save(updated);
    return { ok: true, conversation: updated };
  };

  // Taking back the whole turn is undoing its operation-log entry, so the log says so too; taking
  // back the last note left does the same.
  const revert = async (root: string, reply: Reply, path?: string): Promise<Reply> => {
    const turns = options.snapshots.library(root);
    const log = options.log(root);
    const entry = reply.entry ? (await log.entries()).find((e) => e.id === reply.entry && !e.undone) : undefined;
    if (path !== undefined) await turns.revert(reply.turn!, path);
    else if (!entry) await turns.revert(reply.turn!);
    const left = (await turns.turn(reply.turn!)).changes.some(canRevert);
    if (entry && (path === undefined || !left)) await log.undo(entry.id);
    const { changes } = await turns.turn(reply.turn!);
    return { ...reply, changes, review: changes.some(canRevert) ? "pending" : "reverted" };
  };

  const diff: AssistantTurns["diff"] = async (root, turn, path) => {
    if (!root) return { ok: false, message: "请先打开笔记库。" };
    try {
      return { ok: true, lines: await options.snapshots.library(root).diff(turn, path) };
    } catch (error) {
      return { ok: false, message: knownReason(error) };
    }
  };

  const open: AssistantTurns["open"] = async (root, id) => {
    const conversation = live.get(id) ?? (await conversations.read(id).catch(() => undefined));
    if (!root || !conversation || conversation.root !== root) return null;
    const reply = conversation.messages.at(-1);
    // A turn the app quit in the middle of ended there; what it changed is not known.
    if (!running.has(id) && reply?.role === "assistant" && !reply.done) {
      const messages = [...conversation.messages.slice(0, -1), { ...reply, done: true, failed: stoppedTurn }];
      return { ...conversation, messages };
    }
    return conversation;
  };

  return {
    start,
    history: async (root) => (root ? conversations.list(root) : []),
    open,
    stop: (id) => running.get(id)?.abort(),
    stopAll: () => running.forEach((turn) => turn.abort()),
    review,
    diff,
  };
}
