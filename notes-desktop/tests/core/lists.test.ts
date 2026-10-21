import { describe, expect, it } from "vitest";
import { closesListGap, listIndent, listReturn, opensListGap } from "../../src/shared/lists";

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

/** The note `source` after Tab (or Shift-Tab) on lines `first`…`last` (0-based), or null when none is a list item. */
function tab(source: string, first: number, last = first, outward = false): string | null {
  const lines = source.split("\n");
  const moved = listIndent((n) => lines[n]!, lines.length, first, last, outward);
  if (!moved) return null;
  for (const { line, text } of moved) lines[line] = text;
  return lines.join("\n");
}

describe("Tab and Shift-Tab in a list", () => {
  it("nests an item under the one before it, as far in as that item's text starts", () => {
    expect(tab("- 苔藓\n- 蕨", 1)).toBe("- 苔藓\n  - 蕨");
    expect(tab("- [ ] 买伞\n- [x] 带相机", 1)).toBe("- [ ] 买伞\n  - [x] 带相机");
    expect(tab("1. 一\n2. 二", 1)).toBe("1. 一\n   1. 二");
    expect(tab("10. 十\n11. 十一", 1)).toBe("10. 十\n    1. 十一");
  });

  it("numbers a nested ordered item on from the one before it at its new level", () => {
    expect(tab("1. 一\n   1. 甲\n2. 二", 2)).toBe("1. 一\n   1. 甲\n   2. 二");
    expect(tab("1. 一\n2. 二\n3. 三", 1, 2)).toBe("1. 一\n   1. 二\n   2. 三");
  });

  it("brings an item out to its parent's level, numbered on from the parent", () => {
    expect(tab("- 父\n  - 子", 1, 1, true)).toBe("- 父\n- 子");
    expect(tab("1. 一\n   1. 甲", 1, 1, true)).toBe("1. 一\n2. 甲");
    expect(tab("- 父\n  - 子\n    - 孙", 2, 2, true)).toBe("- 父\n  - 子\n  - 孙");
  });

  it("moves an item's nested lines with it", () => {
    expect(tab("- 一\n- 二\n  - 子\n- 三", 1)).toBe("- 一\n  - 二\n    - 子\n- 三");
    expect(tab("- 一\n  - 二\n    - 子", 1, 1, true)).toBe("- 一\n- 二\n  - 子");
  });

  it("leaves the first item at its level and an outermost item where they are", () => {
    expect(tab("- 一\n- 二", 0)).toBe("- 一\n- 二");
    expect(tab("- 一\n- 二", 1, 1, true)).toBe("- 一\n- 二");
  });

  it("is not for lines that are not list items", () => {
    expect(tab("段落\n第二段", 1)).toBeNull();
    expect(tab("- 一\n段落", 1)).toBeNull();
  });
});
