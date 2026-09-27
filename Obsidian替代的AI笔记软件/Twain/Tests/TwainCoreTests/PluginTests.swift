import XCTest
@testable import TwainCore

final class PluginTests: XCTestCase {
    func testManifestParsesAndKeepsUnknownFields() throws {
        let json = """
        {"id": "reading", "name": "读书", "icon": "book", "custom": {"x": 1},
         "collections": {"pages": {"label": "阅读", "fields": {"pages": {"label": "页数", "unit": "页"}}}},
         "space": {"folder": "/读书/", "entry": {"title": "{{date}} 读书"}, "rules": "rules.md",
                   "modules": [{"type": "stat", "collection": "pages", "field": "pages"}, {"type": "text", "text": "hi"}]}}
        """
        let p = try Plugin.parse(dir: ".twain/plugins/reading", json: Data(json.utf8))
        XCTAssertEqual(p.space?.folder, "读书")
        XCTAssertEqual(p.space?.entryTitle, "{{date}} 读书")
        XCTAssertEqual(p.space?.modules.count, 2)
        XCTAssertEqual(p.label(collection: "pages", field: "pages").unit, "页")
        let edited = p.withModules([["type": "today"]])
        XCTAssertEqual(edited["custom"]?["x"], 1)
        XCTAssertEqual(edited["space"]?["modules"]?.array?.count, 1)
        XCTAssertEqual(edited["space"]?["rules"]?.string, "rules.md")
        XCTAssertThrowsError(try Plugin.parse(dir: "x", json: Data("[1]".utf8)))
    }

    func testDateVars() {
        let d = DataStore.day.date(from: "2026-09-27")!
        let v = DateVars.vars(d)
        XCTAssertEqual(v["date"], "2026-09-27")
        XCTAssertEqual(v["week"], "2026-W39")
        XCTAssertEqual(v["yesterday"], "2026-09-26")
        XCTAssertEqual(v["weekday"], "星期日")
    }
}
