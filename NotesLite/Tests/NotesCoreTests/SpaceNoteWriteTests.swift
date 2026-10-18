import XCTest
@testable import NotesCore

/// Space homepages managing notes inside their scope, and rewriting their own space file.
final class SpaceNoteWriteTests: SpaceAPITestCase {
    func log() -> OperationLog { OperationLog(root: root, now: { [today] in today }) }
    var exists: (String) -> Bool { { [root] in FileManager.default.fileExists(atPath: root!.appendingPathComponent($0).path) } }

    func testCreateWriteAndUndo() throws {
        let log = log(), api = api(log: log)
        XCTAssertTrue(call(api, "create", "健身/计划.md", "# 计划\n").ok)
        XCTAssertEqual(call(api, "create", "健身/计划.md", "x").code, "exists")
        XCTAssertTrue(call(api, "write", "健身/计划.md", "# 计划\n\n周一练胸").ok)
        XCTAssertEqual(try read("健身/计划.md"), "# 计划\n\n周一练胸")
        let entries = log.entries()
        XCTAssertEqual(entries.map(\.kind), [.noteWrite, .noteCreate])
        XCTAssertEqual(entries[0].changes.map { "\($0.sign)\($0.text)" }, ["+周一练胸"], "The log shows what the write changed")
        try log.undo(entries[0].id)
        XCTAssertEqual(try read("健身/计划.md"), "# 计划\n")
        try log.undo(entries[1].id)
        XCTAssertFalse(exists("健身/计划.md"), "Undoing a create sends the note to the trash")
        XCTAssertEqual(call(api, "create", "别处/x.md", "").code, "outside-scope")
        XCTAssertEqual(call(api, "write", "别处/秘密.md", "").code, "outside-scope")
        XCTAssertEqual(try read("别处/秘密.md"), "不在范围内")
    }

    func testRenameAndMoveUpdateLinksAndUndoTogether() throws {
        try write("日记/今天.md", "见 [[训练记录]] 和 [卧推](../健身/训练记录.md#卧推)")
        let log = log(), api = api(log: log)
        XCTAssertTrue(call(api, "rename", "健身/训练记录.md", "力量训练").ok)
        XCTAssertTrue(exists("健身/力量训练.md")); XCTAssertFalse(exists("健身/训练记录.md"))
        XCTAssertEqual(try read("日记/今天.md"), "见 [[健身/力量训练]] 和 [卧推](../%E5%81%A5%E8%BA%AB/%E5%8A%9B%E9%87%8F%E8%AE%AD%E7%BB%83.md#卧推)", "Links follow the note, encoded as the editor writes them")
        XCTAssertTrue(call(api, "move", "健身/力量训练.md", "日记").ok)
        XCTAssertTrue(exists("日记/力量训练.md"))
        XCTAssertEqual(call(api, "move", "日记/力量训练.md", "别处").code, "outside-scope")
        XCTAssertEqual(call(api, "rename", "日记/力量训练.md", "../逃逸").code, "invalid")
        for entry in log.entries() { try log.undo(entry.id) }
        XCTAssertTrue(exists("健身/训练记录.md"))
        XCTAssertEqual(try read("日记/今天.md"), "见 [[训练记录]] 和 [卧推](../健身/训练记录.md#卧推)")
    }

    func testTrashGoesToTheTrashAndUndoRestores() throws {
        let log = log(), api = api(log: log)
        XCTAssertTrue(call(api, "trash", "日记/2026-10.md").ok)
        XCTAssertFalse(exists("日记/2026-10.md"))
        let entry = try XCTUnwrap(log.entries().first)
        XCTAssertEqual(entry.kind, .noteTrash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(entry.trashed)), "The note sits in the system trash")
        try log.undo(entry.id)
        XCTAssertTrue(exists("日记/2026-10.md"))
        XCTAssertEqual(api.lastChanges, 1, "The trash counts as one change for the notice")
    }

    func testPageCanRewriteItselfButNotItsScopeOrOtherSpaceFiles() throws {
        let log = log(), api = api(log: log)
        let page = try XCTUnwrap(call(api, "page").result as? String)
        XCTAssertTrue(call(api, "writePage", page + "<p>新主页</p>").ok)
        XCTAssertTrue(try read(".留白/空间/健身.html").hasSuffix("<p>新主页</p>"))
        XCTAssertEqual(call(api, "writePage", page.replacingOccurrences(of: "健身, 日记", with: "*")).code, "scope-change")
        XCTAssertEqual(call(api, "writePage", "<p>没有范围</p>").code, "scope-change", "Dropping lb-scope also changes the scope")
        XCTAssertEqual(call(api, "write", ".留白/空间/雅思.html", "x").code, "outside-scope")
        XCTAssertEqual(call(api, "write", ".留白/空间/编写说明.md", "x").code, "outside-scope")
        try log.undo(try XCTUnwrap(log.entries().first).id)
        XCTAssertEqual(try read(".留白/空间/健身.html"), page)
    }

    func testRenameIsRefusedWhenNotesOutsideTheScopeLinkToIt() throws {
        try write("别处/引用.md", "见 [[训练记录]]")
        let log = log(), api = api(log: log)
        let reply = call(api, "rename", "健身/训练记录.md", "力量训练")
        XCTAssertEqual(reply.code, "outside-scope")
        XCTAssertTrue(reply.message?.contains("别处/引用.md") == true, reply.message ?? "")
        XCTAssertTrue(exists("健身/训练记录.md"), "Nothing moved")
        XCTAssertEqual(try read("别处/引用.md"), "见 [[训练记录]]", "Notes outside the scope are never written")
        XCTAssertTrue(log.entries().isEmpty)
    }
}
