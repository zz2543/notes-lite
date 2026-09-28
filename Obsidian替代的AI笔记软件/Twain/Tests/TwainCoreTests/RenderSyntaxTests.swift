import XCTest
@testable import TwainCore

/// Syntax the editor renders as more than styled text: math, footnotes, callouts that fold,
/// tables, fence languages and code colouring.
final class RenderSyntaxTests: XCTestCase {
    private func spans(_ line: String) -> [(InlineSpan.Kind, String)] {
        let ns = line as NSString
        return Markdown.parseLine(line).spans.map { ($0.kind, ns.substring(with: $0.content)) }
    }

    func testInlineMath() {
        let line = "传输延时：$=L/R$，其中 $d_{proc}$ 是处理延时"
        let s = spans(line)
        XCTAssertTrue(s.contains { $0.0 == .math("=L/R") && $0.1 == "=L/R" })
        XCTAssertTrue(s.contains { $0.0 == .math("d_{proc}") })
        // Underscores inside TeX are not emphasis.
        XCTAssertFalse(s.contains { $0.0 == .italic })
        let m = Markdown.parseLine(line).spans.first { $0.kind == .math("=L/R") }!
        XCTAssertEqual(m.marks.map { (line as NSString).substring(with: $0) }, ["$", "$"])
    }

    func testDollarsThatAreNotMath() {
        XCTAssertFalse(spans("It costs $5 and $6 today").contains { if case .math = $0.0 { return true }; return false })
        XCTAssertFalse(spans("a $ b $ c").contains { if case .math = $0.0 { return true }; return false })
        XCTAssertFalse(spans("`$x$` in code").contains { if case .math = $0.0 { return true }; return false })
        XCTAssertTrue(spans("单字母$x$也算").contains { $0.0 == .math("x") })
    }

    func testDisplayMathLine() {
        XCTAssertEqual(Markdown.displayMath("$$d_{nodal} = d_{proc}$$"), "d_{nodal} = d_{proc}")
        XCTAssertEqual(Markdown.displayMath("  $$ x $$ "), " x ")
        XCTAssertNil(Markdown.displayMath("$$"))
        XCTAssertNil(Markdown.displayMath("$$ $$"))
        XCTAssertNil(Markdown.displayMath("$$a$$ and $$b$$"))
    }

    func testFootnotes() {
        let s = spans("正文里的引用[^1]和[^note]。")
        XCTAssertTrue(s.contains { $0.0 == .footnote("1") && $0.1 == "1" })
        XCTAssertTrue(s.contains { $0.0 == .footnote("note") })
        let def = Markdown.parseLine("[^1]: 出处在这里 **粗**")
        XCTAssertEqual(def.footnoteLabel, "1")
        XCTAssertEqual(("[^1]: 出处在这里 **粗**" as NSString).substring(with: def.prefix), "[^1]: ")
        XCTAssertTrue(def.spans.contains { $0.kind == .bold })
        XCTAssertFalse(def.spans.contains { if case .footnote = $0.kind { return true }; return false })
    }

    func testCalloutFold() {
        XCTAssertEqual(Markdown.parseLine("> [!tip]- 收起的").calloutFolded, true)
        XCTAssertEqual(Markdown.parseLine("> [!tip]+ 展开的").calloutFolded, false)
        XCTAssertNil(Markdown.parseLine("> [!tip] 普通").calloutFolded)
        let m = Markdown.parseLine("> [!faq]-")
        XCTAssertEqual(m.callout, "faq")
        XCTAssertEqual(m.prefix.length, ("> [!faq]-" as NSString).length)
    }

    func testFenceInfo() {
        XCTAssertEqual(Markdown.fenceInfo("```mermaid"), "mermaid")
        XCTAssertEqual(Markdown.fenceInfo("~~~ Python title=\"a.py\""), "python")
        XCTAssertEqual(Markdown.fenceInfo("```{r}"), "r")
        XCTAssertEqual(Markdown.fenceInfo("```"), "")
        XCTAssertEqual(Markdown.fenceInfo("not a fence"), "")
    }

    func testTable() {
        let lines = ["| 名称 | 数量 | 说明 |", "| :--- | ---: | :-: |", "| `a|b` | 3 | [[页|别名]] |", "| x \\| y | 4 |"]
        let t = MarkdownTable.parse(lines)!
        XCTAssertEqual(t.header.map(\.text), ["名称", "数量", "说明"])
        XCTAssertEqual(t.aligns, [.left, .right, .center])
        XCTAssertEqual(t.rows[0].map(\.text), ["`a|b`", "3", "[[页|别名]]"])
        XCTAssertEqual(t.rows[1].map(\.text), ["x | y", "4", ""])
        // Ranges point at the trimmed cell in its own line.
        XCTAssertEqual((lines[0] as NSString).substring(with: t.header[1].range), "数量")
        XCTAssertNil(MarkdownTable.parse(["| a | b |", "| c | d |"]))
        XCTAssertTrue(MarkdownTable.isSeparator("|---|---|"))
        XCTAssertTrue(MarkdownTable.isSeparator("| :-- | --: |"))
        XCTAssertFalse(MarkdownTable.isSeparator("| a | - |"))
        XCTAssertFalse(MarkdownTable.isSeparator("| | |"))
    }

    func testTableWithoutTrailingPipe() {
        let t = MarkdownTable.parse(["| a | b", "|---|---", "| 1 | 2"])!
        XCTAssertEqual(t.rows[0].map(\.text), ["1", "2"])
    }

    func testHighlight() {
        func kinds(_ line: String, _ lang: String) -> [String: CodeHighlight.Token] {
            let ns = line as NSString
            var out: [String: CodeHighlight.Token] = [:]
            for t in CodeHighlight.tokens(line, language: lang) { out[ns.substring(with: t.range)] = t.token }
            return out
        }
        let swift = kinds("let name = \"共笔\" // 注释", "swift")
        XCTAssertEqual(swift["let"], .keyword)
        XCTAssertEqual(swift["\"共笔\""], .string)
        XCTAssertEqual(swift["// 注释"], .comment)
        let py = kinds("def f(x): return x * 2  # double", "python")
        XCTAssertEqual(py["def"], .keyword)
        XCTAssertEqual(py["2"], .number)
        XCTAssertEqual(py["# double"], .comment)
        XCTAssertEqual(kinds("SELECT id FROM t WHERE a = 1 -- x", "sql")["SELECT"], .keyword)
        XCTAssertEqual(kinds(" * a doc comment", "java")["* a doc comment"], .comment)
        XCTAssertEqual(kinds("<a href=\"x\">", "html")["a"], .tag)
        XCTAssertEqual(kinds("<a href=\"x\">", "html")["href"], .attribute)
        XCTAssertTrue(CodeHighlight.tokens("graph TD", language: "mermaid").isEmpty)
        XCTAssertTrue(CodeHighlight.tokens("anything", language: "text").isEmpty)
        // Strings hide what looks like comments inside them.
        XCTAssertEqual(kinds("url = \"http://x\"", "js")["\"http://x\""], .string)
    }

    func testFastPathsKeepParsing() {
        // Lines without any trigger characters parse to no spans.
        XCTAssertTrue(Markdown.parseLine("只是一段普通的中文，没有任何标记").spans.isEmpty)
        XCTAssertEqual(Markdown.blockType("  - 缩进列表"), .li)
        XCTAssertEqual(Markdown.blockType("- - -"), .hr)
        XCTAssertEqual(Markdown.blockType("___"), .hr)
        XCTAssertNil(Markdown.isFence("  x```"))
    }
}
