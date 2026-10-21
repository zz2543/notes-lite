import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { AgentId } from "../../src/shared/agentKinds";

// Installs the fake command-line agent (fakeAgentProgram.mjs) as `command` in `dir`: a shell script, or a
// .cmd shim on Windows, that runs it with this Node and says where its script and log are, and which
// agent's output to speak: the one whose command it is (claude, codex, dsh or pi).

export type FakeStep =
  | { say: string }
  | { tool: string; input?: Record<string, unknown>; write?: { path: string; text: string }; toolFails?: boolean; waitFor?: string }
  | { waitFor: string }
  | { fail: string };

export interface FakeScript {
  session?: string;
  /** DeepSeek Harness only: the session asked for with --session-id is not there. */
  unknownSession?: boolean;
  /** DeepSeek Harness only: answer as one too old for JSON events (before 0.1.7) does. */
  tooOld?: boolean;
  steps: FakeStep[];
}

export interface FakeRun {
  argv: string[];
  cwd: string;
  stdin: string;
  /** DSH_PERMISSION_MODE, when the agent was run with it. */
  permissionMode?: string;
}

export interface FakeAgent {
  /** The command's file, as detection finds it. */
  path: string;
  /** Each run so far: what it was given. */
  runs(): Promise<FakeRun[]>;
}

const agentScript = join(__dirname, "fakeAgentProgram.mjs");

/** `scripts`: one per run in order (the last repeats), or one for every run. */
export async function installFakeAgent(dir: string, command: AgentId, scripts: FakeScript | FakeScript[]): Promise<FakeAgent> {
  await mkdir(dir, { recursive: true });
  const script = join(dir, `${command}.script.json`);
  const log = join(dir, `${command}.log`);
  await writeFile(script, JSON.stringify(scripts));
  const windows = process.platform === "win32";
  const path = join(dir, windows ? `${command}.cmd` : command);
  if (windows) {
    await writeFile(
      path,
      `@echo off\r\nset "FAKE_AGENT_DIALECT=${command}"\r\nset "FAKE_AGENT_SCRIPT=${script}"\r\nset "FAKE_AGENT_LOG=${log}"\r\n"${process.execPath}" "${agentScript}" %*\r\n`,
    );
  } else {
    const quote = (text: string) => `'${text.replace(/'/g, `'\\''`)}'`;
    await writeFile(
      path,
      `#!/bin/sh\nFAKE_AGENT_DIALECT=${command} FAKE_AGENT_SCRIPT=${quote(script)} FAKE_AGENT_LOG=${quote(log)} exec ${quote(process.execPath)} ${quote(agentScript)} "$@"\n`,
    );
    await chmod(path, 0o755);
  }
  return {
    path,
    runs: async () =>
      (await readFile(log, "utf8").catch(() => ""))
        .split("\n")
        .filter(Boolean)
        .map((line) => JSON.parse(line) as FakeRun),
  };
}
