import XCTest
@testable import NotesCore

/// External tools (agents, other editors, Finder) change the library while the app stays in front.
@MainActor final class FileWatchingTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func eventually(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return condition()
    }

    func testExternalCreateModifyAndDeleteAppearWithoutReactivation() async throws {
        let workspace = Workspace()
        try workspace.open(root)
        workspace.startWatching()
        defer { workspace.stopWatching() }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("健身"), withIntermediateDirectories: true)
        try Data("# 训练\n\n| 日期 |\n|---|\n".utf8).write(to: root.appendingPathComponent("健身/训练.md"))
        let created = await eventually { workspace.notes.map(\.path) == ["健身/训练.md"] && workspace.folders == ["健身"] }
        XCTAssertTrue(created, "Externally created note should appear: \(workspace.notes.map(\.path))")
        XCTAssertEqual(workspace.searchNotes("日期").map(\.path), ["健身/训练.md"], "Search sees the new body")

        try FileManager.default.removeItem(at: root.appendingPathComponent("健身/训练.md"))
        let deleted = await eventually { workspace.notes.isEmpty }
        XCTAssertTrue(deleted)
    }

    func testCleanCurrentNoteReloadsButDirtyNoteKeepsInputAndReportsConflict() async throws {
        try Data("原文".utf8).write(to: root.appendingPathComponent("日记.md"))
        let workspace = Workspace()
        try workspace.open(root)
        workspace.startWatching()
        defer { workspace.stopWatching() }
        XCTAssertEqual(workspace.current, "日记.md")

        try Data("外部修改".utf8).write(to: root.appendingPathComponent("日记.md"))
        let reloaded = await eventually { workspace.text == "外部修改" }
        XCTAssertTrue(reloaded, "A clean note follows the disk")
        XCTAssertFalse(workspace.dirty)

        workspace.edit("我的输入")
        try Data("再次外部修改".utf8).write(to: root.appendingPathComponent("日记.md"))
        let conflicted = await eventually { workspace.saveState == "保存冲突" }
        XCTAssertTrue(conflicted)
        XCTAssertEqual(workspace.text, "我的输入", "Unsaved input is never silently overwritten")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("日记.md"), encoding: .utf8), "再次外部修改")
    }

    func testSubscribersSeeHiddenAppDirectoryChangesThatTheNoteListIgnores() async throws {
        let workspace = Workspace()
        try workspace.open(root)
        workspace.startWatching()
        defer { workspace.stopWatching() }
        var seen: [String] = []
        let token = workspace.observeChanges { seen.append(contentsOf: $0) }
        defer { workspace.removeObserver(token) }
        let spaces = root.appendingPathComponent(".留白/空间")
        try FileManager.default.createDirectory(at: spaces, withIntermediateDirectories: true)
        try Data("<meta name=\"lb-scope\" content=\"*\">".utf8).write(to: spaces.appendingPathComponent("健身.html"))
        let observed = await eventually { seen.contains(".留白/空间/健身.html") }
        XCTAssertTrue(observed, "Seen: \(seen)")
        XCTAssertTrue(workspace.notes.isEmpty)
        XCTAssertTrue(workspace.folders.isEmpty, ".留白 never shows as a folder")
    }

    func testRefreshReusesUnchangedBodiesAndPicksUpModifiedOnes() throws {
        let workspace = Workspace()
        try workspace.open(root)
        try Data("一".utf8).write(to: root.appendingPathComponent("甲.md"))
        try workspace.refresh()
        XCTAssertEqual(workspace.searchNotes("一").map(\.path), ["甲.md"])
        let file = root.appendingPathComponent("甲.md")
        try Data("二".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        try workspace.refresh()
        XCTAssertEqual(workspace.searchNotes("二").map(\.path), ["甲.md"])
        XCTAssertTrue(workspace.searchNotes("一").isEmpty)
    }

    func testCleanEditorLetsGoOfANoteTrashedElsewhere() async throws {
        try Data("内容".utf8).write(to: root.appendingPathComponent("要删.md"))
        let workspace = Workspace()
        try workspace.open(root)
        workspace.startWatching()
        defer { workspace.stopWatching() }
        XCTAssertEqual(workspace.current, "要删.md")
        try FileManager.default.trashItem(at: root.appendingPathComponent("要删.md"), resultingItemURL: nil)
        let released = await eventually { workspace.current == nil && workspace.notes.isEmpty }
        XCTAssertTrue(released)
    }
}
