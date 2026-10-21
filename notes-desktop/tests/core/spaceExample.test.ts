import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { notesInScope, spaceLibrary, spaceRequests } from "../../src/core";
import { library } from "../support/library";

// 新建示例空间 (ticket 31): a space named 组件示例 over a folder of its own with four sample notes, and a
// homepage the app writes itself, every component on it reading one of those notes' record tables.

/** 2026-10-21 (Wednesday) at noon, local time. */
const now = new Date(2026, 9, 21, 12);

type Records = { records: Record<string, unknown>[]; fields: { name: string; type: string }[] };

const query = async (root: string, space: string, source: string): Promise<Records> => {
  const reply = await spaceRequests(root, space).handle({ method: "query", args: [source] });
  if (!reply.ok) throw new Error(`${source}: ${reply.error.message}`);
  return reply.result as Records;
};

/** Every `source` and `target` the homepage's components read or write. */
const sourcesOf = (html: string) => [...html.matchAll(/<space-[a-z-]+\b[^>]*?\s(?:source|target)="([^"]+)"/g)].map((m) => m[1]!);

describe("示例空间", () => {
  it("is 组件示例 over a new folder of the same name holding four sample notes, with a homepage already written", async () => {
    const root = await library({ "日记/今天.md": "今天" });
    const space = await spaceLibrary(root).createExample(now);

    expect(space.name).toBe("组件示例");
    expect(space.scope).toEqual({ library: false, folders: ["组件示例"] });
    expect(space.hasPage).toBe(true);
    expect((await notesInScope(root, space.scope)).sort()).toEqual(
      ["组件示例/健身记录.md", "组件示例/待办清单.md", "组件示例/读书进度.md", "组件示例/专注时长.md"].sort(),
    );
    expect((await spaceLibrary(root).spaces()).map((s) => s.name)).toEqual(["组件示例"]);
    expect(await readFile(join(root, "日记/今天.md"), "utf8")).toBe("今天");
  });

  it("homepage uses every component on the new names only, each reading a record table that has records", async () => {
    const root = await library({});
    const { html } = await spaceLibrary(root).createExample(now);

    for (const component of ["space-stat", "space-chart", "space-calendar", "space-records", "space-quick-add"]) {
      expect(html, component).toContain(`<${component} `);
    }
    expect(html).not.toMatch(/\blb[-.]/);
    const sources = sourcesOf(html);
    expect(sources.length).toBeGreaterThanOrEqual(5);
    for (const source of new Set(sources)) expect((await query(root, "组件示例", source)).records.length, source).toBeGreaterThan(0);
  });

  it("shows under each card the markup that draws it, to copy", async () => {
    const root = await library({});
    const { html } = await spaceLibrary(root).createExample(now);
    const components = [...html.matchAll(/<(space-[a-z-]+)\b[^>]*>[^<]*<\/\1>/g)].map((m) => m[0]);
    expect(components.length).toBeGreaterThanOrEqual(5);
    expect(html.match(/>复制写法</g)).toHaveLength(components.length);
    expect(html).toContain('<code>&lt;space-chart source=&quot;组件示例/健身记录.md#体重&quot; x=&quot;日期&quot; y=&quot;体重&quot;');
    expect(html).toContain('&lt;/space-quick-add&gt;</code>');
  });

  it("records run up to the day it was made, so this week's numbers are not empty", async () => {
    const root = await library({});
    await spaceLibrary(root).createExample(now);
    const { records } = await query(root, "组件示例", "组件示例/健身记录.md");
    const dates = records.map((r) => r["日期"] as string).sort();
    expect(dates.at(-1)! <= "2026-10-21").toBe(true);
    expect(dates.at(-1)! >= "2026-10-19", "a workout this week").toBe(true);
    expect(dates[0]! < "2026-08-01", "a few months of history").toBe(true);
  });

  it("takes the next free name, 组件示例 2, when the space or the folder is already there", async () => {
    const root = await library({ "组件示例/我的.md": "别动" });
    const spaces = spaceLibrary(root);

    const second = await spaces.createExample(now);
    expect(second.name).toBe("组件示例 2");
    expect(second.scope).toEqual({ library: false, folders: ["组件示例 2"] });
    expect(await readdir(join(root, "组件示例"))).toEqual(["我的.md"]);

    const third = await spaces.createExample(now);
    expect(third.name).toBe("组件示例 3");
    expect((await spaces.spaces()).map((s) => s.name)).toEqual(["组件示例 2", "组件示例 3"]);
  });
});
