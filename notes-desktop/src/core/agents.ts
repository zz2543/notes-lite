// 助手 runs through a command-line agent the user installed (ADR 0005): Claude Code, Codex,
// DeepSeek Harness or Pi, all equal. Which of them is installed is whichever command the search path
// (PATH) leads to, as a terminal would find it.
import { constants } from "node:fs";
import { access, stat } from "node:fs/promises";
import { delimiter, join } from "node:path";
import { agents, type AgentKind } from "../shared/agentKinds";

export * from "../shared/agentKinds";

/** An agent found on this computer. */
export interface InstalledAgent extends AgentKind {
  /** The file the command runs. */
  path: string;
}

export interface SearchPath {
  /** Folders joined by the platform's delimiter, as in PATH. */
  path: string;
  /** Windows only: the extensions a command may end in, as in PATHEXT. */
  pathext?: string;
}

const windows = process.platform === "win32";

async function runnable(file: string): Promise<boolean> {
  try {
    if (!(await stat(file)).isFile()) return false;
    if (!windows) await access(file, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/** The installed agents, each at the first place on the path that has it. */
export async function detectAgents({ path, pathext = ".COM;.EXE;.BAT;.CMD" }: SearchPath): Promise<InstalledAgent[]> {
  const folders = path.split(delimiter).filter(Boolean);
  const extensions = windows ? pathext.split(";").filter(Boolean) : [""];
  const found = await Promise.all(
    agents.map(async (agent) => {
      for (const folder of folders)
        for (const extension of extensions) {
          const file = join(folder, agent.command + extension.toLowerCase());
          if (await runnable(file)) return { ...agent, path: file };
        }
      return null;
    }),
  );
  return found.filter((agent) => agent !== null);
}
