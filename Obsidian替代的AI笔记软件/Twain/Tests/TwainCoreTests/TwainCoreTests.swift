import XCTest
@testable import TwainCore

final class MarkdownTests: XCTestCase {
    func testBlockTypes() {
        XCTAssertEqual(Markdown.blockType("# 2.0 发布计划"), .h1)
        XCTAssertEqual(Markdown.blockType("## 里程碑"), .h2)
        XCTAssertEqual(Markdown.blockType("### x"), .h3)
        XCTAssertEqual(Markdown.blockType("#### x"), .h4)
        XCTAssertEqual(Markdown.blockType("####### x"), .p)
        XCTAssertEqual(Markdown.blockType("\t- 嵌套"), .li)
        XCTAssertEqual(Markdown.blockType("* 星号"), .li)
        XCTAssertEqual(Markdown.blockType("2) 括号"), .ol)
        XCTAssertEqual(Markdown.blockType("```swift"), .fence)
        XCTAssertEqual(Markdown.blockType("| a | b |"), .table)
        XCTAssertEqual(Markdown.blockType("***"), .hr)
        XCTAssertEqual(Markdown.blockType("-"), .p)
        XCTAssertEqual(Markdown.blockType("- [x] 冻结功能范围"), .task)
        XCTAssertEqual(Markdown.blockType("- [ ] 完成"), .task)
        XCTAssertEqual(Markdown.blockType("- 列表"), .li)
        XCTAssertEqual(Markdown.blockType("12. 第十二"), .ol)
        XCTAssertEqual(Markdown.blockType("> 引用"), .quote)
        XCTAssertEqual(Markdown.blockType("---"), .hr)
        XCTAssertEqual(Markdown.blockType(""), .empty)
        XCTAssertEqual(Markdown.blockType("正文"), .p)
    }

