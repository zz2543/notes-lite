import { describe, expect, it } from "vitest";
import { codeTokens } from "../../src/shared/codeHighlight";
import {
  blockType,
  displayMath,
  fenceInfo,
  isFence,
  isTableSeparator,
  literalBlocks,
  parseLine,
  parseTable,
  renderedBlocks,
  type Range,
} from "../../src/shared/markdown";

const text = (line: string, r: Range) => line.slice(r.from, r.to);

/** A line's markup as text: its type, block prefix and spans with their visible content and syntax marks. */
function markup(line: string) {
  const m = parseLine(line);
  return {
    type: m.type,
    prefix: text(line, m.prefix),
    depth: m.depth,
    spans: m.spans.map((s) => [s.kind, text(line, s.content), s.marks.map((r) => text(line, r))]),
  };
}

// Ported from the old NotesCoreTests RenderSyntaxTests: syntax the editor shows as more than plain text.
describe("渲染语法", () => {
  it("reads a fence's language from its info string", () => {
    expect(fenceInfo("```mermaid")).toBe("mermaid");
    expect(fenceInfo('~~~ Python title="a.py"')).toBe("python");
    expect(fenceInfo("```{r}")).toBe("r");
    expect(fenceInfo("```")).toBe("");
    expect(fenceInfo("not a fence")).toBe("");
  });

  it("finds the blocks whose lines are literal: fenced code, $$ math and front matter", () => {
    const lines = ["---", "title: 雨", "---", "", "```js", "const a = 1", "```", "$$", "x_1", "$$", "````", "```", "````", "~~~", "never closed"];
    expect(literalBlocks(lines)).toEqual([
      { kind: "frontmatter", first: 0, last: 2, closed: true, language: "" },
      { kind: "code", first: 4, last: 6, closed: true, language: "js" },
      { kind: "math", first: 7, last: 9, closed: true, language: "" },
      // A shorter fence inside does not close a longer one.
      { kind: "code", first: 10, last: 12, closed: true, language: "" },
      { kind: "code", first: 13, last: 14, closed: false, language: "" },
    ]);
    // Front matter only opens on the first line; a closing fence carries no info string.
    expect(literalBlocks(["正文", "---", "```", "```js", "```"])).toEqual([{ kind: "code", first: 2, last: 4, closed: true, language: "" }]);
  });

  it("splits block markers from the text they mark: headings, quotes, lists and tasks", () => {
    expect(markup("## 雨后 **散步**")).toEqual({ type: "h2", prefix: "## ", depth: 0, spans: [["bold", "散步", ["**", "**"]]] });
    expect(markup("> > 引用里的 `code`")).toEqual({ type: "quote", prefix: "> > ", depth: 1, spans: [["code", "code", ["`", "`"]]] });
    expect(markup("\t- [x] 完成")).toMatchObject({ type: "task", prefix: "\t- [x] ", depth: 1 });
    // Two spaces make one level, so a four-space indent reads as two.
    expect(markup("    12) 第十二")).toMatchObject({ type: "ol", prefix: "    12) ", depth: 2 });
    expect(markup("* 星号")).toMatchObject({ type: "li", prefix: "* " });
    expect(markup("#没有空格不是标题")).toMatchObject({ type: "p", prefix: "" });
  });

  it("finds bold, italic and inline code, but no emphasis inside code or words", () => {
    expect(markup("*斜体*与 _下划线_ 和__粗__").spans).toEqual([
      ["bold", "粗", ["__", "__"]],
      ["italic", "斜体", ["*", "*"]],
      ["italic", "下划线", ["_", "_"]],
    ]);
    expect(markup("`**不是粗体**`").spans).toEqual([["code", "**不是粗体**", ["`", "`"]]]);
    expect(markup("snake_case_name 和 2 * 3 * 4").spans).toEqual([]);
  });

  it("reads inline math, whose underscores are not emphasis", () => {
    const line = "传输延时：$=L/R$，其中 $d_{proc}$ 是处理延时";
    const spans = parseLine(line).spans;
    expect(spans.map((s) => [s.kind, s.value, text(line, s.content)])).toEqual([
      ["math", "=L/R", "=L/R"],
      ["math", "d_{proc}", "d_{proc}"],
    ]);
    expect(spans[0]!.marks.map((r) => text(line, r))).toEqual(["$", "$"]);
  });

  it("leaves dollars that are not math alone", () => {
    const math = (line: string) => parseLine(line).spans.filter((s) => s.kind === "math").map((s) => s.value);
    expect(math("It costs $5 and $6 today")).toEqual([]);
    expect(math("a $ b $ c")).toEqual([]);
    expect(math("`$x$` in code")).toEqual([]);
    expect(math("单字母$x$也算")).toEqual(["x"]);
  });

  it("reads a one-line $$ formula, and nothing else as one", () => {
    expect(displayMath("$$d_{nodal} = d_{proc}$$")).toBe("d_{nodal} = d_{proc}");
    expect(displayMath("  $$ x $$ ")).toBe(" x ");
    expect(displayMath("   $$x$$")).toBe("x");
    expect(displayMath("    $$x$$")).toBeNull(); // four spaces in: code, as in the old editor
    expect(displayMath("$$")).toBeNull();
    expect(displayMath("$$ $$")).toBeNull();
    expect(displayMath("$$a$$ and $$b$$")).toBeNull();
  });

  it("reads a pipe table: header, alignments and rows, with pipes in code, links and escapes kept", () => {
    const lines = ["| 名称 | 数量 | 说明 |", "| :--- | ---: | :-: |", "| `a|b` | 3 | [[页|别名]] |", "| x \\| y | 4 |"];
    const t = parseTable(lines)!;
    expect(t.header.map((c) => c.text)).toEqual(["名称", "数量", "说明"]);
    expect(t.aligns).toEqual(["left", "right", "center"]);
    expect(t.rows[0]!.map((c) => c.text)).toEqual(["`a|b`", "3", "[[页|别名]]"]);
    expect(t.rows[1]!.map((c) => c.text)).toEqual(["x | y", "4", ""]);
    // Ranges point at the trimmed cell in its own line.
    expect(text(lines[0]!, t.header[1]!.range!)).toBe("数量");
    expect(t.rows[1]![2]!.range).toBeNull();
    expect(parseTable(["| a | b |", "| c | d |"])).toBeNull();
    expect(isTableSeparator("|---|---|")).toBe(true);
    expect(isTableSeparator("| :-- | --: |")).toBe(true);
    expect(isTableSeparator("| a | - |")).toBe(false);
    expect(isTableSeparator("| | |")).toBe(false);
  });

  it("reads a table whose rows don't end with a pipe", () => {
    expect(parseTable(["| a | b", "|---|---", "| 1 | 2"])!.rows[0]!.map((c) => c.text)).toEqual(["1", "2"]);
  });

  it("gives every row the table's columns: short rows are padded, cells past the last column left out", () => {
    const t = parseTable(["| a | b |", "|---|---|", "| 1 |", "| 1 | 2 | 3 |"])!;
    expect(t.rows.map((row) => row.map((c) => c.text))).toEqual([["1", ""], ["1", "2"]]);
  });

  it("finds the blocks drawn as a whole: tables and formulas, but not inside code", () => {
    const lines = [
      "| a | b |", "|---|---|", "| 1 | 2 |", "", // a table
      "| not | a table |", "| no | separator |", "",
      "$$", "x^2", "$$", // a math block
      "$$e = mc^2$$", // a one-line formula
      "```", "| a | b |", "|---|---|", "$$y$$", "```",
      "$$", "never closed",
      "| a | b |", "|---|---|", // inside the unclosed formula: its TeX, not a table
    ];
    expect(renderedBlocks(lines)).toEqual([
      { kind: "table", first: 0, last: 2, tex: "" },
      { kind: "math", first: 7, last: 9, tex: "x^2" },
      { kind: "math", first: 10, last: 10, tex: "e = mc^2" },
    ]);
    // Read a line at a time, as the editor hands them over, it finds the same.
    expect(renderedBlocks({ length: lines.length, line: (i) => lines[i]! })).toEqual(renderedBlocks(lines));
  });

  it("reads footnote references and definitions", () => {
    const line = "正文里的引用[^1]和[^note]。";
    expect(parseLine(line).spans.map((s) => [s.kind, s.value, text(line, s.content)])).toEqual([
      ["footnote", "1", "1"],
      ["footnote", "note", "note"],
    ]);
    const definition = "[^1]: 出处在这里 **粗**";
    const m = parseLine(definition);
    expect(m.footnoteLabel).toBe("1");
    expect(text(definition, m.prefix)).toBe("[^1]: ");
    expect(m.spans.map((s) => s.kind)).toEqual(["bold"]);
  });

  it("reads whether a callout starts folded", () => {
    expect(parseLine("> [!tip]- 收起的").calloutFolded).toBe(true);
    expect(parseLine("> [!tip]+ 展开的").calloutFolded).toBe(false);
    expect(parseLine("> [!tip] 普通").calloutFolded).toBeUndefined();
    const m = parseLine("> [!faq]-");
    expect(m.callout).toBe("faq");
    expect(m.prefix.to).toBe("> [!faq]-".length);
  });

  it("keeps plain lines fast without losing what they are", () => {
    expect(parseLine("只是一段普通的中文，没有任何标记").spans).toEqual([]);
    expect(blockType("  - 缩进列表")).toBe("li");
    expect(blockType("- - -")).toBe("hr");
    expect(blockType("___")).toBe("hr");
    expect(isFence("  x```")).toBeNull();
  });

  it("reads links, images, embeds and tags, and keeps emphasis out of them", () => {
    const line = "见 [[读书笔记|别名]]、![[图.png]]、![图](a.png)、[官网](https://x.org/a_b_c) 和 https://y.org #标签/子";
    expect(parseLine(line).spans.map((s) => [s.kind, s.value, text(line, s.content)])).toEqual([
      ["embed", "图.png", "图.png"],
      ["image", "a.png", "图"],
      ["wikilink", "读书笔记|别名", "读书笔记|别名"],
      ["link", "https://x.org/a_b_c", "官网"],
      ["link", "https://y.org", "https://y.org"],
      ["tag", "标签/子", "#标签/子"],
    ]);
  });

  it("colours code by language, a line at a time", () => {
    const kinds = (line: string, language: string) =>
      Object.fromEntries(codeTokens(line, language).map((t) => [line.slice(t.from, t.to), t.token]));
    const swift = kinds('let name = "共笔" // 注释', "swift");
    expect(swift["let"]).toBe("keyword");
    expect(swift['"共笔"']).toBe("string");
    expect(swift["// 注释"]).toBe("comment");
    const py = kinds("def f(x): return x * 2  # double", "python");
    expect(py["def"]).toBe("keyword");
    expect(py["2"]).toBe("number");
    expect(py["# double"]).toBe("comment");
    expect(kinds("SELECT id FROM t WHERE a = 1 -- x", "sql")["SELECT"]).toBe("keyword");
    expect(kinds(" * a doc comment", "java")["* a doc comment"]).toBe("comment");
    expect(kinds('<a href="x">', "html")["a"]).toBe("tag");
    expect(kinds('<a href="x">', "html")["href"]).toBe("attribute");
    expect(codeTokens("graph TD", "mermaid")).toEqual([]);
    expect(codeTokens("anything", "text")).toEqual([]);
    // Strings hide what looks like comments inside them.
    expect(kinds('url = "http://x"', "js")['"http://x"']).toBe("string");
  });
});
