import { describe, expect, it } from "vitest";
import { isHidden, noteTitle } from "../../src/shared/paths";

describe("库内路径", () => {
  it("hides dot-folders and dot-files at any depth, and nothing else", () => {
    expect([".notes/空间/健身.html", "健身/.hidden.md", ".git", "日记/周一.md", "", "a.b/c.md"].map(isHidden)).toEqual([true, true, true, false, false, false]);
  });

  it("titles a note by its file name without .md", () => {
    expect(["日记/周一.md", "随记.MD", "读书/书单.md.md", "无扩展名"].map(noteTitle)).toEqual(["周一", "随记", "书单.md", "无扩展名"]);
  });
});