    func testOutline() {
        let text = """
        ---
        title: # not a heading
        ---
        # 周会记录
        正文
        ## 决定 ##
        ```
        # 代码里的井号
        ```
        ### 待办
        """
        let o = Markdown.outline(text)
        XCTAssertEqual(o.map(\.title), ["周会记录", "决定", "待办"])
        XCTAssertEqual(o.map(\.level), [1, 2, 3])
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: NSRange(location: o[1].offset, length: 2)), "##")
        XCTAssertEqual(ns.substring(with: NSRange(location: o[2].offset, length: 3)), "###")
    }

    func testContinuation() {
        XCTAssertEqual(Markdown.continuation(for: "- a")?.prefix, "- ")
        XCTAssertEqual(Markdown.continuation(for: "- [x] done")?.prefix, "- [ ] ")
        XCTAssertEqual(Markdown.continuation(for: "3. c")?.prefix, "4. ")
        XCTAssertEqual(Markdown.continuation(for: "- ")?.exit, true)
        XCTAssertNil(Markdown.continuation(for: "plain"))
        XCTAssertEqual(Markdown.continuation(for: "\t- 嵌套")?.prefix, "\t- ")
        XCTAssertEqual(Markdown.continuation(for: "\t- [x] 做完")?.prefix, "\t- [ ] ")
        XCTAssertEqual(Markdown.continuation(for: "\t- ")?.exit, true)
        XCTAssertEqual(Markdown.continuation(for: "9) 九")?.prefix, "10) ")
    }

    func testContextTypes() {
        let lines = ["---", "title: x", "---", "# 标题", "```swift", "# 不是标题", "- 不是列表", "```", "- 列表", "$$", "a^2", "$$", "正文"]
        XCTAssertEqual(Markdown.types(lines), [.frontmatter, .frontmatter, .frontmatter, .h1, .fence, .code, .code, .fence, .li,
                                                .fence, .code, .fence, .p])
        // A later --- is a rule, not front matter.
        XCTAssertEqual(Markdown.types(["正文", "---"]), [.p, .hr])
        // A shorter or different fence does not close the block.
        XCTAssertEqual(Markdown.types(["````", "```", "~~~", "````"]), [.fence, .code, .code, .fence])
    }

    func testNestedListPrefix() {
        let m = Markdown.parseLine("\t\t- [ ] 深一层")
        XCTAssertEqual(m.type, .task)
        XCTAssertEqual(m.depth, 2)
        XCTAssertEqual(m.prefix, NSRange(location: 0, length: 8))
        XCTAssertEqual(Markdown.toggleTask("\t- [ ] a"), "\t- [x] a")
    }

    func testNewInlineSpans() {
        let line = "~~删掉~~ 和 ==重点== 还有 #标签/子 与 ![[图.png]] 见 https://example.com/a 结束"
        let m = Markdown.parseLine(line)
        let ns = line as NSString
        func text(_ k: InlineSpan.Kind) -> String? { m.spans.first { $0.kind == k }.map { ns.substring(with: $0.content) } }
        XCTAssertEqual(text(.strike), "删掉")
        XCTAssertEqual(text(.highlight), "重点")
        XCTAssertEqual(text(.tag("标签/子")), "#标签/子")
        XCTAssertEqual(text(.embed("图.png")), "图.png")
        XCTAssertEqual(text(.link("https://example.com/a")), "https://example.com/a")
        XCTAssertNil(m.blockEmbed)
        XCTAssertEqual(Markdown.parseLine("![[图.png|300]]").blockEmbed, "图.png|300")
        XCTAssertEqual(Markdown.parseLine("![说明](附件/a.jpg)").blockEmbed, "附件/a.jpg")
        // Headings aren't tags; neither are numbers or anchors in URLs.
        XCTAssertFalse(Markdown.parseLine("# 标题").spans.contains { if case .tag = $0.kind { return true }; return false })
        XCTAssertFalse(Markdown.parseLine("第 #1 名").spans.contains { if case .tag = $0.kind { return true }; return false })
        XCTAssertFalse(Markdown.parseLine("snake_case_name").spans.contains { $0.kind == .italic })
        XCTAssertTrue(Markdown.parseLine("一个 _斜体_ 词").spans.contains { $0.kind == .italic })
    }

    func testCallout() {
        let m = Markdown.parseLine("> [!Warning] 小心")
        XCTAssertEqual(m.callout, "warning")
        XCTAssertEqual(("> [!Warning] 小心" as NSString).substring(with: m.prefix), "> [!Warning] ")
    }

    func testRenamingWikiLinks() {
        let text = "见 [[读书笔记]]、[[读书笔记#第一章|第一章]] 和 [[读书笔记甲]]，还有 [[其他]]"
        let (out, n) = Markdown.renamingWikiLinks(in: text, from: "读书笔记", to: "阅读")
        XCTAssertEqual(out, "见 [[阅读]]、[[阅读#第一章|第一章]] 和 [[读书笔记甲]]，还有 [[其他]]")
        XCTAssertEqual(n, 2)
        XCTAssertEqual(Markdown.renamingWikiLinks(in: "[[Plan]]", from: "plan", to: "Roadmap").text, "[[Roadmap]]")
        XCTAssertEqual(Markdown.renamingWikiLinks(in: "无链接", from: "a", to: "b").count, 0)
    }

    func testTitleHeading() {
        XCTAssertEqual(Markdown.titleHeading("# 读书笔记\n正文"), "读书笔记")
        XCTAssertNil(Markdown.titleHeading("## 二级\n"))
        XCTAssertNil(Markdown.titleHeading("# \n"))
        XCTAssertNil(Markdown.titleHeading("正文"))
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

    func testRewriteAcrossBlankLinesIsOneHunk() {
        let old = ["# 标题", "", "旧段一", "", "旧段二", "", "## 下一节", "保留"]
        let new = ["# 新标题", "", "新段一", "", "新段二", "", "## 下一节", "保留"]
        let hs = LineDiff.hunks(from: old, to: new)
        XCTAssertEqual(hs, [Hunk(start: 0, del: 5, add: ["# 新标题", "", "新段一", "", "新段二"])])
        XCTAssertEqual(LineDiff.apply(hs, to: old, pendingAs: .accepted), new)
        XCTAssertEqual(LineDiff.counts(hs[0], base: old).plus, 3)
        XCTAssertEqual(LineDiff.counts(hs[0], base: old).minus, 3)
        // Blank lines inside the hunk stay context; each paragraph sits next to its original.
        XCTAssertEqual(LineDiff.rows(base: old, hunks: hs).prefix(5), [
            .deleted("# 标题"), .added("# 新标题", changed: [2..<3]),
            .context(""),
            .deleted("旧段一", changed: [0..<1]), .added("新段一", changed: [0..<1]),
        ])
    }

    func testEditsSeparatedByTextStayApart() {
        XCTAssertEqual(LineDiff.hunks(from: ["a", "b", "c", "d"], to: ["A", "b", "C", "d"]).count, 2)
    }

    func testInlineMarksWords() {
        let m = LineDiff.inline("the quick brown fox", "the slow brown fox")
        XCTAssertEqual(m?.old, [4..<9])
        XCTAssertEqual(m?.new, [4..<8])
        XCTAssertEqual(LineDiff.inline("活跃用户 3,200", "活跃用户 3,480")?.new, [7..<10])
        // Nothing in common worth marking.
        XCTAssertNil(LineDiff.inline("完全不同的一句话", "another line entirely"))
    }

    func testUnrelatedLinesAreNotPaired() {
        let rows = LineDiff.rows(base: ["苹果香蕉"], hunks: LineDiff.hunks(from: ["苹果香蕉"], to: ["hello"]))
        XCTAssertEqual(rows, [.deleted("苹果香蕉"), .added("hello"), .bar(hunk: 0)])
    }

    func testFoldsLongUnchangedRuns() {
        let old = (0..<20).map { "line \($0)" }
        var new = old
        new[10] = "changed"
        let hs = LineDiff.hunks(from: old, to: new)
        let rows = LineDiff.rows(base: old, hunks: hs, context: 2)
        XCTAssertEqual(rows.first, .gap(line: 0, count: 8))
        XCTAssertEqual(rows[1...2], [.context("line 8"), .context("line 9")])
        XCTAssertEqual(rows.last, .gap(line: 13, count: 7))
        let open = LineDiff.rows(base: old, hunks: hs, context: 2, expanded: [0])
        XCTAssertEqual(open.first, .context("line 0"))
        // Short runs are never folded.
        XCTAssertFalse(LineDiff.rows(base: ["a", "b", "c"], hunks: LineDiff.hunks(from: ["a", "b", "c"], to: ["a", "b", "C"]), context: 1)
            .contains { if case .gap = $0 { true } else { false } })
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

final class AgentModelTests: XCTestCase {
    func testCodexCacheKeepsListedModelsByPriority() {
        let json = """
        {"models":[
          {"slug":"gpt-6-sol","display_name":"GPT-6-Sol","visibility":"list","priority":2},
          {"slug":"gpt-reserve","display_name":"GPT-Reserve","visibility":"hide","priority":1},
          {"slug":"gpt-6-astra","display_name":"GPT-6-Astra","visibility":"list","priority":1}
        ]}
        """
        let models = CodexModels.parseCache(Data(json.utf8))
        XCTAssertEqual(models.map(\.id), ["gpt-6-astra", "gpt-6-sol"])
        XCTAssertEqual(models.first?.name, "GPT-6-Astra")
        XCTAssertEqual(CodexModels.parseCache(Data("not json".utf8)), [])
    }

    func testCodexConfiguredModel() {
        let toml = """
        model_reasoning_effort = "high"
        model = "gpt-6-sol"

        [profiles.fast]
        model = "gpt-6-luna"
        """
        XCTAssertEqual(CodexModels.configuredModel(toml), "gpt-6-sol")
        XCTAssertEqual(CodexModels.configuredEffort(toml), "high")
        XCTAssertNil(CodexModels.configuredModel("[tui]\nmodel = \"x\""))
    }

    func testCodexCacheReadsReasoningLevels() {
        let json = """
        {"models":[{"slug":"gpt-6-sol","display_name":"GPT-6-Sol","description":"Workhorse","priority":1,
          "default_reasoning_level":"medium",
          "supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"},{"effort":"high"},{"effort":"ultra"}]}]}
        """
        let m = CodexModels.parseCache(Data(json.utf8)).first
        XCTAssertEqual(m?.efforts, ["low", "medium", "high", "ultra"])
        XCTAssertEqual(m?.defaultEffort, "medium")
        XCTAssertEqual(m?.detail, "Workhorse")
    }

    func testClaudeCatalogKeepsFullNamesAndEfforts() {
        let json = """
        {"version":2,"catalog":{"surface":"cc","config":{"id":"cc","models":[
          {"id":"claude-opus-5-5","name":"Opus 5.5","short_name":"Opus","description":"Most capable","section":"main",
           "thinking":{"type":"effort","effort_options":[{"id":"low","name":"Low"},
             {"id":"medium","name":"Medium","badge":{"message":"Default","variant":"neutral"}},{"id":"max","name":"Max"}]}},
          {"id":"claude-haiku-4-5-20251001","name":"Haiku 4.5","short_name":"Haiku","section":"main","thinking":{"type":"none"}},
          {"id":"claude-opus-5","name":"Opus 5","short_name":"Opus","section":"overflow",
           "thinking":{"type":"effort","effort_options":[{"id":"high","name":"High"}]}}
        ]}}}
        """
        let models = ClaudeModels.parseCatalog(Data(json.utf8))
        XCTAssertEqual(models.map(\.name), ["Opus 5.5", "Haiku 4.5", "Opus 5"])
        XCTAssertEqual(models[0].efforts, ["low", "medium", "max"])
        XCTAssertEqual(models[0].defaultEffort, "medium")
        XCTAssertEqual(models[1].efforts, [])
        XCTAssertFalse(models[2].primary)
        // `--model opus` is the newest primary Opus; exact ids still win.
        XCTAssertEqual(models.find("opus")?.id, "claude-opus-5-5")
        XCTAssertEqual(models.find("claude-opus-5")?.name, "Opus 5")
        XCTAssertNil(models.find("gpt-6"))
        XCTAssertEqual(ClaudeModels.parseCatalog(Data("[]".utf8)), [])
    }

    func testClaudeSettingsDefaults() {
        let conf = ClaudeModels.configured(Data(#"{"model":"opus","effortLevel":"high","theme":"dark"}"#.utf8))
        XCTAssertEqual(conf.model, "opus")
        XCTAssertEqual(conf.effort, "high")
        XCTAssertNil(ClaudeModels.configured(Data("{}".utf8)).model)
    }

    func testVersionComparison() {
        XCTAssertTrue(versionIsOlder("codex-cli 0.148.0", than: "0.155.0"))
        XCTAssertFalse(versionIsOlder("codex-cli 0.155.0", than: "0.155.0"))
        XCTAssertFalse(versionIsOlder("2.1.282 (Claude Code)", than: "2.1.9"))
        XCTAssertFalse(versionIsOlder("unknown", than: "0.1.0"))
    }

    func testEffortClampsToNearestOfferedLevel() {
        XCTAssertEqual(Effort.clamp("high", to: ["low", "medium", "high"]), "high")
        XCTAssertEqual(Effort.clamp("xhigh", to: ["low", "medium", "high", "max"]), "high")
        XCTAssertEqual(Effort.clamp("ultra", to: ["low", "max"]), "max")
        XCTAssertNil(Effort.clamp("high", to: []))
        XCTAssertEqual(Effort.name("xhigh"), "超高")
    }
}

final class FolderLinkTests: XCTestCase {
    func testMovingWikiLinks() {
        let (out, n) = Markdown.movingWikiLinks(in: "见 [[项目/同步]] 和 [[项目/子/a|别名]]，[[项目甲/x]] 不变", from: "项目", to: "工作")
        XCTAssertEqual(out, "见 [[工作/同步]] 和 [[工作/子/a|别名]]，[[项目甲/x]] 不变")
        XCTAssertEqual(n, 2)
    }
}
