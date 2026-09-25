import XCTest
@testable import PlumeCore

final class MarkdownTests: XCTestCase {
    func testBlockTypes() {
        XCTAssertEqual(Markdown.blockType("# 2.0 发布计划"), .h1)
        XCTAssertEqual(Markdown.blockType("## 里程碑"), .h2)
        XCTAssertEqual(Markdown.blockType("### x"), .h3)
        XCTAssertEqual(Markdown.blockType("#### x"), .p)
        XCTAssertEqual(Markdown.blockType("- [x] 冻结功能范围"), .task)
        XCTAssertEqual(Markdown.blockType("- [ ] 完成"), .task)
        XCTAssertEqual(Markdown.blockType("- 列表"), .li)
        XCTAssertEqual(Markdown.blockType("12. 第十二"), .ol)
        XCTAssertEqual(Markdown.blockType("> 引用"), .quote)
        XCTAssertEqual(Markdown.blockType("---"), .hr)
        XCTAssertEqual(Markdown.blockType(""), .empty)
        XCTAssertEqual(Markdown.blockType("正文"), .p)
    }

    func testContinuation() {
        XCTAssertEqual(Markdown.continuation(for: "- a")?.prefix, "- ")
        XCTAssertEqual(Markdown.continuation(for: "- [x] done")?.prefix, "- [ ] ")
        XCTAssertEqual(Markdown.continuation(for: "3. c")?.prefix, "4. ")
        XCTAssertEqual(Markdown.continuation(for: "- ")?.exit, true)
        XCTAssertNil(Markdown.continuation(for: "plain"))
    }

    func testToggleTask() {
        XCTAssertEqual(Markdown.toggleTask("- [ ] a"), "- [x] a")
        XCTAssertEqual(Markdown.toggleTask("- [X] a"), "- [ ] a")
    }

    func testInlineSpans() {
        let line = "目标是在 **10 月 20 日** 前验证 [[同步引擎]]，需要在 `M2 Air` 上*复测*。"
        let m = Markdown.parseLine(line)
        let ns = line as NSString
        let kinds = m.spans.map(\.kind)
        XCTAssertTrue(kinds.contains(.bold))
        XCTAssertTrue(kinds.contains(.code))
        XCTAssertTrue(kinds.contains(.italic))
        XCTAssertTrue(kinds.contains(.wikilink("同步引擎")))
        let bold = m.spans.first { $0.kind == .bold }!
        XCTAssertEqual(ns.substring(with: bold.content), "10 月 20 日")
        let code = m.spans.first { $0.kind == .code }!
        XCTAssertEqual(ns.substring(with: code.content), "M2 Air")
        XCTAssertEqual(m.allMarks.count, 8)
    }

    func testItalicInsideCodeIgnored() {
        let m = Markdown.parseLine("`a*b*c` and **x**")
        XCTAssertFalse(m.spans.contains { $0.kind == .italic })
    }

    func testPrefixRange() {
        let m = Markdown.parseLine("- [ ] 内测用户扩大到 500 人")
        XCTAssertEqual(m.prefix, NSRange(location: 0, length: 6))
        XCTAssertEqual(Markdown.parseLine("---").prefix.length, 0)
    }

    func testLinkHidesURL() {
        let line = "看 [官网](https://example.com) 吧"
        let m = Markdown.parseLine(line)
        let link = m.spans.first!
        XCTAssertEqual(link.kind, .link("https://example.com"))
        XCTAssertEqual((line as NSString).substring(with: link.content), "官网")
        XCTAssertEqual(link.marks.map { (line as NSString).substring(with: $0) }, ["[", "](https://example.com)"])
    }

    func testCountWords() {
        XCTAssertEqual(Markdown.countWords(["# 关于专注", "hello world 2.0"]), 4 + 3)
        XCTAssertEqual(Markdown.countWords(["- [ ] **粗体**"]), 2)
    }
}

final class LineDiffTests: XCTestCase {
    func testHunksAndApply() {
        let old = ["# 周报", "## 数据", "活跃用户 3,200", "## 下周", "- 发布 0.9 beta"]
        let new = ["# 周报", "## 数据", "活跃用户 3,480", "## 下周", "- 发布 0.9 beta", "- 跟进留存"]
        var hs = LineDiff.hunks(from: old, to: new)
        XCTAssertEqual(hs, [Hunk(start: 2, del: 1, add: ["活跃用户 3,480"]), Hunk(start: 5, del: 0, add: ["- 跟进留存"])])
        XCTAssertEqual(LineDiff.apply(hs, to: old, pendingAs: .accepted), new)
        XCTAssertEqual(LineDiff.apply(hs, to: old), old)
        hs[1].state = .accepted
        XCTAssertEqual(LineDiff.apply(hs, to: old), old + ["- 跟进留存"])
    }

