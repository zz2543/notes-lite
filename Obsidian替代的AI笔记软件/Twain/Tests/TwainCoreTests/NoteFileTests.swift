import XCTest
@testable import TwainCore

final class NoteFileTests: XCTestCase {
    private func temp(_ name: String, _ data: Data) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("nf-\(UUID())-\(name)")
        try data.write(to: u)
        return u
    }

    func testUnreadableReasons() throws {
        let text = try temp("a.md", Data("# 标题\n正文".utf8))
        let zeros = try temp("b.md", Data(repeating: 0, count: 100))
        defer { try? FileManager.default.removeItem(at: text); try? FileManager.default.removeItem(at: zeros) }
        XCTAssertNil(NoteFile.unreadableReason(text))
        XCTAssertNotNil(NoteFile.unreadableReason(zeros))
    }

    func testOversizedLinesAreClippedForDisplay() {
        let long = String(repeating: "x", count: NoteFile.oversizedLine + 1)
        XCTAssertFalse(NoteFile.hasOversizedLine("short\nlines"))
        XCTAssertFalse(NoteFile.hasOversizedLine(String(repeating: "ab\n", count: 50_000)), "many short lines are fine")
        XCTAssertTrue(NoteFile.hasOversizedLine("# t\n" + long + "\nend"))
        let shown = NoteFile.clippedForDisplay("# t\n" + long + "\nend")
        let lines = shown.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix(String(repeating: "x", count: NoteFile.shownOfLongLine) + " …"))
        XCTAssertTrue(lines[1].contains("\(NoteFile.oversizedLine + 1 - NoteFile.shownOfLongLine) 个字符"))
        XCTAssertEqual(lines[2], "end")
    }

    func testOffsetOfLine() {
        let t = "一\n二二\n\n四"
        XCTAssertEqual(NoteFile.offset(ofLine: 1, in: t), 0)
        XCTAssertEqual(NoteFile.offset(ofLine: 2, in: t), 2)
        XCTAssertEqual(NoteFile.offset(ofLine: 4, in: t), 6)
        XCTAssertEqual(NoteFile.offset(ofLine: 99, in: t), (t as NSString).length)
    }

    func testNewNotePathStaysInsideTheVault() throws {
        XCTAssertEqual(try NoteFile.newNotePath("项目/计划"), "项目/计划.md")
        XCTAssertEqual(try NoteFile.newNotePath("/a.MD"), "a.MD")
        XCTAssertThrowsError(try NoteFile.newNotePath("../外面"))
        XCTAssertThrowsError(try NoteFile.newNotePath(".twain/x"))
        XCTAssertThrowsError(try NoteFile.newNotePath("  "))
    }
}

final class WriteAttributionTests: XCTestCase {
    func testOnlyAWriteInTheTranscriptCounts() {
        let events: [AgentEvent] = [
            .step(id: "1", text: "读取 AGENTS.md", write: nil),
            .step(id: "2", text: "编辑", write: "/v/项目/计划.md"),
            .step(id: "3", text: "$ sed -i '' s/a/b/ 周报.md", write: nil),
            .text("好了"),
        ]
        let r = WriteAttribution.recent(events)
        XCTAssertEqual(r.paths, ["/v/项目/计划.md"])
        XCTAssertEqual(r.steps.count, 3)
        XCTAssertTrue(WriteAttribution.explains("项目/计划.md", root: "/v", paths: r.paths, steps: r.steps))
        XCTAssertTrue(WriteAttribution.explains("周报.md", root: "/v", paths: r.paths, steps: r.steps), "named in a shell step")
        XCTAssertFalse(WriteAttribution.explains("别的.md", root: "/v", paths: r.paths, steps: r.steps))
        XCTAssertEqual(WriteAttribution.recent(events, window: 1).steps, [], "only the last events count")
    }

    func testClaudeProjectFolder() {
        XCTAssertEqual(ClaudeStream.projectFolderName(cwd: "/Users/me/Obsidian all/笔记"), "-Users-me-Obsidian-all---")
    }
}

