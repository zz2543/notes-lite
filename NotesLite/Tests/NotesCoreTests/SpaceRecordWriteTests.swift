import XCTest
@testable import NotesCore

/// Writing records through lb, and undoing them one record at a time from the operation log.
final class SpaceRecordWriteTests: SpaceAPITestCase {
    var clock: Date!
    func log() -> OperationLog { OperationLog(root: root, now: { [unowned self] in self.clock }) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = today
    }

    func testAppendAddsRowsAtTheTableEndAndKeepsTheRestOfTheNote() throws {
        let log = log(), api = api(log: log)
        let reply = call(api, "append", "健身/训练记录.md#卧推", [["日期": "{今天}", "动作": "卧推", "重量": 62.5, "组数": 5], ["日期": "2026-10-19", "重量": 65]])
        XCTAssertTrue(reply.ok, reply.message ?? "")
        XCTAssertEqual((reply.result as? [String: Any])?["count"] as? Int, 2)
        XCTAssertEqual(api.lastChanges, 2)
        let text = try read("健身/训练记录.md")
        XCTAssertTrue(text.contains("| 2026-10-16 | 卧推 | 60 | 5 |\n| 2026-10-18 | 卧推 | 62.5 | 5 |\n| 2026-10-19 |  | 65 |  |\n\n## 深蹲"), text)
        XCTAssertTrue(text.hasSuffix("| 2026-10-15 | 80 |"), "Other tables are untouched")
        XCTAssertEqual(log.entries().count, 2, "One entry per record")
        XCTAssertEqual(log.entries().first?.space, "健身")
    }

    func testAppendRefusesUnknownFieldsAndEscapesPipes() throws {
        XCTAssertEqual(call(api(log: log()), "append", "健身/训练记录.md#卧推", ["心情": "好"]).code, "unknown-field")
        XCTAssertTrue(call(api(log: log()), "append", "健身/训练记录.md#卧推", ["动作": "a|b\nc"]).ok)
        XCTAssertTrue(try read("健身/训练记录.md").contains("| a\\|b c |"))
        XCTAssertEqual(records(call(api(), "query", "健身/训练记录.md#卧推")).last?["动作"] as? String, "a|b c")
    }

    func testAppendCreatesMissingNotesAndTablesFromTheHeader() throws {
        let api = api(log: log())
        XCTAssertTrue(call(api, "append", "健身/{月}.md", ["日期": "{今天}", "时长": 30], ["header": ["日期", "时长", "备注"]]).ok)
        XCTAssertEqual(try read("健身/2026-10.md"), "# 2026-10\n\n| 日期 | 时长 | 备注 |\n|---|---|---|\n| 2026-10-18 | 30 |  |\n")
        XCTAssertTrue(call(api, "append", "健身/训练记录.md#硬拉", ["日期": "2026-10-18", "重量": 100]).ok)
        let note = try read("健身/训练记录.md")
        XCTAssertTrue(note.hasSuffix("| 2026-10-15 | 80 |\n\n## 硬拉\n\n| 日期 | 重量 |\n|---|---|\n| 2026-10-18 | 100 |\n"), note)
        XCTAssertTrue(call(api, "append", "新目录/x.md", ["a": 1]).code == "outside-scope", "Creation still respects the scope")
    }

    func testUpdateAndRemoveByFieldOrRow() throws {
        let log = log(), api = api(log: log)
        let updated = call(api, "update", "健身/训练记录.md#卧推", ["重量": 60], ["组数": 6])
        XCTAssertEqual((updated.result as? [String: Any])?["count"] as? Int, 1)
        XCTAssertTrue(try read("健身/训练记录.md").contains("| 2026-10-16 | 卧推 | 60 | 6 |"))
        XCTAssertEqual((call(api, "remove", "健身/训练记录.md#卧推", ["_row": 0]).result as? [String: Any])?["count"] as? Int, 1)
        XCTAssertFalse(try read("健身/训练记录.md").contains("2026-10-12"))
        XCTAssertEqual(call(api, "update", "健身/训练记录.md#卧推", ["重量": 60], ["体重": 1]).code, "unknown-field")
        XCTAssertEqual((call(api, "remove", "健身/训练记录.md#卧推", ["重量": 999]).result as? [String: Any])?["count"] as? Int, 0)
        XCTAssertEqual(log.entries().map(\.kind), [.recordRemove, .recordUpdate], "Newest first")
    }

    func testEachRecordUndoesOnItsOwnEvenAfterReopening() throws {
        _ = call(api(log: log()), "append", "健身/训练记录.md#卧推", [["日期": "2026-10-18", "重量": 61], ["日期": "2026-10-19", "重量": 62]])
        _ = call(api(log: log()), "remove", "健身/训练记录.md#卧推", ["日期": "2026-10-14"])
        // A fresh log, as after relaunching the app.
        let reopened = log()
        let entries = reopened.entries()
        XCTAssertEqual(entries.count, 3)
        let firstAppend = try XCTUnwrap(entries.first { $0.kind == .recordAppend && $0.after == ["2026-10-18", "", "61", ""] })
        try reopened.undo(firstAppend.id)
        var text = try read("健身/训练记录.md")
        XCTAssertFalse(text.contains("| 2026-10-18 |  | 61 |"))
        XCTAssertTrue(text.contains("| 2026-10-19 |  | 62 |  |"), "The other appended record stays")
        try reopened.undo(try XCTUnwrap(entries.first { $0.kind == .recordRemove }).id)
        text = try read("健身/训练记录.md")
        XCTAssertTrue(text.contains("| 2026-10-12 | 卧推 | 55 | 5 |\n| 2026-10-14 | 卧推 | 57.5 |  |\n| 2026-10-16"), "A removed record returns to its place: \(text)")
        XCTAssertTrue(log().entries().first { $0.id == firstAppend.id }?.undone == true)
        XCTAssertThrowsError(try reopened.undo(firstAppend.id), "An entry undoes once")
    }

    func testUndoRefusesWhenTheRecordChangedSince() throws {
        let log = log()
        _ = call(api(log: log), "update", "健身/训练记录.md#卧推", ["日期": "2026-10-16"], ["重量": 61])
        let text = try read("健身/训练记录.md").replacingOccurrences(of: "| 2026-10-16 | 卧推 | 61 | 5 |", with: "| 2026-10-16 | 卧推 | 70 | 5 |")
        try Data(text.utf8).write(to: root.appendingPathComponent("健身/训练记录.md"))
        XCTAssertThrowsError(try log.undo(try XCTUnwrap(log.entries().first).id)) { error in
            XCTAssertEqual((error as? SpaceAPIError)?.code, "conflict")
        }
        XCTAssertTrue(try read("健身/训练记录.md").contains("| 70 |"), "Nothing is overwritten")
    }

    func testEntriesOlderThanThirtyDaysArePruned() throws {
        _ = call(api(log: log()), "append", "健身/训练记录.md#卧推", ["日期": "2026-10-18"])
        clock = today.addingTimeInterval(29 * 86_400)
        XCTAssertEqual(log().entries().count, 1)
        clock = today.addingTimeInterval(31 * 86_400)
        XCTAssertEqual(log().entries().count, 0)
        _ = call(api(log: log()), "append", "健身/训练记录.md#卧推", ["日期": "2026-11-18"])
        let stored = try Data(contentsOf: root.appendingPathComponent(".留白/操作记录.json"))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("2026-10-18\""), "Expired entries leave the file")
    }

    func testTheLogIsNotReachableThroughLb() {
        XCTAssertEqual(call(api(), "read", ".留白/操作记录.json").code, "outside-scope")
    }
}
