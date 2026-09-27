import XCTest
@testable import TwainCore

final class RPCTests: XCTestCase {
    func testRequestRoundTrip() throws {
        let req = RPCRequest(id: 7, method: "search", params: ["query": "同步", "limit": 5],
                             caller: RPCCaller(session: "S1", pid: 42, vault: "/v"))
        var buf = req.line()
        buf.append(Data(#"{"jsonrpc":"2.0","id":8,"method":"context"}"#.utf8))
        let lines = RPC.drainLines(&buf)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(String(decoding: buf, as: UTF8.self), #"{"jsonrpc":"2.0","id":8,"method":"context"}"#)
        let back = try JSONDecoder().decode(RPCRequest.self, from: lines[0])
        XCTAssertEqual(back, req)
        XCTAssertEqual(back.params["limit"]?.int, 5)
        buf.append(0x0A)
        let second = try JSONDecoder().decode(RPCRequest.self, from: RPC.drainLines(&buf)[0])
        XCTAssertEqual(second.params, [:])
        XCTAssertNil(second.caller)
    }

    func testResponseKeepsNullResult() throws {
        let ok = RPCResponse(id: 1, result: .null)
        let text = String(decoding: ok.line(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""result":null"#))
        let back = try JSONDecoder().decode(RPCResponse.self, from: ok.line())
        XCTAssertEqual(back.result, .null)
        XCTAssertNil(back.error)

        let err = RPCResponse(id: 2, error: RPCError(RPCError.notFound, "找不到"))
        let e = try JSONDecoder().decode(RPCResponse.self, from: err.line())
        XCTAssertNil(e.result)
        XCTAssertEqual(e.error?.code, 1004)
    }

    func testJSONNumbersStayIntegers() {
        let v: JSONValue = ["line": 3, "ratio": .number(0.5)]
        XCTAssertEqual(v.text(), #"{"line":3,"ratio":0.5}"#)
    }
}

final class CommandSpecTests: XCTestCase {
    func testParsePositionalAndFlags() throws {
        let p = try TwainCommands.search.parse(["同步", "引擎", "--limit", "5"])
        XCTAssertEqual(p["query"], "同步 引擎")
        XCTAssertEqual(p["limit"]?.int, 5)

        let o = try TwainCommands.open.parse(["--line=3", "收件箱"])
        XCTAssertEqual(o["note"], "收件箱")
        XCTAssertEqual(o["line"]?.int, 3)

        let t = try TwainCommands.tasks.parse(["--done", "--tag", "#工作"])
        XCTAssertEqual(t["done"], true)
        XCTAssertEqual(t["tag"], "#工作")
        XCTAssertEqual(try TwainCommands.tasks.parse(["--done=false"])["done"], false)
    }

    func testParseErrors() {
        XCTAssertThrowsError(try TwainCommands.search.parse(["x", "--limit", "many"]))
        XCTAssertThrowsError(try TwainCommands.search.parse(["x", "--limit"]))
        XCTAssertThrowsError(try TwainCommands.context.parse(["多余"]))
    }

    func testUnknownFlagsPassThrough() throws {
        XCTAssertEqual(try TwainCommands.context.parse(["--mode", "full"])["mode"], "full")
    }

    func testValidate() {
        XCTAssertThrowsError(try TwainCommands.open.validate([:]))
        XCTAssertThrowsError(try TwainCommands.open.validate(["note": 3]))
        XCTAssertNoThrow(try TwainCommands.open.validate(["note": "a", "line": 2]))
    }

    func testHelp() {
        XCTAssertEqual(TwainCommands.open.usage, "twain open <note> [--line N] [--heading <heading>]")
        XCTAssertTrue(TwainCommands.open.help.contains("--line"))
    }
}

final class OutlineTests: XCTestCase {
    let text = """
    # 2.0 发布计划
    和 [[同步引擎]]、[[设计评审#结论|评审]] 有关。 #工作 #项目/twain
    ## 里程碑
    - [x] 冻结功能范围
    - [ ] 内测 `#不是标签` [[同步引擎]]
    ```
    # 不是标题
    - [ ] 不是待办 #也不是
    ```
    ### 风险
    - [ ] 性能 见 issue #12 和 a#b
    """

    func testParse() {
        let o = NoteOutline.parse(text)
        XCTAssertEqual(o.headings.map(\.text), ["2.0 发布计划", "里程碑", "风险"])
        XCTAssertEqual(o.headings.map(\.line), [1, 3, 10])
        XCTAssertEqual(o.tasks.map(\.text), ["冻结功能范围", "内测 `#不是标签` [[同步引擎]]", "性能 见 issue #12 和 a#b"])
        XCTAssertEqual(o.tasks.map(\.done), [true, false, false])
        XCTAssertEqual(o.tasks.map(\.heading), ["里程碑", "里程碑", "风险"])
        XCTAssertEqual(o.links.map(\.target), ["同步引擎", "设计评审", "同步引擎"])
        XCTAssertEqual(o.tags, ["工作", "项目/twain"])
    }

    func testHeadingPath() {
        let o = NoteOutline.parse(text)
        XCTAssertEqual(o.headingPath(at: 4), ["2.0 发布计划", "里程碑"])
        XCTAssertEqual(o.headingPath(at: 11), ["2.0 发布计划", "里程碑", "风险"])
        XCTAssertEqual(o.headingPath(at: 2), ["2.0 发布计划"])
    }
}

final class VaultIndexTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("twain-index-\(UUID().uuidString)")
        try write("收件箱.md", "# 收件箱\n- [ ] 读 [[同步引擎]] 的方案\n- [x] 已完成\n")
        try write("项目/同步引擎.md", "# 同步引擎\n## 冲突处理\n用 CRDT 处理冲突。 #工作\n- [ ] 压测\n")
        try write("项目/设计评审.md", "# 设计评审\n结论见 [[同步引擎#冲突处理]] 和 [[项目/同步引擎|引擎]]。\n")
        try write("日记/同步引擎.md", "# 另一篇同名笔记\n")
        try write(".hidden/秘密.md", "不该被索引")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ rel: String, _ text: String) throws {
        let u = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
    }

    func testResolve() {
        let i = VaultIndex(root: root)
        i.refresh()
        XCTAssertEqual(i.paths.count, 4)
        XCTAssertEqual(i.resolve("收件箱"), "收件箱.md")
        XCTAssertEqual(i.resolve("收件箱.md"), "收件箱.md")
        XCTAssertEqual(i.resolve("日记/同步引擎"), "日记/同步引擎.md")
        // Two notes share the title: both are one level deep, so the path order decides.
        XCTAssertEqual(i.resolve("同步引擎"), "日记/同步引擎.md")
        XCTAssertNil(i.resolve("不存在"))
    }

    func testBacklinks() {
        let i = VaultIndex(root: root)
        i.refresh()
        let hits = i.backlinks(to: "项目/同步引擎.md")
        // The explicit path link counts; the bare title resolves to the other note of that name.
        XCTAssertEqual(hits.map(\.rel), ["项目/设计评审.md"])
        XCTAssertEqual(hits.first?.line, 2)
    }

    func testSearchRanksTitleFirst() {
        let i = VaultIndex(root: root)
        i.refresh()
        let hits = i.search("同步引擎")
        XCTAssertEqual(hits.first?.line, nil)
        XCTAssertTrue(hits.contains { $0.rel == "收件箱.md" && $0.line == 2 })
        XCTAssertEqual(i.search("crdt 冲突").map(\.rel), ["项目/同步引擎.md"])
        XCTAssertEqual(i.search("同步", limit: 2).count, 2)
    }

    func testSearchMatchesEditedTextAndSkipsDamagedFiles() throws {
        let i = VaultIndex(root: root)
        // A file of NULs (a broken iCloud download) is indexed empty rather than searched.
        try Data(repeating: 0, count: 4096).write(to: root.appendingPathComponent("坏文件.md"))
        i.refresh()
        XCTAssertEqual(i.notes["坏文件.md"]?.lines, [""])
        XCTAssertTrue(i.search("\u{0}").isEmpty)
        // Unsaved editor text is what search sees, case-insensitively.
        i.update("收件箱.md", text: "# 收件箱\nMixed Case 行\n")
        XCTAssertEqual(i.search("mixed case").map(\.line), [2])
        XCTAssertTrue(VaultIndex.has("abc", ""))
        XCTAssertFalse(VaultIndex.has("ab", "abc"))
        XCTAssertTrue(VaultIndex.has("中文检索", "检索"))
    }

    func testTasksAndRefresh() throws {
        let i = VaultIndex(root: root)
        i.refresh()
        XCTAssertEqual(i.tasks().map(\.task.text), ["读 [[同步引擎]] 的方案", "压测"])
        XCTAssertEqual(i.tasks(includeDone: true).count, 3)
        XCTAssertEqual(i.tasks(tag: "#工作").map(\.rel), ["项目/同步引擎.md"])
        XCTAssertEqual(i.tasks(folder: "项目").count, 1)

        try write("收件箱.md", "# 收件箱\n")
        // Bump the date past the file system's timestamp resolution.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                              ofItemAtPath: root.appendingPathComponent("收件箱.md").path)
        try FileManager.default.removeItem(at: root.appendingPathComponent("日记/同步引擎.md"))
        i.refresh()
        XCTAssertEqual(i.tasks().count, 1)
        XCTAssertEqual(i.resolve("同步引擎"), "项目/同步引擎.md")
    }

    func testQueriesShareOneShape() throws {
        let i = VaultIndex(root: root)
        i.refresh()
        let out = try VaultQueries.run("outline", ["note": "同步引擎"], index: i, current: nil)
        XCTAssertEqual(out["note"], "日记/同步引擎.md")
        let bl = try VaultQueries.run("backlinks", [:], index: i, current: "项目/同步引擎.md")
        XCTAssertEqual(bl["backlinks"]?.array?.count, 1)
        XCTAssertThrowsError(try VaultQueries.run("backlinks", [:], index: i, current: nil))
        XCTAssertThrowsError(try VaultQueries.run("outline", ["note": "不存在"], index: i, current: nil)) {
            XCTAssertEqual(($0 as? RPCError)?.code, RPCError.notFound)
        }
    }

    func testFindVaultRoot() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".twain"), withIntermediateDirectories: true)
        let inner = root.appendingPathComponent("项目")
        XCTAssertEqual(findVaultRoot(from: inner)?.path, root.standardizedFileURL.resolvingSymlinksInPath().path)
    }
}

final class AgentArgumentsTests: XCTestCase {
    func testClaudeMayRunTwain() {
        let a = AgentArguments.build(kind: .claude, prompt: "p", context: "c", root: "/v", resume: "R", model: "opus", effort: "")
        XCTAssertEqual(a, ["-p", "p", "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits",
                           "--allowedTools", "Bash(twain:*)", "--append-system-prompt", "c", "--model", "opus", "--resume", "R"])
    }

