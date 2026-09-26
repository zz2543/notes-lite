import XCTest
@testable import PlumeCore

final class ProposalTests: XCTestCase {
    let base = "# 计划\n第一段很长很长。\n\n第二段。\n\n## 风险\n性能未知。"

    func testEditsApplyAndCarryReasons() throws {
        let edits = try ProposalBuilder.edits([
            ["old": "第一段很长很长。", "new": "第一段。", "reason": "精简"],
            ["old": "性能未知。", "new": "性能待压测。"],
        ])
        let (text, anchors) = try ProposalBuilder.apply(edits, to: base)
        XCTAssertEqual(text, "# 计划\n第一段。\n\n第二段。\n\n## 风险\n性能待压测。")
        XCTAssertEqual(anchors.count, 1)
        XCTAssertEqual(anchors[0].0, 1...1)

        let p = Proposal(path: "a.md", baseline: Markdown.lines(base), proposed: Markdown.lines(text),
                         notes: nil)
        XCTAssertEqual(p.hunks.count, 2)
        let notes = ProposalBuilder.notes(hunks: p.hunks, anchors: anchors, lineNotes: [(7, "说清楚下一步")])
        XCTAssertEqual(notes, ["精简", "说清楚下一步"])
    }

    func testEditsMustBeUniqueAndPresent() throws {
        XCTAssertThrowsError(try ProposalBuilder.apply([.init(old: "不存在", new: "x")], to: base)) {
            XCTAssertEqual(($0 as? RPCError)?.code, RPCError.notFound)
        }
        XCTAssertThrowsError(try ProposalBuilder.apply([.init(old: "段", new: "x")], to: base))
        XCTAssertThrowsError(try ProposalBuilder.apply([.init(old: "aa", new: "b")], to: "aaa"))
        XCTAssertThrowsError(try ProposalBuilder.apply([.init(old: "第一段", new: "x"), .init(old: "段很长", new: "y")], to: base))
        XCTAssertThrowsError(try ProposalBuilder.edits(.array([])))
        XCTAssertThrowsError(try ProposalBuilder.edits([["old": "a"]]))
    }

    func testResolveAndFeedback() {
        var p = Proposal(path: "a.md", baseline: ["一", "二", "三", "四", "五"], proposed: ["一", "贰", "三", "四", "伍"])
        XCTAssertEqual(p.hunks.count, 2)
        var decided = p.hunks
        decided[0].state = .accepted
        decided[1].state = .rejected
        p.resolve(decided, feedback: [nil, "保留原来的写法"])
        XCTAssertEqual(p.status, .partial)
        let msg = p.feedbackMessage()!
        XCTAssertTrue(msg.contains("接受 1 处，拒绝 1 处"))
        XCTAssertTrue(msg.contains("第 5 行，原文：“五”，你改成：“伍”。原因：保留原来的写法"))
        XCTAssertEqual(p.resultJSON["hunks"]?.array?[1]["feedback"], "保留原来的写法")

        decided[1].state = .accepted
        p.resolve(decided, feedback: [])
        XCTAssertEqual(p.status, .accepted)
        XCTAssertNil(p.feedbackMessage())
    }

    func testStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-proposals-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProposalStore(vault: root)
        var a = Proposal(id: "20260101-000000-aaaa", path: "a.md", createdAt: Date(timeIntervalSince1970: 1), reason: "r",
                         baseline: ["x"], proposed: ["y"])
        let b = Proposal(id: "20260101-000001-bbbb", path: "b.md", createdAt: Date(timeIntervalSince1970: 2), baseline: [], proposed: ["新"], isNew: true)
        store.save(b)
        var h = a.hunks
        h[0].state = .rejected
        a.resolve(h, feedback: ["不对"], at: Date(timeIntervalSince1970: 100))
        store.save(a)
        XCTAssertEqual(store.all().map(\.id), [a.id, b.id])
        XCTAssertEqual(store.load(a.id), a)
        let reviews = store.recentReviews(limit: 5)["reviews"]?.array ?? []
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews[0]["hunks"]?.array?[0]["feedback"], "不对")
        XCTAssertEqual(reviews[0]["hunks"]?.array?[0]["old"], "x")
    }
}

final class MCPTests: XCTestCase {
    func line(_ s: String) -> Data { Data(s.utf8) }