final class CacheFolderTests: XCTestCase {
    func testPruneDropsOldFilesThenOldestAndOlderVersions() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("cache-\(UUID())")
        let dir = base.appendingPathComponent("render-3"), old = base.appendingPathComponent("render-2")
        let other = base.appendingPathComponent("other")
        for d in [dir, old, other] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: base) }
        let now = Date()
        func file(_ name: String, bytes: Int, age: TimeInterval) throws {
            let u = dir.appendingPathComponent(name)
            try Data(repeating: 1, count: bytes).write(to: u)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: u.path)
        }
        try file("stale", bytes: 10, age: 100 * 86400)
        try file("old", bytes: 600, age: 3 * 86400)
        try file("mid", bytes: 600, age: 2 * 86400)
        try file("new", bytes: 600, age: 60)
        CacheFolder.prune(dir, olderVersionsIn: base, now: now, maxAge: 60 * 86400, maxBytes: 1300)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: dir.path)), ["mid", "new"])
        XCTAssertFalse(fm.fileExists(atPath: old.path), "an older version of the same cache goes")
        XCTAssertTrue(fm.fileExists(atPath: other.path), "unrelated folders stay")
    }
}

@MainActor
final class VaultAttachmentTests: XCTestCase {
    func testAttachmentsResolveLikeObsidian() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("att-\(UUID())").standardizedFileURL.resolvingSymlinksInPath()
        for rel in ["我的笔记/a.md", "我的笔记/图.png", "附件/图.png", "附件/深/图.png", "附件/其他.PNG"] {
            let u = root.appendingPathComponent(rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: u)
        }
        defer { try? fm.removeItem(at: root) }
        let v = Vault(root: root)
        XCTAssertEqual(v.attachment("图.png", from: "我的笔记/a.md"), "我的笔记/图.png", "next to the note first")
        XCTAssertEqual(v.attachment("图.png|300", from: nil), "附件/图.png", "shortest path wins; size suffix ignored")
        XCTAssertEqual(v.attachment("深/图.png", from: nil), "附件/深/图.png", "a partial path narrows it")
        XCTAssertEqual(v.attachment("其他.png", from: nil), "附件/其他.PNG", "names match without case")
        XCTAssertNil(v.attachment("没有.png", from: nil))
        v.attachmentAdded("附件/新.png")
        XCTAssertEqual(v.attachments["新.png"], ["附件/新.png"])
    }
}

final class PluginAndDataTests: XCTestCase {
    func testEditedModulesKeepTheRestOfTheManifest() throws {
        let json = #"{"id":"j","name":"日记","extra":{"keep":1},"space":{"folder":"/日记/","modules":[{"type":"today"}]},"collections":{"sleep":{"label":"睡眠","fields":{"hours":{"label":"时长","unit":"小时"}}}}}"#
        let p = try Plugin.parse(dir: ".twain/plugins/j", json: Data(json.utf8))
        XCTAssertEqual(p.space?.folder, "日记")
        let edited = p.withModules([["type": "stats"]])
        XCTAssertEqual(edited["extra"]?["keep"], 1)
        XCTAssertEqual(edited["space"]?["folder"]?.string, "/日记/")
        XCTAssertEqual(edited["space"]?["modules"]?.array?.count, 1)
        XCTAssertEqual(p.label(collection: "sleep", field: "hours").unit, "小时")
    }

    func testDailyReductions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("data-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DataStore(vault: root)
        _ = try store.add("run", records: [["km": 3, "date": "2026-09-26"], ["km": 5, "date": "2026-09-26"], ["km": 4, "date": "2026-09-27"]])
        let now = DataStore.day.date(from: "2026-09-27")!.addingTimeInterval(3600)
        XCTAssertEqual(store.daily("run", field: "km", days: 2, reduce: "avg", now: now).map(\.value), [4, 4])
        XCTAssertEqual(store.daily("run", field: "km", days: 2, reduce: "last", now: now).map(\.value), [5, 4])
        XCTAssertEqual(store.daily("run", field: "km", days: 2, now: now).map(\.value), [8, 4])
        XCTAssertEqual(store.daily("run", field: "count", days: 2, now: now).map(\.value), [2, 1], "count counts records")
        let d = DataStore.day
        XCTAssertEqual(DataStore.parseSince("2w", now: d.date(from: "2026-09-27")!).map(d.string), "2026-09-13")
        XCTAssertNil(DataStore.parseSince("7x"))
        XCTAssertEqual(DataStore.parseSince("2026-01-02").map(d.string), "2026-01-02")
    }
}
