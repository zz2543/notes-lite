import { describe, expect, it } from "vitest";
import { countWords } from "../../src/core";

describe("字数", () => {
  it("counts each CJK character and each English word or number, not Markdown markers", () => {
    expect(countWords("# 雨后 walk\n\n- 2026 年 10 月，走了 3.5 km\n> don't stop")).toBe(13);
    expect(countWords("用AI笔记app")).toBe(5);
    expect(countWords("")).toBe(0);
    expect(countWords("---\n\n* * *\n")).toBe(0);
  });
});
