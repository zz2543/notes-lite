import { chmod, mkdir, rename, rm, symlink, utimes, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createSearchIndex, type SearchHit } from "../../src/core";
import { library, removeLibraries } from "../support/library";

afterEach(removeLibraries);

/** A hit as the list shows it: its snippet with the match in brackets. */
const shown = (hit: SearchHit) => {
  const { text, match } = hit.snippet;
  return match ? `${text.slice(0, match.start)}[${text.slice(match.start, match.end)}]${text.slice(match.end)}` : text;
};

describe("搜索", () => {
  it("finds notes by title or body, with the folder and the matching line", async () => {
    const index = createSearchIndex(
      await library({
        "日记/雨后的散步.md": "# 雨后的散步\n\n小路上长满了青苔。\n",
        "读书/青苔.md": "# 青苔\n\n一本关于苔藓的书\n",
        "读书.md": "# 读书\n\n没有相关内容\n",
      }),
    );

    const { hits } = await index.search("青苔");

    expect(hits.map((h) => h.path).sort()).toEqual(["日记/雨后的散步.md", "读书/青苔.md"]);
    const walk = hits.find((h) => h.path === "日记/雨后的散步.md")!;
    expect(walk.title).toBe("雨后的散步");
    expect(walk.folder).toBe("日记");
    expect(shown(walk)).toBe("小路上长满了[青苔]。");
  });

  it("keeps the match in view on a long line, and line endings out of the snippet", async () => {
    const index = createSearchIndex(
      await library({
        "长段落.md": `${"甲".repeat(100)}青苔${"乙".repeat(200)}\n`,
        "短行.md": "> 雨后的青苔\r\n第二行\r\n",
      }),
    );

    const { hits } = await index.search("青苔");

    expect(hits.map((h) => [h.title, shown(h)]).sort()).toEqual([
      ["短行", "雨后的[青苔]"],
      ["长段落", `…${"甲".repeat(10)}[青苔]${"乙".repeat(80)}…`],
    ]);
  });

  it("shows how a note begins when only its title matches", async () => {
    const index = createSearchIndex(
      await library({ "工作/周报.md": "\n\n- 本周完成了三件事\n- 下周计划\n", "工作/空的周报.md": "" }),
    );

    const { hits } = await index.search("周报");

    expect(hits.map((h) => [h.title, shown(h)]).sort()).toEqual([
      ["周报", "本周完成了三件事"],
      ["空的周报", ""],
    ]);
  });

  it("searches the whole library, or one folder with its subfolders", async () => {
    const index = createSearchIndex(
      await library({
        "A/直属.md": "笔记",
        "A/子目录/深层.md": "笔记",
        "A B/邻居.md": "笔记",
        "根目录.md": "笔记",
      }),
    );

    const paths = async (folder?: string) => (await index.search("笔记", { folder })).hits.map((h) => h.path).sort();

    expect(await paths()).toEqual(["A B/邻居.md", "A/子目录/深层.md", "A/直属.md", "根目录.md"]);
    expect(await paths("")).toEqual(await paths());
    expect(await paths("A")).toEqual(["A/子目录/深层.md", "A/直属.md"]);
    expect(await paths("A/子目录")).toEqual(["A/子目录/深层.md"]);
  });

  it("leaves out hidden entries and other files, and finds notes that aren't UTF-8 by title", async () => {
    const index = createSearchIndex(
      await library({
        ".notes/spaces/健身.md": "健身",
        ".留白/健身.md": "健身",
        "日记/.健身草稿.md": "健身",
        "健身计划.txt": "健身",
        "健身记录.MD": "每周三次",
        "健身旧档.md": Buffer.from([0xbd, 0xa1, 0xc9, 0xed]), // "健身" in GBK
      }),
    );

    const { hits } = await index.search("健身");

    expect(hits.map((h) => [h.path, shown(h)]).sort()).toEqual([
      ["健身旧档.md", ""],
      ["健身记录.MD", "每周三次"],
    ]);
  });

  it("lists the most recently modified notes first, up to a limit, and tells how many matched", async () => {
    const root = await library({ "旧.md": "散步", "新.md": "散步", "中/中.md": "散步" });
    const at = (name: string, day: number) => utimes(join(root, name), new Date(2026, 9, day), new Date(2026, 9, day));
    await Promise.all([at("旧.md", 1), at("中/中.md", 5), at("新.md", 9)]);
    const index = createSearchIndex(root);

    const all = await index.search("散步");
    const first = await index.search("散步", { limit: 2 });

    expect(all.hits.map((h) => h.title)).toEqual(["新", "中", "旧"]);
    expect(first.hits.map((h) => h.title)).toEqual(["新", "中"]);
    expect(first.total).toBe(3);
  });

  it("follows a note that was saved, added or removed once told its path", async () => {
    const root = await library({ "日记/今天.md": "下雨", "日记/昨天.md": "晴天" });
    const index = createSearchIndex(root);
    const titles = async (query: string) => (await index.search(query)).hits.map((h) => h.title).sort();
    expect(await titles("下雨")).toEqual(["今天"]);

    await writeFile(join(root, "日记/今天.md"), "雨停了，出太阳");
    await writeFile(join(root, "日记/明天.md"), "也许下雨");
    await rm(join(root, "日记/昨天.md"));
    await Promise.all(["日记/今天.md", "日记\\明天.md", "日记/昨天.md"].map((path) => index.update(path)));

    expect(await titles("下雨")).toEqual(["明天"]);
    expect(await titles("太阳")).toEqual(["今天"]);
    expect(await titles("晴天")).toEqual([]);
  });

  it("follows a folder that was added, removed or renamed once told its path", async () => {
    const root = await library({ "旅行/京都.md": "红叶", "旅行/东京.md": "红叶" });
    const index = createSearchIndex(root);
    const paths = async () => (await index.search("红叶")).hits.map((h) => h.path).sort();
    expect(await paths()).toEqual(["旅行/东京.md", "旅行/京都.md"]);

    await rename(join(root, "旅行"), join(root, "游记"));
    await mkdir(join(root, "游记/秋天"));
    await writeFile(join(root, "游记/秋天/奈良.md"), "红叶与鹿");
    await index.update("旅行");
    await index.update("游记");

    expect(await paths()).toEqual(["游记/东京.md", "游记/京都.md", "游记/秋天/奈良.md"]);
  });

  // Windows has no unreadable-folder permission to set from here.
  it.skipIf(process.platform === "win32")("indexes the rest of the library when a folder can't be read", async () => {
    const root = await library({ "公开/计划.md": "目标", "私密/日记.md": "目标" });
    await chmod(join(root, "私密"), 0o000);
    try {
      const { hits } = await createSearchIndex(root).search("目标");

      expect(hits.map((h) => h.path)).toEqual(["公开/计划.md"]);
    } finally {
      await chmod(join(root, "私密"), 0o755);
    }
  });

  it("never reaches outside the library through a link", async () => {
    const outside = await library({ "秘密.md": "口令" });
    const root = await library({ "日记/今天.md": "没有口令" });
    await symlink(outside, join(root, "外链"), "junction");

    const { hits } = await createSearchIndex(root).search("口令");

    expect(hits.map((h) => h.path)).toEqual(["日记/今天.md"]);
  });

  it("ignores case and Unicode composition, like the old app", async () => {
    const index = createSearchIndex(
      await library({
        "Walks.md": "An Evening WALK by the café\n",
        "Café notes.md": "Tasting café au lait\n",
      }),
    );

    const walk = await index.search("walk");
    const cafe = await index.search("CAFÉ");

    expect(walk.hits.map(shown)).toEqual(["An Evening [WALK] by the café"]);
    expect(cafe.hits.map((h) => h.path).sort()).toEqual(["Café notes.md", "Walks.md"]);
    expect(cafe.hits.find((h) => h.path === "Café notes.md")!.snippet.match).toBeDefined();
  });
});
