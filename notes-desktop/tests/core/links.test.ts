import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { openLibrary } from "../../src/core";
import { library } from "../support/library";

// Ticket 13: following 笔记链接 and links to attachments; importing images and attachments.

describe("跟随链接", () => {
  it("finds a Chinese note by its title, past an anchor and alias, and refuses one that isn't there or is ambiguous", async () => {
    // As the old WorkspaceTests.testFollowingLinkFindsChineseNoteAndRejectsAmbiguity.
    const root = await library({ "阅读/摘记.md": "# 摘记", "入口.md": "", "其他/入口.md": "" });
    const lib = await openLibrary(root);

    expect(await lib.followLink("入口.md", { target: "摘记#章节|显示名称", wiki: true })).toEqual({ kind: "note", path: "阅读/摘记.md" });
    await expect(lib.followLink("入口.md", { target: "不存在", wiki: true })).rejects.toThrow("找不到笔记“不存在”");

    await lib.createNote("其他", "摘记");
    // Beside the note wins; then a path from the library root; a bare title found twice elsewhere is refused.
    expect(await lib.followLink("其他/入口.md", { target: "摘记", wiki: true })).toEqual({ kind: "note", path: "其他/摘记.md" });
    expect(await lib.followLink("其他/入口.md", { target: "阅读/摘记", wiki: true })).toEqual({ kind: "note", path: "阅读/摘记.md" });
    await expect(lib.followLink("入口.md", { target: "摘记", wiki: true })).rejects.toThrow(
      /^有多篇笔记叫“摘记”，请在链接里写上文件夹，例如 \[\[(其他|阅读)\/摘记\]\]。$/,
    );
    // A note at the root, found from the root, wins over the same title in folders.
    await lib.createNote("", "摘记");
    expect(await lib.followLink("入口.md", { target: "摘记", wiki: true })).toEqual({ kind: "note", path: "摘记.md" });
  });

  it("follows Markdown links to notes and attachments, percent-encoded or not, never outside the library", async () => {
    const root = await library({ "阅读/摘记.md": "", "附件/说明 书.pdf": "pdf", "阅读/笔记.md": "" });
    const lib = await openLibrary(root);

    expect(await lib.followLink("阅读/笔记.md", { target: "摘记.md", wiki: false })).toEqual({ kind: "note", path: "阅读/摘记.md" });
    // .md may be left out, as the old app let it.
    expect(await lib.followLink("阅读/笔记.md", { target: "摘记", wiki: false })).toEqual({ kind: "note", path: "阅读/摘记.md" });
    expect(await lib.followLink("阅读/笔记.md", { target: "阅读/摘记#要点", wiki: false })).toEqual({ kind: "note", path: "阅读/摘记.md" });
    expect(await lib.followLink("阅读/笔记.md", { target: "../附件/说明%20书.pdf", wiki: false })).toEqual({ kind: "file", path: "附件/说明 书.pdf" });
    // From the library root too, as the old app read them.
    expect(await lib.followLink("阅读/笔记.md", { target: "附件/说明 书.pdf", wiki: false })).toEqual({ kind: "file", path: "附件/说明 书.pdf" });
    await expect(lib.followLink("阅读/笔记.md", { target: "../附件/丢了.png", wiki: false })).rejects.toThrow("找不到附件“../附件/丢了.png”");
    await expect(lib.followLink("阅读/笔记.md", { target: "../../outside.md", wiki: false })).rejects.toThrow("找不到笔记");
    // `[[说明 书.pdf]]`, `![[说明 书.pdf|页 2]]`: a file by its name, found in 附件 where imports go.
    expect(await lib.followLink("阅读/笔记.md", { target: "说明 书.pdf|页 2", wiki: true })).toEqual({ kind: "file", path: "附件/说明 书.pdf" });
    await expect(lib.followLink("阅读/笔记.md", { target: "丢了.png", wiki: true })).rejects.toThrow("找不到附件“丢了.png”");
  });
});

