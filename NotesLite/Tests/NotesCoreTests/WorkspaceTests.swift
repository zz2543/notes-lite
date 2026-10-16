import XCTest
@testable import NotesCore

@MainActor final class WorkspaceTests: XCTestCase {
    func testWriterCanCreateSaveAndReopenWithoutChangingLegacyMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".twain"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = root.appendingPathComponent(".twain/history.json")
        try Data("legacy".utf8).write(to: metadata)
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "中文笔记")
        workspace.edit("# 中文笔记\n\n保存这段内容。")
        try workspace.save()
        let reopened = Workspace()
        try reopened.open(root)
        try reopened.select("中文笔记.md")
        XCTAssertEqual(reopened.text, "# 中文笔记\n\n保存这段内容。")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("中文笔记.md"), encoding: .utf8), reopened.text)
        XCTAssertEqual(try Data(contentsOf: metadata), Data("legacy".utf8))
    }
    func testFollowingLinkFindsChineseNoteAndRejectsAmbiguity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("阅读"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "# 摘记".write(to: root.appendingPathComponent("阅读/摘记.md"), atomically: true, encoding: .utf8)
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "入口")
        try workspace.followLink("摘记#章节|显示名称")
        XCTAssertEqual(workspace.current, "阅读/摘记.md")
        try "# 同名".write(to: root.appendingPathComponent("摘记.md"), atomically: true, encoding: .utf8)
        try workspace.refresh()
        try workspace.select("入口.md")
        XCTAssertThrowsError(try workspace.followLink("不存在"))
        // A root-relative exact match wins; otherwise ambiguous basenames must be rejected.
        try workspace.followLink("阅读/摘记")
        XCTAssertEqual(workspace.current, "阅读/摘记.md")
    }

    func testConflictPreservesBothVersionsAndWriterCanSaveCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "冲突")
        workspace.edit("我的未保存输入")
        try "外部的新内容".write(to: root.appendingPathComponent("冲突.md"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try workspace.save())
        XCTAssertEqual(workspace.text, "我的未保存输入")
        XCTAssertTrue(workspace.dirty)
        try workspace.saveCopy(title: "保留副本")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("冲突.md"), encoding: .utf8), "外部的新内容")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("保留副本.md"), encoding: .utf8), "我的未保存输入")
        XCTAssertFalse(workspace.dirty)
    }

    func testImportAndMovePreservesImageReferenceAndBacklink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "图片笔记")
        let snippet = try workspace.importAttachment(data: Data([1,2,3]), name: "示例.png")
        workspace.edit("# 图片笔记\n" + snippet)
        try workspace.save()
        try workspace.createNote(title: "入口")
        workspace.edit("见 [[图片笔记]]")
        try workspace.save()
        try workspace.select("图片笔记.md")
        try workspace.createFolder("归档")
        try workspace.relocateCurrent(to: "归档/新名字.md")
        XCTAssertEqual(workspace.current, "归档/新名字.md")
        XCTAssertTrue(workspace.text.contains("(../"))
        XCTAssertEqual(try Data(contentsOf: workspace.resolveFile("../附件/示例.png")!), Data([1,2,3]))
        try workspace.select("入口.md")
        XCTAssertEqual(workspace.text, "见 [[归档/新名字]]")
        try workspace.followLink("归档/新名字")
        XCTAssertEqual(workspace.current, "归档/新名字.md")
    }

    func testSaveFailureKeepsDraftAndCanRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path); try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "保存失败")
        workspace.edit("仍然保留的输入")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        XCTAssertThrowsError(try workspace.save())
        XCTAssertTrue(workspace.dirty)
        XCTAssertEqual(workspace.text, "仍然保留的输入")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try workspace.save()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("保存失败.md"), encoding: .utf8), "仍然保留的输入")
    }

    func testSearchRecentsAndDuplicateNamesRemainUnambiguous() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "日记")
        workspace.edit("今天散步看见了落叶")
        try workspace.save()
        try workspace.createNote(title: "日记")
        XCTAssertEqual(workspace.current, "日记 2.md")
        workspace.query = "落叶"
        XCTAssertEqual(workspace.visibleNotes.map(\.path), ["日记.md"])
        workspace.query = ""
        try workspace.select("日记.md")
        workspace.recentsOnly = true
        XCTAssertEqual(workspace.visibleNotes.map(\.path), ["日记.md", "日记 2.md"])
        XCTAssertThrowsError(try workspace.renameCurrent(title: "../不应创建"))
        XCTAssertEqual(workspace.current, "日记.md")
    }

    func testAutosavePersistsWithoutManualSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "自动保存")
        workspace.edit("不需要按保存键")
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertFalse(workspace.dirty)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("自动保存.md"), encoding: .utf8), "不需要按保存键")
    }

    func testRenamingUpdatesRealLinksButLeavesCodeExamplesAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "目标")
        try workspace.createNote(title: "说明")
        workspace.edit("链接 [[目标]]\n\n`[[目标]]`\n\n```text\n[[目标]]\n```\n")
        try workspace.save()
        try workspace.select("目标.md")
        try workspace.renameCurrent(title: "新目标")
        try workspace.select("说明.md")
        XCTAssertEqual(workspace.text, "链接 [[新目标]]\n\n`[[目标]]`\n\n```text\n[[目标]]\n```\n")
    }

}
