import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { scopeContains, spaceLibrary } from "../../src/core";
import { library } from "../support/library";

// Ported from the old SpaceLibraryTests: spaces live as `.notes/空间/<名称>.html` inside the note
// library and are checked through the files they leave on disk.
const read = (root: string, path: string) => readFile(join(root, path), "utf8");

describe("空间库", () => {
  it("creating a space writes an empty page with scope and icon meta", async () => {
    const root = await library({});
    const spaces = spaceLibrary(root);
    const space = await spaces.create({ name: "健身", icon: "🏋️", scope: { library: false, folders: ["健身", "日记"] } });

    expect(space.path).toBe(".notes/空间/健身.html");
    expect(space.hasPage).toBe(false);
    const html = await read(root, ".notes/空间/健身.html");
    expect(html).toContain('<meta name="lb-scope" content="健身, 日记">');
    expect(html).toContain('<meta name="lb-icon" content="🏋️">');

    const listed = await spaces.spaces();
    expect(listed.map((s) => s.name)).toEqual(["健身"]);
    expect(listed[0]!.icon).toBe("🏋️");
    expect(listed[0]!.scope).toEqual({ library: false, folders: ["健身", "日记"] });
    expect(existsSync(join(root, ".notes/空间/编写说明.md")), "the authoring guide is installed with the first space").toBe(true);
  });

  it("reads a whole-library scope and tells an empty page from a written one", async () => {
    const root = await library({
      ".notes/空间/全局.html": '<meta name="lb-icon" content="🌍">\n<meta content="*" name="lb-scope">\n<!-- 空的 -->\n  \n',
      ".notes/空间/雅思.html": '<meta name="lb-scope" content="英语-雅思">\n<div class="lb-card">内容</div>',
    });
    const spaces = await spaceLibrary(root).spaces();

    expect(spaces.map((s) => s.name)).toEqual(["全局", "雅思"]);
    expect(spaces[0]!.scope).toEqual({ library: true });
    expect(spaces[0]!.hasPage).toBe(false);
    expect(spaces[1]!.hasPage).toBe(true);
    expect(scopeContains({ library: true }, "任何/笔记.md")).toBe(true);
    expect(scopeContains(spaces[1]!.scope, "英语-雅思/单词.md")).toBe(true);
    expect(scopeContains(spaces[1]!.scope, "英语-雅思2/单词.md")).toBe(false);
    expect(scopeContains(spaces[1]!.scope, "日记/a.md")).toBe(false);
  });

  it("lets one folder belong to several spaces and refuses unusable names and scopes", async () => {
    const spaces = spaceLibrary(await library({}));
    await spaces.create({ name: "健身", icon: "🏋️", scope: { library: false, folders: ["日记"] } });
    await spaces.create({ name: "雅思", icon: "📚", scope: { library: false, folders: ["日记", "英语"] } });
    expect((await spaces.spaces()).filter((s) => scopeContains(s.scope, "日记/今天.md"))).toHaveLength(2);

    const whole = { library: true } as const;
    await expect(spaces.create({ name: "健身", icon: "x", scope: whole })).rejects.toMatchObject({ code: "exists" });
    await expect(spaces.create({ name: "a/b", icon: "x", scope: whole })).rejects.toMatchObject({ code: "invalid-name" });
    await expect(spaces.create({ name: "a\\b", icon: "x", scope: whole })).rejects.toMatchObject({ code: "invalid-name" });
    await expect(spaces.create({ name: ".隐藏", icon: "x", scope: whole })).rejects.toMatchObject({ code: "invalid-name" });
    await expect(spaces.create({ name: "  ", icon: "x", scope: whole })).rejects.toMatchObject({ code: "invalid-name" });
    await expect(spaces.create({ name: "空范围", icon: "x", scope: { library: false, folders: [] } })).rejects.toMatchObject({
      code: "empty-scope",
    });
    await expect(spaces.create({ name: "逗号", icon: "x", scope: { library: false, folders: ["a,b"] } })).rejects.toMatchObject({
      code: "scope-name",
    });
    expect((await spaces.spaces()).map((s) => s.name)).toEqual(["健身", "雅思"]);
  });
});
