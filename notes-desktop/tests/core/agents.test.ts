import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { delimiter, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { agents, detectAgents } from "../../src/core";

// 助手 runs through a command-line agent installed on this computer: whichever of the four is on the
// search path. A fake PATH of scratch folders stands in for the user's.

const windows = process.platform === "win32";
let scratch: string;

beforeEach(async () => {
  scratch = await mkdtemp(join(tmpdir(), "notes-agents-"));
});
afterEach(async () => {
  await rm(scratch, { recursive: true, force: true });
});

/** An installed command: `name.cmd` on Windows (how npm installs one), an executable file elsewhere. */
async function install(dir: string, name: string) {
  await mkdir(dir, { recursive: true });
  const file = join(dir, windows ? `${name}.cmd` : name);
  await writeFile(file, windows ? "@echo off\r\n" : "#!/bin/sh\n");
  if (!windows) await chmod(file, 0o755);
  return file;
}

describe("detectAgents", () => {
  it("knows the four agents, in the order the switch shows them", () => {
    expect(agents.map((a) => [a.name, a.command])).toEqual([
      ["Claude Code", "claude"],
      ["Codex", "codex"],
      ["DeepSeek Harness", "dsh"],
      ["Pi", "pi"],
    ]);
  });

  it("finds the agents installed in any folder on the search path, with where each lies", async () => {
    const a = join(scratch, "a");
    const b = join(scratch, "b");
    const claude = await install(a, "claude");
    const dsh = await install(b, "dsh");
    // A folder called `pi` is not a command.
    await mkdir(join(b, "pi"));
    const found = await detectAgents({ path: [join(scratch, "missing"), a, b].join(delimiter) });
    expect(found).toEqual([
      { id: "claude", name: "Claude Code", command: "claude", path: claude },
      { id: "dsh", name: "DeepSeek Harness", command: "dsh", path: dsh },
    ]);
  });

  it("takes the first one on the path when an agent is installed twice", async () => {
    const first = await install(join(scratch, "first"), "codex");
    await install(join(scratch, "second"), "codex");
    const found = await detectAgents({ path: [join(scratch, "first"), join(scratch, "second")].join(delimiter) });
    expect(found.map((a) => a.path)).toEqual([first]);
  });

  it("finds none on a path without them", async () => {
    await mkdir(join(scratch, "empty"));
    expect(await detectAgents({ path: join(scratch, "empty") })).toEqual([]);
    expect(await detectAgents({ path: "" })).toEqual([]);
  });

  it.skipIf(windows)("passes over a file that cannot be run", async () => {
    const dir = join(scratch, "bin");
    await mkdir(dir);
    await writeFile(join(dir, "claude"), "#!/bin/sh\n");
    await chmod(join(dir, "claude"), 0o644);
    expect(await detectAgents({ path: dir })).toEqual([]);
  });

  it.runIf(windows)("on Windows, finds a command by the extensions PATHEXT lists", async () => {
    const dir = join(scratch, "bin");
    await mkdir(dir);
    await writeFile(join(dir, "pi.exe"), "");
    await writeFile(join(dir, "codex.txt"), "");
    const found = await detectAgents({ path: dir, pathext: ".COM;.EXE;.BAT;.CMD" });
    expect(found.map((a) => a.id)).toEqual(["pi"]);
  });
});
