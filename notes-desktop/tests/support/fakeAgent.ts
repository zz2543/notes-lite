import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

// Installs the fake command-line agent (fakeAgentProgram.mjs) as `command` in `dir`: a shell script, or a
// .cmd shim on Windows, that runs it with this Node and says where its script and log are.

export type FakeStep =
  | { say: string }
  | { tool: string; input?: Record<string, unknown>; write?: { path: string; text: string }; toolFails?: boolean }
  | { waitFor: string }
  | { fail: string };

export interface FakeScript {
  session?: string;
  steps: FakeStep[];
}

export interface FakeRun {
  argv: string[];
  cwd: string;
  stdin: string;
}

export interface FakeAgent {
  /** The command's file, as detection finds it. */
  path: string;
  /** Each run so far: what it was given. */
  runs(): Promise<FakeRun[]>;
}

const agentScript = join(__dirname, "fakeAgentProgram.mjs");

/** `scripts`: one per run in order (the last repeats), or one for every run. */
export async function installFakeAgent(dir: string, command: string, scripts: FakeScript | FakeScript[]): Promise<FakeAgent> {
  await mkdir(dir, { recursive: true });
  const script = join(dir, `${command}.script.json`);
  const log = join(dir, `${command}.log`);
  await writeFile(script, JSON.stringify(scripts));
  const windows = process.platform === "win32";
  const path = join(dir, windows ? `${command}.cmd` : command);
  if (windows) {
    await writeFile(
      path,
      `@echo off\r\nset "FAKE_AGENT_SCRIPT=${script}"\r\nset "FAKE_AGENT_LOG=${log}"\r\n"${process.execPath}" "${agentScript}" %*\r\n`,
    );
  } else {
    const quote = (text: string) => `'${text.replace(/'/g, `'\\''`)}'`;
    await writeFile(
      path,
      `#!/bin/sh\nFAKE_AGENT_SCRIPT=${quote(script)} FAKE_AGENT_LOG=${quote(log)} exec ${quote(process.execPath)} ${quote(agentScript)} "$@"\n`,
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
