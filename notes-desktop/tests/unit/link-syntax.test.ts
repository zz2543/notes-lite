import { describe, expect, it } from "vitest";
import { embeddedImage, isAddress, linkOf, linkPath, parseLine, pastedName, renderedBlocks, shownSpan, snippetInsertion } from "../../src/shared/markdown";

// Ticket 13: links and images as the editor reads them; where imported files go in the text.

const spanOf = (line: string) => parseLine(line).spans[0]!;
const shown = (line: string) => {
  const { content } = shownSpan(spanOf(line));
  return line.slice(content.from, content.to);
};

describe("链接", () => {
  it("leads where it was written: a wiki link by title, a Markdown link by its destination alone", () => {
    expect(linkOf(spanOf("见 [[阅读/摘记#章节|别名]]"))).toEqual({ target: "阅读/摘记#章节|别名", wiki: true });
    expect(linkOf(spanOf("见 ![[图.png]]"))).toEqual({ target: "图.png", wiki: true });
    expect(linkOf(spanOf('见 [报告](附件/报告%201.pdf "终稿")'))).toEqual({ target: "附件/报告%201.pdf", wiki: false });
    expect(linkOf(spanOf("见 [报告](<附件/报告 1.pdf>)"))).toEqual({ target: "附件/报告 1.pdf", wiki: false });
    expect(linkOf(spanOf("![图](../附件/图.png)"))).toEqual({ target: "../附件/图.png", wiki: false });
    expect(linkOf(spanOf("看 https://example.com/页"))).toEqual({ target: "https://example.com/页", wiki: false });
    expect(linkOf(spanOf("**粗**"))).toBeNull();
  });

  it("shows a wiki link's alias in place of its target, and everything else as before", () => {
    expect(shown("[[阅读/摘记|别名]]")).toBe("别名");
    expect(shown("[[阅读/摘记]]")).toBe("阅读/摘记");
    expect(shown("[报告](a.pdf)")).toBe("报告");
    const { marks } = shownSpan(spanOf("[[页|别名]]"));
    expect(marks.map((m) => "[[页|别名]]".slice(m.from, m.to))).toEqual(["[[", "]]", "页|"]);
  });
});

describe("图片", () => {
  it("is drawn when it stands alone on its line, from the library only", () => {
    expect(embeddedImage("![示例.png](../附件/示例%202.png)")).toEqual({ target: "../附件/示例%202.png", wiki: false });
    expect(embeddedImage("  ![[图.PNG|300]] ")).toEqual({ target: "图.PNG|300", wiki: true });
    expect(embeddedImage("看 ![图](a.png)")).toBeNull();
    expect(embeddedImage("![图](a.png) ![图](b.png)")).toBeNull();
    expect(embeddedImage("![报告](a.pdf)")).toBeNull();
    expect(embeddedImage("![[另一篇笔记]]")).toBeNull();
    expect(embeddedImage("![图](https://example.com/a.png)")).toBeNull();
    expect(embeddedImage("- ![图](a.png)")).toBeNull();
  });

  it("is one of the blocks drawn in place, but not inside code", () => {
    const blocks = renderedBlocks(["# 题", "![图](a.png)", "```", "![图](b.png)", "```"]);
    expect(blocks).toEqual([{ kind: "image", first: 1, last: 1, tex: "", image: { target: "a.png", wiki: false } }]);
  });
});

describe("插入附件", () => {
  it("puts each snippet on a line of its own, the caret after the last", () => {
    expect(snippetInsertion("", 0, ["![a.png](a.png)"])).toEqual({ text: "![a.png](a.png)", caret: 15 });
    expect(snippetInsertion("前文", 2, ["[b](b.pdf)"])).toEqual({ text: "\n[b](b.pdf)", caret: 11 });
    expect(snippetInsertion("前后", 1, ["[b](b.pdf)", "[c](c.pdf)"])).toEqual({ text: "\n[b](b.pdf)\n[c](c.pdf)\n", caret: 22 });
    expect(snippetInsertion("后文", 0, ["[b](b.pdf)"])).toEqual({ text: "[b](b.pdf)\n", caret: 10 });
  });

  it("names a pasted picture as the old app did, and keeps a file's own name", () => {
    expect(pastedName("image.png", "image/png", "0a1b2c3d")).toBe("图片-0a1b2c3d.png");
    expect(pastedName("", "image/jpeg", "0a1b2c3d")).toBe("图片-0a1b2c3d.jpg");
    expect(pastedName("报告.pdf", "application/pdf", "0a1b2c3d")).toBe("报告.pdf");
    expect(pastedName("截图 1.png", "image/png", "0a1b2c3d")).toBe("截图 1.png");
  });
});

describe("链接目标", () => {
  it("names the file or note without alias or anchor, and tells addresses from paths", () => {
    expect(linkPath(" 摘记#章节|显示名称 ")).toBe("摘记");
    expect(linkPath("#标题")).toBe("");
    expect(isAddress("https://example.com")).toBe(true);
    expect(isAddress("mailto:a@b.c")).toBe(true);
    expect(isAddress("x:y")).toBe(true);
    expect(isAddress("../附件/图.png")).toBe(false);
    expect(isAddress("阅读/摘记")).toBe(false);
  });
});