    func testCodexReachesOnlyTwainSocket() {
        let sock = "/Users/a/Library/Application Support/Twain/run/twain.sock"
        let v = "codex-cli 0.157.0"
        let a = AgentArguments.build(kind: .codex, prompt: "p", context: "c", root: "/v", resume: nil, socket: sock, version: v)
        XCTAssertEqual(Array(a.prefix(7)), ["exec", "--json", "-s", "workspace-write", "--skip-git-repo-check", "-C", "/v"])
        XCTAssertTrue(a.contains("features.network_proxy.unix_sockets={\"\(sock)\"=\"allow\"}"))
        XCTAssertEqual(a.last, "c\n\np")

        let r = AgentArguments.build(kind: .codex, prompt: "p", context: "c", root: "/v", resume: "T", effort: "high", socket: sock, version: v)
        XCTAssertEqual(Array(r.prefix(3)), ["exec", "resume", "T"])
        XCTAssertTrue(r.contains("sandbox_workspace_write.network_access=true"))
        XCTAssertTrue(r.contains("model_reasoning_effort=\"high\""))

        // Without a socket, Codex keeps its default sandbox untouched.
        let plain = AgentArguments.build(kind: .codex, prompt: "p", context: "c", root: "/v", resume: nil, version: v)
        XCTAssertFalse(plain.contains { $0.contains("network") })
    }