    func testRows() {
        let old = ["a", "b", "c"]
        var hs = LineDiff.hunks(from: old, to: ["a", "B", "c", "d"])
        XCTAssertEqual(LineDiff.rows(base: old, hunks: hs), [.context("a"), .deleted("b"), .added("B"), .bar(hunk: 0), .context("c"), .added("d"), .bar(hunk: 1)])
        hs[0].state = .rejected
        hs[1].state = .accepted
        XCTAssertEqual(LineDiff.rows(base: old, hunks: hs), [.context("a"), .context("b"), .bar(hunk: 0), .context("c"), .added("d"), .bar(hunk: 1)])
    }

    func testInsertionAtTop() {
        let hs = LineDiff.hunks(from: ["x"], to: ["> 摘要", "x"])
        XCTAssertEqual(hs, [Hunk(start: 0, del: 0, add: ["> 摘要"])])
    }
}

final class AgentEventTests: XCTestCase {
    func fixture(_ name: String) throws -> [[String: Any]] {
        let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")!
        var data = try Data(contentsOf: url)
        data.append(0x0A)
        return JSONLines.drain(&data)
    }

    func testClaudeStream() throws {
        let events = try fixture("claude-stream").flatMap { ClaudeStream.events(from: $0, root: "/vault") }
        XCTAssertEqual(events.first, .session("d9298c2a-5ae7-41de-a351-d597543ffcc7"))
        XCTAssertTrue(events.contains(.step(id: "toolu_01T24ZdW6dHSSqz8F5AxWuTq", text: "读取 note.md", write: nil)))
        XCTAssertTrue(events.contains(.step(id: "toolu_01V5q6R1Kiz2F8jQcTSAYX1z", text: "写入 note.md", write: "/vault/note.md")))
        XCTAssertTrue(events.contains(.stepDone(id: "toolu_01V5q6R1Kiz2F8jQcTSAYX1z")))
        XCTAssertTrue(events.contains(.text("完成。已在 note.md 末尾追加\"再见\"。")))
        XCTAssertEqual(events.last, .finished(isError: false))
    }

    func testCodexStream() throws {
        let events = try fixture("codex-exec").flatMap { CodexStream.events(from: $0, root: "/vault") }
        XCTAssertEqual(events.first, .session("01a0d775-28ba-7aa2-9372-72b3dff00097"))
        XCTAssertTrue(events.contains(.step(id: "item_1", text: "$ cat note2.md", write: nil)))
        XCTAssertTrue(events.contains(.step(id: "item_2", text: "写入 note2.md", write: "/vault/note2.md")))
        XCTAssertTrue(events.contains(.text("已在 note2.md 末尾追加“再见”。")))
        XCTAssertTrue(events.contains(.error("The 'gpt-6-astra' model requires a newer version of Codex. Please upgrade to the latest app or CLI and try again.")))
        XCTAssertEqual(events.last, .finished(isError: true))
    }

    func testClaudeTranscriptUserText() {
        let obj: [String: Any] = ["type": "user", "message": ["role": "user", "content": "把风险那段写清楚"]]
        XCTAssertEqual(ClaudeStream.events(from: obj, root: "/v", transcript: true), [.user("把风险那段写清楚")])
        XCTAssertEqual(ClaudeStream.events(from: obj, root: "/v"), [])
        let meta: [String: Any] = ["type": "user", "message": ["role": "user", "content": "<command-name>/clear</command-name>"]]
        XCTAssertEqual(ClaudeStream.events(from: meta, root: "/v", transcript: true), [])
    }

    func testCodexRolloutPatch() {
        let obj: [String: Any] = ["type": "response_item", "payload": ["type": "custom_tool_call", "name": "apply_patch", "call_id": "c1",
                                                                        "input": "*** Begin Patch\n*** Update File: /vault/项目/周报 W39.md\n@@\n-a\n+b\n*** End Patch"]]
        XCTAssertEqual(CodexRollout.events(from: obj, root: "/vault", index: 0), [.step(id: "c1", text: "写入 项目/周报 W39.md", write: nil), .stepDone(id: "c1")])
    }

    func testDrainKeepsPartialLine() {
        var buf = Data("{\"a\":1}\n{\"b\":".utf8)
        XCTAssertEqual(JSONLines.drain(&buf).count, 1)
        XCTAssertEqual(String(data: buf, encoding: .utf8), "{\"b\":")
    }
}
