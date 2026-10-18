import XCTest
@testable import NotesCore

/// Spaces live as `.留白/空间/<名称>.html` inside the note library; checked through the files they leave on disk.
final class SpaceLibraryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func read(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

    func testCreatingASpaceWritesAnEmptyPageWithScopeAndIconMeta() throws {
        let library = SpaceLibrary(root: root)
        let space = try library.create(name: "健身", icon: "🏋️", scope: .folders(["健身", "日记"]))
        XCTAssertEqual(space.path, ".留白/空间/健身.html")
        XCTAssertFalse(space.hasPage, "A new space has no homepage yet")
        let html = try read(".留白/空间/健身.html")
        XCTAssertTrue(html.contains(#"<meta name="lb-scope" content="健身, 日记">"#), html)
        XCTAssertTrue(html.contains(#"<meta name="lb-icon" content="🏋️">"#), html)

        let listed = try library.spaces()
        XCTAssertEqual(listed.map(\.name), ["健身"])
        XCTAssertEqual(listed[0].icon, "🏋️")
        XCTAssertEqual(listed[0].scope, .folders(["健身", "日记"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".留白/空间/编写说明.md").path), "The authoring guide is installed with the first space")
    }

    func testWholeLibraryScopeAndPageDetection() throws {
        try write(".留白/空间/全局.html", "<meta name=\"lb-icon\" content=\"🌍\">\n<meta content=\"*\" name=\"lb-scope\">\n<!-- 空的 -->\n  \n")
        try write(".留白/空间/雅思.html", "<meta name=\"lb-scope\" content=\"英语-雅思\">\n<div class=\"lb-card\">内容</div>")
        let spaces = try SpaceLibrary(root: root).spaces()
        XCTAssertEqual(spaces.map(\.name), ["全局", "雅思"])
        XCTAssertEqual(spaces[0].scope, .library)
        XCTAssertFalse(spaces[0].hasPage)
        XCTAssertTrue(spaces[1].hasPage)
        XCTAssertTrue(SpaceScope.library.contains("任何/笔记.md"))
        XCTAssertTrue(spaces[1].scope.contains("英语-雅思/单词.md"))
        XCTAssertFalse(spaces[1].scope.contains("英语-雅思2/单词.md"))
        XCTAssertFalse(spaces[1].scope.contains("日记/a.md"))
    }

    func testSameFolderInSeveralSpacesAndInvalidNames() throws {
        let library = SpaceLibrary(root: root)
        _ = try library.create(name: "健身", icon: "🏋️", scope: .folders(["日记"]))
        _ = try library.create(name: "雅思", icon: "📚", scope: .folders(["日记", "英语"]))
        XCTAssertEqual(try library.spaces().filter { $0.scope.contains("日记/今天.md") }.count, 2)
        XCTAssertThrowsError(try library.create(name: "健身", icon: "x", scope: .library), "Duplicate names are refused")
        XCTAssertThrowsError(try library.create(name: "a/b", icon: "x", scope: .library))
        XCTAssertThrowsError(try library.create(name: ".隐藏", icon: "x", scope: .library))
        XCTAssertThrowsError(try library.create(name: "空范围", icon: "x", scope: .folders([])))
    }

    func testPromptNamesGuideFileScopeAndExistingRecordTables() throws {
        try write("健身/训练记录.md", "# 训练记录\n\n## 卧推\n\n| 日期 | 动作 | 重量 | 组数 |\n|---|---|---|---|\n| 2026-10-18 | 卧推 | 60 | 5 |\n\n```\n| 不是 | 表 |\n|---|---|\n```\n")
        try write("日记/2026-10.md", "| 日期 | 时长 |\n| --- | --- |\n")
        try write("别处/无关.md", "| 字段 |\n|---|\n")
        let library = SpaceLibrary(root: root)
        let space = try library.create(name: "健身", icon: "🏋️", scope: .folders(["健身", "日记"]))
        let prompt = try library.prompt(for: space)
        XCTAssertTrue(prompt.contains(root.appendingPathComponent(".留白/空间/编写说明.md").path), prompt)
        XCTAssertTrue(prompt.contains(root.appendingPathComponent(".留白/空间/健身.html").path))
        XCTAssertTrue(prompt.contains("健身、日记"))
        XCTAssertTrue(prompt.contains("健身/训练记录.md#卧推：日期 | 动作 | 重量 | 组数"), prompt)
        XCTAssertTrue(prompt.contains("日记/2026-10.md：日期 | 时长"), prompt)
        XCTAssertFalse(prompt.contains("别处"), "Tables outside the scope are not offered")
        XCTAssertFalse(prompt.contains("不是"), "Tables inside code fences are not record tables")
    }

    func testGuideIsRewrittenWhenOutdated() throws {
        try write(".留白/空间/编写说明.md", "旧版本")
        let library = SpaceLibrary(root: root)
        try library.installGuide()
        XCTAssertEqual(try read(".留白/空间/编写说明.md"), SpaceGuide.text)
    }
}
