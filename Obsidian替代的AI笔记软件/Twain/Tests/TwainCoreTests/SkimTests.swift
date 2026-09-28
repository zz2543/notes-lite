import XCTest
@testable import TwainCore

final class SkimTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("skim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("项目"), withIntermediateDirectories: true)
        try "---\ntags: [工作, 同步]\nsummary: 同步方案的取舍\n---\n# 同步引擎\n正文".write(to: root.appendingPathComponent("项目/同步引擎.md"), atomically: true, encoding: .utf8)
        let long = "# 读书笔记\n> 引用不算摘要吗？算。\n## 第一章\n这一章讲的是 **专注** 的代价，" + String(repeating: "很长的正文。", count: 60) + "\n## 第二章\n- [ ] 读完\n"
        try long.write(to: root.appendingPathComponent("读书笔记.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCardsPreferFrontmatterThenStoreThenAuto() throws {
        var index = VaultIndex(root: root)
        index.refresh()
        let store = SummaryStore(vault: root)
        let a = Skim.card(index.notes["项目/同步引擎.md"]!, store: store)
        XCTAssertEqual(a.summary, "同步方案的取舍")
        XCTAssertEqual(a.source, "frontmatter")
        XCTAssertEqual(Set(a.tags), ["工作", "同步"])
        let note = index.notes["读书笔记.md"]!
        var b = Skim.card(note, store: store)
        XCTAssertEqual(b.source, "auto")
        XCTAssertTrue(b.summary.hasPrefix("引用不算摘要吗？算。 这一章讲的是 专注 的代价"), b.summary)
        XCTAssertEqual(b.headings, ["第一章", "第二章"])
        XCTAssertTrue(Skim.wantsSummary(note, store: store))
        store.set("读书笔记.md", text: "讨论专注的代价", source: "ai", hash: b.hash)
        b = Skim.card(note, store: SummaryStore(vault: root))
        XCTAssertEqual(b.summary, "讨论专注的代价")
        XCTAssertFalse(Skim.wantsSummary(note, store: store))
        // A stale AI summary is ignored; a user one is kept even when the note changes.
        store.set("读书笔记.md", text: "旧", source: "ai", hash: "stale")
        XCTAssertEqual(Skim.card(note, store: store).source, "auto")
        store.set("读书笔记.md", text: "我写的", source: "user", hash: "stale")
        XCTAssertEqual(Skim.card(note, store: store).summary, "我写的")
    }

    func testReadLevels() throws {
        var index = VaultIndex(root: root)
        index.refresh()
        let outline = try VaultQueries.run("read", ["note": "读书笔记", "level": 2], index: index, current: nil)
        let o = outline["outline"]!.array!
        XCTAssertEqual(o.map { $0["text"]!.string! }, ["读书笔记", "第一章", "第二章"])
        XCTAssertEqual(o[1]["line"]!.int, 3)
        XCTAssertEqual(outline["tasks"]!.int, 1)
        let sec = try VaultQueries.run("read", ["note": "读书笔记", "level": 3, "section": "第二章"], index: index, current: nil)
        XCTAssertEqual(sec["from"]!.int, 5)
        XCTAssertEqual(sec["lines"]!.array!.compactMap(\.string), ["## 第二章", "- [ ] 读完", ""])
        XCTAssertTrue(Render.text("read", sec).contains("6| - [ ] 读完"))
        let skim = try VaultQueries.run("skim", ["tag": "同步"], index: index, current: nil)
        XCTAssertEqual(skim["cards"]!.array!.count, 1)
        XCTAssertEqual(skim["total"]!.int, 1)
    }
}