    func testOlderOrUnknownCodexKeepsNetworkClosed() {
        let sock = "/s.sock"
        for version in ["codex-cli 0.150.2", nil, "codex-cli dev"] as [String?] {
            let a = AgentArguments.build(kind: .codex, prompt: "p", context: "c", root: "/v", resume: nil, socket: sock, version: version)
            XCTAssertFalse(a.contains { $0.contains("network") }, "\(version ?? "nil")")
        }
        XCTAssertTrue(AgentArguments.codexProxyWorks("codex-cli 0.160.1"))
        XCTAssertTrue(AgentArguments.codexProxyWorks("codex-cli 1.0.0"))
    }
}

final class EditorContextTests: XCTestCase {
    let text = "# 计划\n## 里程碑\n- [ ] 内测\n正文第二段\n"

    func testCaretOnly() {
        let loc = (text as NSString).range(of: "内测").location
        let c = EditorContext.describe(text: text, selection: NSRange(location: loc, length: 0))
        XCTAssertEqual(c["cursor"], ["line": 3, "column": 7])
        XCTAssertEqual(c["headingPath"], ["计划", "里程碑"])
        XCTAssertEqual(c["selection"], .null)
        XCTAssertEqual(c["lines"]?.int, 5)
    }

    func testSelectionAcrossLines() {
        let r = (text as NSString).range(of: "内测\n正文")
        let c = EditorContext.describe(text: text, selection: r)
        XCTAssertEqual(c["selection"]?["text"], "内测\n正文")
        XCTAssertEqual(c["selection"]?["start"], ["line": 3, "column": 7])
        XCTAssertEqual(c["selection"]?["end"], ["line": 4, "column": 3])
        XCTAssertEqual(c["selection"]?["truncated"], false)
    }

    func testStaleSelectionIsClamped() {
        // The editor switched to a shorter note before the selection caught up.
        let c = EditorContext.describe(text: "短", selection: NSRange(location: 40, length: 10))
        XCTAssertEqual(c["cursor"], ["line": 1, "column": 2])
        XCTAssertEqual(c["selection"], .null)
    }

    func testLongSelectionIsCut() {
        let long = String(repeating: "字", count: EditorContext.selectionLimit + 5)
        let c = EditorContext.describe(text: long, selection: NSRange(location: 0, length: (long as NSString).length))
        XCTAssertEqual(c["selection"]?["text"]?.string?.count, EditorContext.selectionLimit)
        XCTAssertEqual(c["selection"]?["truncated"], true)
    }
}