    func decode(_ d: Data?) -> JSONValue? { d.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } }

    func testHandshakeAndList() {
        let server = MCPServer(version: "t") { _, _ in .success(.null) }
        let r = decode(server.handle(line(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)))
        XCTAssertEqual(r?["result"]?["protocolVersion"], "2025-03-26")
        XCTAssertEqual(r?["result"]?["serverInfo"]?["name"], "plume")
        XCTAssertNil(server.handle(line(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)))

        let list = decode(server.handle(line(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)))
        let tools = list?["result"]?["tools"]?.array ?? []
        XCTAssertLessThanOrEqual(tools.count, 10)
        let names = tools.compactMap { $0["name"]?.string }
        XCTAssertTrue(names.contains("propose_edit"))
        XCTAssertTrue(names.contains("ask_user"))
        let propose = tools.first { $0["name"] == "propose_edit" }!
        XCTAssertEqual(propose["inputSchema"]?["required"], ["note"])
        XCTAssertEqual(propose["inputSchema"]?["properties"]?["edits"]?["type"], "array")
        XCTAssertEqual(propose["inputSchema"]?["properties"]?["wait"]?["type"], "boolean")
    }

    func testCallsForwardAndErrorsStayInBand() {
        var seen: (String, [String: JSONValue])?
        let server = MCPServer(version: "t") { spec, params in
            seen = (spec.id, params)
            return params["query"] == "空" ? .failure(RPCError(RPCError.notFound, "没找到")) : .success(["query": params["query"]!, "results": []])
        }
        let ok = decode(server.handle(line(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"query":"计划"}}}"#)))
        XCTAssertEqual(seen?.0, "search")
        XCTAssertEqual(ok?["result"]?["isError"], false)
        XCTAssertEqual(ok?["result"]?["content"]?.array?.first?["text"], "没有找到“计划”")

        let bad = decode(server.handle(line(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search","arguments":{"query":"空"}}}"#)))
        XCTAssertEqual(bad?["result"]?["isError"], true)

        let invalid = decode(server.handle(line(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"search","arguments":{}}}"#)))
        XCTAssertEqual(invalid?["result"]?["isError"], true)

        let unknown = decode(server.handle(line(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"reveal","arguments":{}}}"#)))
        XCTAssertNotNil(unknown?["error"])
    }
}

final class VaultConfigTests: XCTestCase {
    func testFrontmatter() {
        let (f, body) = Frontmatter.split("---\ntitle: 润色 # 注释\nagent: \"codex\"\n---\n\n正文 {{selection}}\n")
        XCTAssertEqual(f["title"], "润色")
        XCTAssertEqual(f["agent"], "codex")
        XCTAssertEqual(body, "正文 {{selection}}")
        XCTAssertEqual(Frontmatter.split("没有头").body, "没有头")
    }

    func testTemplate() {
        XCTAssertEqual(Template.render("改 {{ selection }}，见 {{path}} {{typo}}", ["selection": "这段", "path": "a.md"]),
                       "改 这段，见 a.md {{typo}}")
        XCTAssertTrue(Template.uses("x {{selection}}", "selection"))
        XCTAssertFalse(Template.uses("x {{note}}", "selection"))
    }

    func testGlob() {
        XCTAssertTrue(Glob.match("收件箱.md", "收件箱.md"))
        XCTAssertTrue(Glob.match("收件箱.md", "项目/收件箱.md"))
        XCTAssertTrue(Glob.match("日记/*.md", "日记/2026-09-26.md"))
        XCTAssertFalse(Glob.match("日记/*.md", "日记/9月/26.md"))
        XCTAssertTrue(Glob.match("日记/**", "日记/9月/26.md"))
        XCTAssertTrue(Glob.match("**/*.md", "a.md"))
        XCTAssertTrue(Glob.match("**/*.md", "x/y/a.md"))
        XCTAssertFalse(Glob.match("*.md", "a.txt"))
        XCTAssertFalse(Glob.match("a.md", "ba.md"))
    }

    func testUserCommand() {
        let c = UserCommand.parse(file: ".plume/commands/polish.md", text: "---\ntitle: 润色选中段落\nagent: claude\n---\n改得简洁：{{selection}}")!
        XCTAssertEqual(c.key, "polish")
        XCTAssertEqual(c.scope, .selection)
        XCTAssertEqual(c.agent, .claude)
        XCTAssertNil(UserCommand.parse(file: "x.md", text: "---\nagent: gpt\n---\nhi"))
        XCTAssertNil(UserCommand.parse(file: "x.md", text: "---\ntitle: 空\n---\n"))
        XCTAssertEqual(UserCommand.parse(file: "sum.md", text: "总结 {{note}}")?.scope, .note)
    }

    func testAutomation() {
        let text = "---\ntitle: 收件箱归类\non: note.saved, note.changed\nmatch: 收件箱.md\ndebounce: 120\n---\n归类 {{path}}"
        let a = Automation.parse(file: ".plume/automations/inbox.md", text: text)!
        XCTAssertEqual(a.id, "inbox")
        XCTAssertEqual(a.on, ["note.saved", "note.changed"])
        XCTAssertEqual(a.debounce, 120)
        XCTAssertTrue(a.triggers(event: "note.saved", path: "收件箱.md"))
        XCTAssertFalse(a.triggers(event: "note.saved", path: "日记.md"))
        XCTAssertFalse(a.triggers(event: "note.opened", path: "收件箱.md"))
        XCTAssertNil(Automation.parse(file: "x.md", text: "---\ntitle: 没有 on\n---\n做点事"))
        let edited = Automation.parse(file: ".plume/automations/inbox.md", text: text + "。")!
        XCTAssertNotEqual(a.fingerprint, edited.fingerprint)
    }
}

final class SpecJSONTests: XCTestCase {
    func testSpecSurvivesJSON() {
        for spec in PlumeCommands.all {
            let back = CommandSpec(json: spec.json)
            XCTAssertEqual(back?.id, spec.id)
            XCTAssertEqual(back?.params.map(\.name), spec.params.map(\.name))
            XCTAssertEqual(back?.params.map(\.positional), spec.params.map(\.positional))
            XCTAssertEqual(back?.mcpName, spec.mcpName)
        }
    }
}

final class MCPLaunchTests: XCTestCase {
    let mcp = AgentArguments.MCP(command: "/Users/a/Library/Application Support/Plume/bin/plume",
                                 env: ["PLUME_SESSION": "S1", "PLUME_SOCK": "/s.sock"])

    func testClaudeMountsPlume() throws {
        let a = AgentArguments.build(kind: .claude, prompt: "p", context: "c", root: "/v", resume: nil, mcp: mcp)
        let allowed = a[a.firstIndex(of: "--allowedTools")! + 1]
        XCTAssertEqual(allowed, "Bash(plume:*),mcp__plume")
        let config = a[a.firstIndex(of: "--mcp-config")! + 1]
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(config.utf8))
        XCTAssertEqual(v["mcpServers"]?["plume"]?["command"]?.string, mcp.command)
        XCTAssertEqual(v["mcpServers"]?["plume"]?["env"]?["PLUME_SESSION"], "S1")
        XCTAssertEqual(a[a.firstIndex(of: "--permission-mode")! + 1], "acceptEdits")
    }

    func testReadOnlyRunsCannotEdit() {
        let c = AgentArguments.build(kind: .claude, prompt: "p", context: "c", root: "/v", resume: nil, mcp: mcp, readOnly: true)
        XCTAssertEqual(c[c.firstIndex(of: "--permission-mode")! + 1], "default")
        let x = AgentArguments.build(kind: .codex, prompt: "p", context: "c", root: "/v", resume: nil,
                                     socket: "/s.sock", version: "codex-cli 0.157.0", mcp: mcp, readOnly: true)
        XCTAssertEqual(x[x.firstIndex(of: "-s")! + 1], "read-only")
        XCTAssertFalse(x.contains { $0.contains("network_access") })
    }

    func testCodexMountsPlume() {
        let x = AgentArguments.build(kind: .codex, prompt: "p", context: "c", root: "/v", resume: nil, mcp: mcp)
        XCTAssertTrue(x.contains(#"mcp_servers.plume.command="/Users/a/Library/Application Support/Plume/bin/plume""#))
        XCTAssertTrue(x.contains(#"mcp_servers.plume.env={PLUME_SESSION="S1",PLUME_SOCK="/s.sock"}"#))
        XCTAssertTrue(x.contains(#"mcp_servers.plume.default_tools_approval_mode="approve""#))
    }
}
