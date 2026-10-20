import { describe, expect, it } from "vitest";
import { closesListGap, listReturn, opensListGap } from "../../src/core/lists";

// Return at the end of a list item, as in the old editor (Markdown.continuation and its parent lookup)
// and the 退出列表 spec. `above` lists the note's lines above the item, nearest first.
describe("Return in a list", () => {
  it("continues a non-empty item with a marker of the same kind and level", () => {
    expect(listReturn("- 苔藓", [])).toEqual({ kind: "continue", prefix: "- " });
    expect(listReturn("  * 蕨", [])).toEqual({ kind: "continue", prefix: "  * " });
    expect(listReturn("\t+ 石", [])).toEqual({ kind: "continue", prefix: "\t+ " });
  });

  it("numbers the next ordered item one on, keeping its delimiter", () => {
    expect(listReturn("1. 第一站", [])).toEqual({ kind: "continue", prefix: "2. " });
    expect(listReturn("   9) 第九站", [])).toEqual({ kind: "continue", prefix: "   10) " });
  });

  it("continues a task, ticked or not, with an open task", () => {
    expect(listReturn("- [x] 买伞", [])).toEqual({ kind: "continue", prefix: "- [ ] " });
    expect(listReturn("  * [ ] 带相机", [])).toEqual({ kind: "continue", prefix: "  * [ ] " });
  });

  it("ends the list on an empty outermost item", () => {
    for (const line of ["- ", "* ", "1. ", "- [ ] ", "- [x]   "]) expect(listReturn(line, ["- 项目"])).toEqual({ kind: "exit" });
  });

  it("steps an empty nested item out one level, taking its parent's marker", () => {
    // Lines above, nearest first.
    expect(listReturn("  - ", ["  - 子", "- 父"])).toEqual({ kind: "outdent", prefix: "- " });
    expect(listReturn("   2. ", ["   1. 子", "2. 父二", "1. 父"])).toEqual({ kind: "outdent", prefix: "3. " });
    expect(listReturn("   - ", ["   - 子", "1) 父"])).toEqual({ kind: "outdent", prefix: "2) " });
    expect(listReturn("  - [ ] ", ["  - [ ] 子", "- [x] 父"])).toEqual({ kind: "outdent", prefix: "- [ ] " });
    expect(listReturn("  2. ", ["  1. 子", "- 父"])).toEqual({ kind: "outdent", prefix: "- " });
    // One level at a time, blank lines between items skipped.
    expect(listReturn("    - ", ["    - 三", "", "  - 二", "- 一"])).toEqual({ kind: "outdent", prefix: "  - " });
  });

  it("ends the list when a nested empty item has no list item to step out to", () => {
    expect(listReturn("  - ", ["  - 子", "段落"])).toEqual({ kind: "exit" });
    expect(listReturn("  - ", ["  - 子"])).toEqual({ kind: "exit" });
    expect(listReturn("  - ", ["  - 子", "- "])).toEqual({ kind: "exit" });
  });

  it("leaves lines that are not list items to an ordinary new line", () => {
    for (const line of ["正文", "-正文", "# 标题", "> 引用", ""]) expect(listReturn(line, [])).toBeNull();
  });
});

// 分隔空行: Markdown ends a list only at a blank line, so text started right below an item needs one.
describe("the blank line that ends a list", () => {
  it("opens when text starts on an empty line right below a list item", () => {
    for (const above of ["- 项目", "1. 项目", "- [ ] 项目", "  - 子"]) expect(opensListGap(above, "", "正")).toBe(true);
    expect(opensListGap("- 项目", "", "zhong")).toBe(true);
    expect(opensListGap("- 项目", "", "-")).toBe(true);
  });

  it("does not open for a new line, on a line with text, or below anything but a list item", () => {
    expect(opensListGap("- 项目", "", "\n")).toBe(false);
    expect(opensListGap("- 项目", "", "")).toBe(false);
    expect(opensListGap("- 项目", "正", "文")).toBe(false);
    for (const above of ["段落", "", "# 标题", "> 引用"]) expect(opensListGap(above, "", "正")).toBe(false);
  });

  it("closes again when the line below it is empty or starts with a complete list marker", () => {
    for (const line of ["", "- ", "* ", "1. ", "2) ", "- [ ] ", "- 新项"]) expect(closesListGap(line)).toBe(true);
    // A dash alone may start a paragraph.
    for (const line of ["-", "1.", "正文", "-正文"]) expect(closesListGap(line)).toBe(false);
  });
});
