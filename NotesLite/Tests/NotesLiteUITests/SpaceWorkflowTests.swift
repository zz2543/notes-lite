import AppKit
import NotesCore
import SwiftUI
import WebKit
import XCTest
@testable import NotesLite

/// The real window, the real WKWebView and a temporary library: no mocks between the page and the disk.
@MainActor final class SpaceWorkflowTests: XCTestCase {
    private var root: URL!
    private var previousMode: Any?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("健身"), withIntermediateDirectories: true)
        previousMode = UserDefaults.standard.object(forKey: "sidebar.mode")
        UserDefaults.standard.set("spaces", forKey: "sidebar.mode")
    }

    override func tearDown() async throws {
        if let previousMode { UserDefaults.standard.set(previousMode, forKey: "sidebar.mode") } else { UserDefaults.standard.removeObject(forKey: "sidebar.mode") }
        try? FileManager.default.removeItem(at: root)
    }

    private var note: URL { root.appendingPathComponent("健身/训练记录.md") }

    func testSpaceHomepageRendersWritesRefreshesAndReportsErrors() throws {
        _ = NSApplication.shared
        try Data("# 训练记录\n\n## 卧推\n| 日期 | 动作 | 重量 |\n|---|---|---|\n| 2026-10-12 | 卧推 | 55 |\n| 2026-10-14 | 卧推 | 57.5 |\n| 2026-10-16 | 卧推 | 60 |\n".utf8).write(to: note)
        try Data("# 计划\n".utf8).write(to: root.appendingPathComponent("健身/计划.md"))
        let library = SpaceLibrary(root: root)
        let space = try library.create(name: "健身", icon: "🏋️", scope: .folders(["健身"]))
        try Data((space.html + """
        <div class="lb-card"><lb-stat id="count" source="健身/训练记录.md#卧推" label="训练" unit="次"></lb-stat></div>
        <div class="lb-card"><lb-quick-add id="add" target="健身/训练记录.md#卧推" defaults='{"动作":"卧推"}'></lb-quick-add></div>
        <div class="lb-card"><lb-records id="recent" source="健身/训练记录.md#卧推" limit="2"></lb-records></div>
        """).utf8).write(to: library.url(of: "健身"))

        let workspace = Workspace()
        try workspace.open(root)
        let store = SpaceStore()
        let host = NSHostingView(rootView: NoteWindow(workspace: workspace, spaces: store))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1180, height: 820), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); workspace.stopWatching() }

        XCTAssertTrue(wait { store.selected == "健身" && store.showingHome }, "Space mode opens the first space's homepage")
        XCTAssertTrue(wait { self.webView(in: host) != nil }, "The homepage is a web view in the right column")
        let web = try XCTUnwrap(webView(in: host))

        // Widgets render data read through lb.
        XCTAssertTrue(wait(10) { self.text(web, "count") == "3" }, "lb-stat shows the record count: \(self.text(web, "count") ?? "nil")")

        // Quick add writes a row to the Markdown table, logs it and raises the notice.
        _ = js(web, """
        const form = document.getElementById('add').shadowRoot.querySelector('form');
        form.querySelector('input[name="重量"]').value = '65';
        form.requestSubmit(); return true;
        """)
        XCTAssertTrue(wait(5) { ((try? String(contentsOf: self.note, encoding: .utf8)) ?? "").contains("| 卧推 | 65 |") }, "The record reaches the note on disk")
        let today = js(web, "return lb.today()") as? String ?? ""
        XCTAssertTrue(try String(contentsOf: note, encoding: .utf8).contains("| \(today) | 卧推 | 65 |"), "Date defaults to today")
        XCTAssertTrue(wait { store.pageState.recentChanges == 1 }, "「主页刚修改了 1 条记录」")
        XCTAssertEqual(store.log?.entries().first?.kind, .recordAppend)

        // Live refresh: the page's own write and an external edit both reach the widgets.
        XCTAssertTrue(wait(5) { self.text(web, "count") == "4" }, "Count follows the write: \(self.text(web, "count") ?? "nil")")
        var text = try String(contentsOf: note, encoding: .utf8)
        text += "| 2099-01-01 | 外部 | 70 |\n"
        try Data(text.utf8).write(to: note)
        XCTAssertTrue(wait(5) { self.text(web, "count") == "5" && (self.text(web, "recent") ?? "").contains("外部") }, "External edits refresh the homepage")

        // A new table keeps the field order the page wrote.
        _ = js(web, "await lb.append('健身/新表.md', { 日期: '2026-01-01', 事项: '甲', 时长: 30 }); return true;")
        XCTAssertTrue(wait(5) { ((try? String(contentsOf: self.root.appendingPathComponent("健身/新表.md"), encoding: .utf8)) ?? "").contains("| 日期 | 事项 | 时长 |") })

        // Undo from the operation log removes just that record.
        try store.log?.undo(try XCTUnwrap(store.log?.entries().first { $0.kind == .recordAppend && $0.path == "健身/训练记录.md" }).id)
        XCTAssertTrue(wait(5) { self.text(web, "count") == "4" })
        XCTAssertFalse(try String(contentsOf: note, encoding: .utf8).contains("| 卧推 | 65 |"))

        // Page errors surface in the error bar, ready to copy.
        _ = js(web, "setTimeout(() => { throw new Error('故意的错误'); }, 0); return true;")
        XCTAssertTrue(wait { store.pageState.errors.contains { $0.message.contains("故意的错误") } })
        let report = try XCTUnwrap(store.pageState.errors.last).report(space: try library.space(named: "健身"), file: library.url(of: "健身"))
        XCTAssertTrue(report.contains(library.url(of: "健身").path) && report.contains("编写说明"))

        // An agent rewriting the space file shows the new page without review.
        store.pageState.errors = []
        try Data((space.html + "<p id=\"fresh\">新的主页</p>\n<script>throw new Error('第四行')</script>").utf8).write(to: library.url(of: "健身"))
        XCTAssertTrue(wait(5) { (self.js(web, "return document.getElementById('fresh')?.textContent ?? ''") as? String) == "新的主页" })
        XCTAssertTrue(wait { store.pageState.errors.contains { $0.message.contains("第四行") } })
        XCTAssertTrue(store.pageState.errors.first { $0.message.contains("第四行") }?.location.hasPrefix("空间文件第 4 行") == true, "Lines point into the space file")

        // Embedded frames never get lb, and the page can't navigate itself away.
        XCTAssertEqual(js(web, "const f = document.createElement('iframe'); f.srcdoc = '<p>x</p>'; document.body.appendChild(f); await new Promise(r => f.onload = r); return typeof f.contentWindow.lb;") as? String, "undefined")
        _ = js(web, "location.href = 'https://example.com/'; return true;")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(web.url, SpacePageController.origin(root: root, space: "健身"), "Script navigation is refused")

        // Opening a note shows the editor; 主页 returns to the homepage.
        try workspace.select("健身/计划.md")
        store.showingHome = false
        XCTAssertTrue(wait { self.findEditor(host) != nil && self.webView(in: host) == nil })
        store.select("健身")
        XCTAssertTrue(wait { self.webView(in: host) === web }, "The same page comes back, state intact")
    }

    // MARK: helpers

    private func wait(_ timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private func js(_ web: WKWebView, _ body: String) -> Any? {
        var result: Any?, done = false
        web.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { outcome in
            if case .success(let value) = outcome { result = value }
            done = true
        }
        _ = wait(5) { done }
        return result
    }

    /// Visible text of a widget's shadow root.
    private func text(_ web: WKWebView, _ id: String) -> String? {
        let raw = js(web, "const el = document.getElementById('\(id)'); return el && el.shadowRoot ? (el.shadowRoot.querySelector('.number') || el.shadowRoot.querySelector('ul') || el.shadowRoot.querySelector('.body'))?.textContent ?? '' : null") as? String
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func webView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.webView(in: $0) }.first
    }

    private func findEditor(_ view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, editor.accessibilityLabel() == "笔记正文" { return editor }
        return view.subviews.lazy.compactMap { self.findEditor($0) }.first
    }
}
