// The command-line agents 助手 can run (ADR 0005); no Node here, so the page may read it too.
export type AgentId = "claude" | "codex" | "dsh" | "pi";

export interface AgentKind {
  id: AgentId;
  /** As the switch and the install guide name it. */
  name: string;
  /** The command a terminal runs it by. */
  command: string;
}

/** The four agents, in the order the switch and the install guide show them. */
export const agents: readonly AgentKind[] = [
  { id: "claude", name: "Claude Code", command: "claude" },
  { id: "codex", name: "Codex", command: "codex" },
  { id: "dsh", name: "DeepSeek Harness", command: "dsh" },
  { id: "pi", name: "Pi", command: "pi" },
];

/** A model name as typed: trimmed, and only if it can go on a command line as one word. */
export function modelName(typed: string): string | undefined {
  const name = typed.trim();
  return /^[\w.:/@[\]-]{1,120}$/.test(name) ? name : undefined;
}
