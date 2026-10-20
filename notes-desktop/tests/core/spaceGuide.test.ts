import { execFile } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";
import { spaceGuide, spaceGuideVersion } from "../../src/core";
import { scratchFolder } from "../support/library";

// The authoring guide an agent reads before writing a homepage (ticket 20): the new names, the old ones
// as aliases, and type declarations that hold up under the TypeScript compiler.

const tsc = join(__dirname, "../../node_modules/typescript/bin/tsc");

/** The guide's TypeScript block. */
const declarations = () => {
  const block = /```ts\n([\s\S]*?)```/.exec(spaceGuide);
  expect(block, "the guide carries a ```ts block").not.toBeNull();
  return block![1]!;
};

/** Compiles the declarations with a page script; answers the compiler's complaints, or "" when it has none. */
async function compile(script: string): Promise<string> {
  const dir = await scratchFolder("space-types-");
  await writeFile(join(dir, "space.d.ts"), declarations());
  await writeFile(join(dir, "page.ts"), script);
  const run = promisify(execFile);
  const args = ["--noEmit", "--strict", "--target", "es2023", "--module", "esnext", "--lib", "es2023,dom", join(dir, "space.d.ts"), join(dir, "page.ts")];
  return run(process.execPath, [tsc, ...args], { cwd: dir }).then(
    () => "",
    (error: { stdout?: string }) => error.stdout || String(error),
  );
}

describe("空间主页编写说明", () => {
  it("teaches the new names, under .notes/", () => {
    expect(spaceGuideVersion).toBe(3);
    expect(spaceGuide).toContain(`版本 ${spaceGuideVersion}`);
    expect(spaceGuide).toContain(".notes/空间/<名称>.html");
    expect(spaceGuide).not.toContain(".留白");
    for (const name of ['<meta name="space-scope"', '<meta name="space-icon"', "space.query(", "space.append(", 'space.on("change"', "<space-stat", "<space-chart", "<space-calendar", "<space-quick-add", "<space-records", "--space-accent", "--space-font", ".space-card"]) {
      expect(spaceGuide, name).toContain(name);
    }
  });

  it("names the old lb names as aliases that keep working", () => {
    const aliases = spaceGuide.slice(spaceGuide.indexOf("## 旧名称"));
    expect(aliases).not.toBe(spaceGuide);
    for (const name of ["`lb`", "`lb-*`", "`--lb-*`", "`lb-scope`", "`lb-icon`"]) expect(aliases, name).toContain(name);
    // Outside that section the guide only teaches the new names.
    const before = spaceGuide.slice(0, spaceGuide.indexOf("## 旧名称"));
    expect(before).not.toMatch(/\blb[.-]/);
  });

  it("declares the interface and components in types the compiler accepts, and that catch mistakes", async () => {
    const page = `
      const rows = await space.query("健身/训练记录.md#卧推", { sort: "-日期", limit: 5, filter: (r) => typeof r["重量"] === "number" });
      const names: string[] = rows.fields.map((f) => f.name + f.type);
      const row: number = rows[0]!._row;
      await space.append("健身/训练记录.md#卧推", { 日期: space.today(), 重量: 60 }, { header: ["日期", "重量"] });
      const { count } = await space.update("健身/训练记录.md#卧推", { _row: 0 }, { 重量: 62.5 });
      const scope = await space.scope();
      if (!scope.library) scope.folders.join();
      const notes = await space.notes();
      notes[0]?.path.toUpperCase();
      const off: () => void = space.on("change", (paths) => paths.join());
      off();
      const same: typeof space = lb;
      const stat: HTMLElement = document.createElement("space-stat");
      try { await space.read("x.md"); } catch (e) { if (e instanceof Error && (e as SpaceError).code === "outside-scope") {} }
      export { names, row, count, same, stat };
    `;
    expect(await compile(page)).toBe("");
    expect(await compile("space.query(1);\nexport {};")).toMatch(/error TS/);
    expect(await compile('space.on("click", () => {});\nexport {};')).toMatch(/error TS/);
  }, 60_000);
});
