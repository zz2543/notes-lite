import { readdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { scopeContains, spaceGuide, spaceLibrary } from "../../src/core";
import { fakeTrash, library } from "../support/library";

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
    expect(html).toContain('<meta name="space-scope" content="健身, 日记">');
    expect(html).toContain('<meta name="space-icon" content="🏋️">');

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

  it("writes a prompt naming the guide, the space file, the scope and the record tables in it", async () => {
    const root = await library({
      "健身/训练记录.md":
        "# 训练记录\n\n## 卧推\n\n| 日期 | 动作 | 重量 | 组数 |\n|---|---|---|---|\n| 2026-10-18 | 卧推 | 60 | 5 |\n\n```\n| 不是 | 表 |\n|---|---|\n```\n",
      "健身/说明.md": "| 只是一行竖线 |\n\n正文",
      "日记/2026-10.md": "| 日期 | 时长 |\n| --- | --- |\n",
      "别处/无关.md": "| 字段 |\n|---|\n",
      ".notes/空间/旧.html": "| 隐藏 |\n|---|\n",
    });
    const spaces = spaceLibrary(root);
    const space = await spaces.create({ name: "健身", icon: "🏋️", scope: { library: false, folders: ["健身", "日记"] } });
    const prompt = await spaces.prompt(space);

    expect(prompt).toContain(join(root, ".notes", "空间", "编写说明.md"));
    expect(prompt).toContain(join(root, ".notes", "空间", "健身.html"));
    expect(prompt).toContain("健身、日记");
    expect(prompt).toContain("健身/训练记录.md#卧推：日期 | 动作 | 重量 | 组数");
    expect(prompt).toContain("日记/2026-10.md：日期 | 时长");
    expect(prompt, "tables outside the scope are not offered").not.toContain("别处");
    expect(prompt, "tables inside code fences are not record tables").not.toContain("不是");
    expect(prompt, "a lone row of bars is not a table").not.toContain("只是一行竖线");
    expect(prompt).not.toContain("隐藏");
  });

  it("offers a whole-library space every table, and says so when there are none", async () => {
    const root = await library({ "a.md": "## 心情\n\n| 日期 | 分数 |\n|:-:|--:|\n| 2026-10-01 | 7 |\n" });
    const spaces = spaceLibrary(root);
    const whole = await spaces.create({ name: "全局", icon: "🌍", scope: { library: true } });
    expect(await spaces.prompt(whole)).toContain("a.md#心情：日期 | 分数");
    expect(await spaces.prompt(whole)).toContain("整个笔记库");

    const empty = await spaces.create({ name: "空", icon: "", scope: { library: false, folders: ["没有"] } });
    expect(await spaces.prompt(empty)).toContain("暂无");
  });

  it("rewrites an outdated authoring guide", async () => {
    const root = await library({ ".notes/空间/编写说明.md": "旧版本" });
    await spaceLibrary(root).installGuide();
    expect(await read(root, ".notes/空间/编写说明.md")).toBe(spaceGuide);
    expect(spaceGuide).toContain(".notes/空间/<名称>.html");
    expect(spaceGuide).not.toContain(".留白");
  });

  it("keeps the order in the library, and deleting a space leaves its notes alone", async () => {
    const root = await library({ "健身/训练.md": "笔记" });
    const { trash, folder: trashed } = await fakeTrash();
    const spaces = spaceLibrary(root, { trash });
    for (const name of ["甲", "乙", "丙"]) await spaces.create({ name, icon: "", scope: { library: false, folders: ["健身"] } });
    await spaces.reorder(["丙", "甲", "乙"]);
    expect((await spaceLibrary(root).spaces()).map((s) => s.name)).toEqual(["丙", "甲", "乙"]);

    await spaces.delete("甲");
    expect((await spaces.spaces()).map((s) => s.name)).toEqual(["丙", "乙"]);
    expect(await read(root, "健身/训练.md")).toBe("笔记");
    expect(await read(root, ".notes/空间/顺序.json")).not.toContain("甲");
    expect(await readdir(trashed), "the space file goes to the trash").toEqual(["甲.html"]);
    await expect(spaces.delete("甲")).rejects.toMatchObject({ code: "not-found" });
  });

  it("renames, re-icons and re-scopes a space, keeping its page and its place", async () => {
    const root = await library({});
    const spaces = spaceLibrary(root);
    await spaces.create({ name: "健身", icon: "🏋️", scope: { library: false, folders: ["健身"] } });
    await spaces.create({ name: "雅思", icon: "📚", scope: { library: false, folders: ["英语"] } });
    await writeFile(join(root, ".notes/空间/健身.html"), (await read(root, ".notes/空间/健身.html")) + "<p>主页</p>");

    const edited = await spaces.update("健身", { name: "力量", icon: "💪", scope: { library: true } });
    expect(edited.scope).toEqual({ library: true });
    expect((await spaces.spaces()).map((s) => s.name)).toEqual(["力量", "雅思"]);
    const html = await read(root, ".notes/空间/力量.html");
    expect(html).toContain("<p>主页</p>");
    expect(html).toContain('content="*"');
    expect(html).toContain("💪");
    expect(existsSync(join(root, ".notes/空间/健身.html"))).toBe(false);

    await expect(spaces.update("力量", { name: "雅思", icon: "", scope: { library: true } })).rejects.toMatchObject({ code: "exists" });
    expect(await read(root, ".notes/空间/力量.html")).toBe(html);
  });

  it("still reads lb-scope and lb-icon, and editing such a space keeps a single scope meta", async () => {
    const root = await library({ ".notes/空间/旧.html": '<meta name="lb-scope" content="健身">\n<meta name="lb-icon" content="🏋️">\n<p>旧主页</p>' });
    const spaces = spaceLibrary(root);
    const [old] = await spaces.spaces();
    expect(old).toMatchObject({ name: "旧", icon: "🏋️", scope: { library: false, folders: ["健身"] }, hasPage: true });

    await spaces.update("旧", { name: "旧", icon: "💪", scope: { library: false, folders: ["健身", "日记"] } });
    const html = await read(root, ".notes/空间/旧.html");
    expect(html.match(/-scope"/g), "one scope meta, whichever name the file used").toHaveLength(1);
    expect(html.match(/-icon"/g)).toHaveLength(1);
    expect((await spaces.space("旧")).scope).toEqual({ library: false, folders: ["健身", "日记"] });
    expect((await spaces.space("旧")).icon).toBe("💪");
    expect(html).toContain("<p>旧主页</p>");
  });

  it("prefers space-scope when a file declares both names", async () => {
    const root = await library({ ".notes/空间/双.html": '<meta name="lb-scope" content="旧">\n<meta name="space-scope" content="新">\n' });
    expect((await spaceLibrary(root).space("双")).scope).toEqual({ library: false, folders: ["新"] });
  });

  it("renaming notes and folders updates scopes and component paths in every space file", async () => {
    const root = await library({});
    const spaces = spaceLibrary(root);
    await spaces.create({ name: "健身", icon: "", scope: { library: false, folders: ["健身", "健身房", "日记"] } });
    const page =
      (await read(root, ".notes/空间/健身.html")) +
      `<space-chart source="健身/训练记录.md#卧推" x="日期"></space-chart>
<lb-quick-add target='健身/训练记录.md'></lb-quick-add>
<lb-stat source="健身房/训练记录.md"></lb-stat>
<lb-records source="健身/训练记录#卧推"></lb-records>
<script>space.query("健身/训练记录.md#深蹲"); lb.query("健身/训练记录.md.bak");</script>
`;
    await writeFile(join(root, ".notes/空间/健身.html"), page);

    await spaces.syncPaths("健身/训练记录.md", "健身/力量.md");
    let html = await read(root, ".notes/空间/健身.html");
    expect(html).toContain('source="健身/力量.md#卧推"');
    expect(html).toContain("target='健身/力量.md'");
    expect(html, "exact path literals in scripts follow too").toContain('space.query("健身/力量.md#深蹲")');
    expect(html, "other strings are left alone").toContain('lb.query("健身/训练记录.md.bak")');
    expect(html).toContain('source="健身房/训练记录.md"');
    expect(html, "sources written without .md follow too").toContain('source="健身/力量#卧推"');

    await spaces.syncPaths("健身", "运动/健身");
    html = await read(root, ".notes/空间/健身.html");
    expect((await spaces.space("健身")).scope).toEqual({ library: false, folders: ["运动/健身", "健身房", "日记"] });
    expect(html).toContain('source="运动/健身/力量.md#卧推"');
    expect(html, "a sibling folder sharing the prefix is untouched").toContain('source="健身房/训练记录.md"');
    expect(html, "the meta keeps its name").toContain('<meta name="space-scope" content="运动/健身, 健身房, 日记">');
  });
});
