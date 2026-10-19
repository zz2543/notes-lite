import { describe, expect, it } from "vitest";
import { countWords } from "../../src/core/markdown";

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
