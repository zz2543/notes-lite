import XCTest
@testable import TwainCore

final class DataTests: XCTestCase {
    func testAddQueryDaily() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DataStore(vault: root)
        let now = DataStore.day.date(from: "2026-09-27")!.addingTimeInterval(12 * 3600)
        XCTAssertEqual(try store.add("sleep", records: [["hours": 7, "date": "2026-09-25"], ["hours": 6, "date": "2026-09-27"],
                                                         ["hours": 1, "date": "2026-09-27"]], now: now), 3)
        try store.add("sleep", records: [["note": "午睡"]], now: now)
        XCTAssertEqual(store.all("sleep").count, 4)
        XCTAssertNotNil(store.all("sleep")[3]["time"], "a record without time gets one")
        let d = store.daily("sleep", field: "hours", days: 3, now: now)
        XCTAssertEqual(d.map(\.day), ["2026-09-25", "2026-09-26", "2026-09-27"])
        XCTAssertEqual(d.map(\.value), [7, nil, 7])
        XCTAssertEqual(store.daily("sleep", field: "hours", days: 1, reduce: "max", now: now).first?.value, 6)
        XCTAssertEqual(store.query("sleep", since: DataStore.day.date(from: "2026-09-26")).count, 3)
        XCTAssertThrowsError(try store.add("../x", records: [["a": 1]]))
        XCTAssertThrowsError(try store.add("ok", records: ["not an object"]))
        XCTAssertEqual(store.collections().map(\.name), ["sleep"])
    }

    func testParseFormats() throws {
        XCTAssertEqual(try DataStore.parse(#"[{"a":1},{"a":2}]"#, ext: "json").count, 2)
        XCTAssertEqual(try DataStore.parse(#"{"a":1}"#, ext: "json").count, 1)
        XCTAssertEqual(try DataStore.parse("{\"a\":1}\n{\"a\":2}\n", ext: "jsonl").count, 2)
        let rows = try DataStore.parse("date,minutes,type\n2026-09-27,45,\"力量, 核心\"\n", ext: "csv")
        XCTAssertEqual(rows.first?["minutes"], 45)
        XCTAssertEqual(rows.first?["type"]?.string, "力量, 核心")
        XCTAssertEqual(DataStore.parseSince("7d", now: DataStore.day.date(from: "2026-09-27")!).map { DataStore.day.string(from: $0) }, "2026-09-20")
    }
}
