import XCTest
@testable import NotesCore

/// The lb request handler: one JSON request from a space homepage in, one JSON result out, checked against the library on disk.
final class SpaceAPITests: XCTestCase {
    var root: URL!
    /// 2026-10-18 (Sunday, ISO week 42) at noon, local time.
    let today: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 18; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("健身/训练记录.md", """
        # 训练记录

        ## 卧推
        | 日期 | 动作 | 重量 | 组数 |
        |---|---|---|---|
        | 2026-10-12 | 卧推 | 55 | 5 |
        | 2026-10-14 | 卧推 | 57.5 |  |
        | 2026-10-16 | 卧推 | 60 | 5 |

        ## 深蹲
        | 日期 | 重量 |
        |---|---|
        | 2026-10-15 | 80 |
        """)
        try write("日记/2026-10.md", "| 日期 | 心情 |\n|---|---|\n| 2026-10-18 | 好 |\n")
        try write("别处/秘密.md", "不在范围内")
        _ = try SpaceLibrary(root: root).create(name: "健身", icon: "🏋️", scope: .folders(["健身", "日记"]))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func read(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

    func api(_ space: String = "健身", log: OperationLog? = nil) -> SpaceAPI {
        SpaceAPI(root: root, space: space, log: log, now: { [today] in today })
    }

    struct Reply { var ok: Bool; var result: Any?; var code: String?; var message: String? }

    func call(_ api: SpaceAPI, _ method: String, _ args: Any...) -> Reply {
        let request = try! JSONSerialization.data(withJSONObject: ["method": method, "args": args])
        let object = try! JSONSerialization.jsonObject(with: api.handle(request)) as! [String: Any]
        let error = object["error"] as? [String: Any]
        return Reply(ok: object["ok"] as? Bool ?? false, result: object["result"], code: error?["code"] as? String, message: error?["message"] as? String)
    }

    func records(_ reply: Reply) -> [[String: Any]] { (reply.result as? [String: Any])?["records"] as? [[String: Any]] ?? [] }

    func testQueryReturnsTypedRecordsFromTheTableUnderAHeading() {
        let reply = call(api(), "query", "健身/训练记录.md#卧推")
        XCTAssertTrue(reply.ok, reply.message ?? "")
        let rows = records(reply)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1]["日期"] as? String, "2026-10-14")
        XCTAssertEqual(rows[1]["重量"] as? Double, 57.5)
        XCTAssertTrue(rows[1]["组数"] is NSNull, "Empty cells are null")
        XCTAssertEqual(rows[2]["_row"] as? Int, 2)
        let fields = (reply.result as? [String: Any])?["fields"] as? [[String: String]]
        XCTAssertEqual(fields?.map { $0["name"]! }, ["日期", "动作", "重量", "组数"])
        XCTAssertEqual(fields?.map { $0["type"]! }, ["date", "text", "number", "number"])
    }

    func testQueryWithoutHeadingUsesFirstTableAndSupportsFilterSortLimit() {
        XCTAssertEqual(records(call(api(), "query", "健身/训练记录.md")).count, 3, "First table is 卧推")
        XCTAssertEqual(records(call(api(), "query", "健身/训练记录.md#深蹲")).first?["重量"] as? Double, 80)
        let sorted = records(call(api(), "query", "健身/训练记录.md#卧推", ["sort": "-日期", "limit": 2]))
        XCTAssertEqual(sorted.map { $0["日期"] as? String }, ["2026-10-16", "2026-10-14"])
        let filtered = records(call(api(), "query", "健身/训练记录.md#卧推", ["filter": ["重量": 60]]))
        XCTAssertEqual(filtered.map { $0["日期"] as? String }, ["2026-10-16"])
        let missing = call(api(), "query", "健身/没有这篇.md")
        XCTAssertTrue(missing.ok); XCTAssertTrue(records(missing).isEmpty, "A missing record table reads as empty")
    }

    func testPlaceholdersExpandToToday() {
        try! write("日记/2026-10-18.md", "| 日期 | 事 |\n|---|---|\n| {今天} | 跑步 |\n")
        XCTAssertEqual(records(call(api(), "query", "日记/{今天}.md")).count, 1)
        XCTAssertEqual(records(call(api(), "query", "日记/{月}.md")).first?["心情"] as? String, "好")
        XCTAssertEqual(Placeholders.expand("{年}/{月}/{周}/{今天}", now: today), "2026/2026-10/2026-W42/2026-10-18")
    }

    func testScopeNotesReadAndTables() {
        XCTAssertEqual(call(api(), "scope").result as? [String: AnyHashable], ["library": false, "folders": ["健身", "日记"]])
        let notes = call(api(), "notes").result as? [[String: Any]]
        XCTAssertEqual(Set(notes?.compactMap { $0["path"] as? String } ?? []), ["健身/训练记录.md", "日记/2026-10.md"])
        XCTAssertEqual((call(api(), "notes", "日记").result as? [[String: Any]])?.count, 1)
        XCTAssertEqual(call(api(), "read", "日记/2026-10.md").result as? String, "| 日期 | 心情 |\n|---|---|\n| 2026-10-18 | 好 |\n")
        let tables = call(api(), "tables").result as? [[String: Any]]
        XCTAssertEqual(tables?.compactMap { $0["source"] as? String }, ["健身/训练记录.md#卧推", "健身/训练记录.md#深蹲", "日记/2026-10.md"])
    }

    func testPathsOutsideTheScopeAreRefused() throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("健身/捷径.md"), withDestinationURL: root.appendingPathComponent("别处/秘密.md"))
        for path in ["别处/秘密.md", "健身/../别处/秘密.md", "../外面.md", "/etc/passwd", "健身/捷径.md", ".留白/空间/编写说明.md", "健身/.隐藏.md", ".留白/空间/健身.html"] {
            let reply = call(api(), "read", path)
            XCTAssertFalse(reply.ok, path)
            XCTAssertEqual(reply.code, "outside-scope", path)
        }
        XCTAssertEqual(call(api(), "query", "别处/秘密.md").code, "outside-scope")
        XCTAssertEqual(call(api(), "notes", "别处").code, "outside-scope")
        XCTAssertEqual(call(api(), "nonsense").code, "invalid")
    }

    func testWholeLibraryScopeStillRefusesTheAppDirectory() throws {
        _ = try SpaceLibrary(root: root).create(name: "全局", icon: "🌍", scope: .library)
        XCTAssertTrue(call(api("全局"), "read", "别处/秘密.md").ok)
        XCTAssertEqual(call(api("全局"), "read", ".留白/空间/健身.html").code, "outside-scope")
    }

    func testPageReadsTheSpaceFileItself() {
        let page = call(api(), "page").result as? String
        XCTAssertTrue(page?.contains("lb-scope") == true)
    }
}
