import { describe, expect, it } from "vitest";
import { countWords, noteSummary } from "../../src/core/markdown";

// Ported from the old NotesCore NotePreview: the 详细 list shows prose, not Markdown delimiters,
// headings, code or attachment paths.
describe("摘要", () => {
  it("shows the prose without headings, markers, code or embeds", () => {
    const note = ["---", "tags: 日记", "---", "# 雨后的散步", "", "![[雨.png]]", "- 走过**小路**，看见 `青苔`", "```js", "let x = 1;", "```", "> 空气[很好](https://example.com)"].join("\n");
    expect(noteSummary(note)).toBe("走过小路，看见 青苔 空气很好");
  });

  it("is one short line: about a hundred characters", () => {
    const long = Array.from({ length: 30 }, (_, i) => `第${i}段文字写得很长。`).join("\n\n");
    const summary = noteSummary(long);
    expect(summary.length).toBeLessThanOrEqual(110);
    expect(summary.startsWith("第0段文字写得很长。 第1段文字写得很长。")).toBe(true);
    expect(noteSummary("# 只有标题\n\n---\n")).toBe("");
  });
});

// Ported from the old NotesCore Markdown.countWords: block markers are skipped, each CJK character
// counts once, and a run of ASCII letters or digits counts once ("2.0", "3,200" and "50%" included).
describe("字数", () => {
  it("skips heading, quote and list markers", () => {
    expect(countWords("# 雨后 walk\n\n- 2026 年 10 月，走了 3.5 km\n> don't stop")).toBe(14);
    expect(countWords("1. 第一\n- [x] 完成 3,200 元 50%")).toBe(7);
  });

  it("splits CJK from Latin runs and ignores lines with no words", () => {
    expect(countWords("用AI笔记app")).toBe(5);
    expect(countWords("---\n\n* * *\n")).toBe(0);
    expect(countWords("")).toBe(0);
  });
});