describe("显示图片", () => {
  it("reads an image the note can show as a data: URL, and says why it can't show the others", async () => {
    const root = await library({ "笔记.md": "", "附件/图.png": "png", "附件/照片.heic": "heic", "附件/说明.pdf": "pdf" });
    const lib = await openLibrary(root);

    expect(await lib.readImage("笔记.md", { target: "附件/图.png", wiki: false })).toBe(`data:image/png;base64,${Buffer.from("png").toString("base64")}`);
    expect(await lib.readImage("笔记.md", { target: "图.png", wiki: true })).toMatch(/^data:image\/png;base64,/);
    // HEIC is imported as an image but the page can't draw it: it opens with another app instead.
    await expect(lib.readImage("笔记.md", { target: "照片.heic", wiki: true })).rejects.toMatchObject({ code: "not-allowed", message: "无法在笔记里显示“照片.heic”，双击可用其他应用打开。" });
    await expect(lib.readImage("笔记.md", { target: "附件/说明.pdf", wiki: false })).rejects.toMatchObject({ code: "not-allowed" });
    await expect(lib.readImage("笔记.md", { target: "附件/丢了.png", wiki: false })).rejects.toMatchObject({ code: "not-found", message: "找不到附件“附件/丢了.png”。" });
  });
});

describe("导入附件", () => {
  it("copies into 附件 at the library root and gives a link relative to the note, an image's shown in place", async () => {
    const root = await library({ "日记/今天.md": "", "根.md": "" });
    const lib = await openLibrary(root);

    expect(await lib.importAttachment("日记/今天.md", "示例.png", Buffer.from([1, 2, 3]))).toBe("![示例.png](../附件/示例.png)");
    expect(await readFile(join(root, "附件/示例.png"))).toEqual(Buffer.from([1, 2, 3]));
    // A taken name is numbered, never replaced.
    expect(await lib.importAttachment("根.md", "示例.png", Buffer.from([4]))).toBe("![示例 2.png](附件/示例%202.png)");
    expect(await readFile(join(root, "附件/示例.png"))).toEqual(Buffer.from([1, 2, 3]));
    // Not an image: a plain link. Characters that would break the link are encoded; brackets leave the label.
    expect(await lib.importAttachment("根.md", "报告 [终稿](1).pdf", Buffer.from("pdf"))).toBe("[报告 终稿(1).pdf](附件/报告%20%5B终稿%5D%281%29.pdf)");
    await expect(lib.importAttachment("根.md", "a:b.png", Buffer.from([0]))).rejects.toThrow("名称不能为空");
    // What the links say is what following them finds.
    expect(await lib.followLink("日记/今天.md", { target: "../附件/示例.png", wiki: false })).toEqual({ kind: "file", path: "附件/示例.png" });
    expect(await lib.followLink("根.md", { target: "附件/示例%202.png", wiki: false })).toEqual({ kind: "file", path: "附件/示例 2.png" });
  });

  it("keeps an imported image's link working when its note moves, and a link to the note too", async () => {
    // As the old WorkspaceTests.testImportAndMovePreservesImageReferenceAndBacklink.
    const root = await library({ "图片笔记.md": "", "入口.md": "见 [[图片笔记]]" });
    const lib = await openLibrary(root);
    const snippet = await lib.importAttachment("图片笔记.md", "示例.png", Buffer.from([1, 2, 3]));
    await lib.saveNote("图片笔记.md", `# 图片笔记\n${snippet}`, "");
    await lib.createFolder("", "归档");

    const moved = await lib.move("图片笔记.md", "归档");
    expect(moved.path).toBe("归档/图片笔记.md");
    expect(await lib.readNote("归档/图片笔记.md")).toBe("# 图片笔记\n![示例.png](../附件/示例.png)");
    expect(await lib.followLink("归档/图片笔记.md", { target: "../附件/示例.png", wiki: false })).toEqual({ kind: "file", path: "附件/示例.png" });
    expect(await lib.readNote("入口.md")).toBe("见 [[归档/图片笔记]]");
    expect(await lib.followLink("入口.md", { target: "归档/图片笔记", wiki: true })).toEqual({ kind: "note", path: "归档/图片笔记.md" });
  });
});
