import AppKit
import XCTest
import SwiftUI
import MetalKit
import NotesCore
@testable import NotesLite

/// Runs the real SwiftUI window and AppKit editor against a temporary note library.
/// Uses native text-input operations, including marked-text composition; no editor mocks.
@MainActor final class EditorWorkflowTests: XCTestCase {
    func testChineseCompositionSourceToggleAndFocusKeepEditingContinuity() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "连续写作")
        let host = NSHostingView(rootView: NoteWindow(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 1180, height: 800), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "NotesLite — isolated verification"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let editor = try XCTUnwrap(findEditor(host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        workspace.source = true
        settle(host)
        XCTAssertTrue(editor.hasMarkedText(), "Style changes must not destroy IME composition")
        editor.insertText("中文组合输入", replacementRange: editor.markedRange())
        editor.unmarkText()
        XCTAssertTrue(workspace.text.contains("中文组合输入"))
        let selection = editor.selectedRange()
        workspace.focus = true
        settle(host)
        let focusedEditor = try XCTUnwrap(findEditor(host))
        XCTAssertEqual(focusedEditor.selectedRange(), selection)
        XCTAssertTrue(focusedEditor.string.contains("中文组合输入"))
        workspace.focus = false; workspace.source = false
        settle(host)
        let restored = try XCTUnwrap(findEditor(host))
        XCTAssertEqual(restored.selectedRange(), selection)
        restored.undoManager?.beginUndoGrouping()
        restored.insertText("X", replacementRange: restored.selectedRange())
        restored.undoManager?.endUndoGrouping()
        restored.undoManager?.undo()
        XCTAssertFalse(workspace.text.hasSuffix("X"))
        restored.undoManager?.redo()
        XCTAssertTrue(workspace.text.hasSuffix("X"))
        restored.undoManager?.undo()
        try workspace.save()
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("连续写作.md"), encoding: .utf8).contains("中文组合输入"))
    }

    func testLongDocumentCanBeEditedAndSavedInNativeWindow() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let body = "# 长文\n\n" + (1...5000).map { "第\($0)行：保留可读内容与连续输入。" }.joined(separator: "\n")
        try body.write(to: root.appendingPathComponent("长文.md"), atomically: true, encoding: .utf8)
        let start = Date()
        let workspace = Workspace()
        try workspace.open(root)
        let host = NSHostingView(rootView: NoteWindow(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 1180, height: 800), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let firstLayoutMs = Date().timeIntervalSince(start)*1000
        let editor = try XCTUnwrap(findEditor(host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let insertStart = Date()
        editor.insertText("\n新输入", replacementRange: editor.selectedRange())
        let insertMs = Date().timeIntervalSince(insertStart)*1000
        settle(host)
        try workspace.save()
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("长文.md"), encoding: .utf8).hasSuffix("\n新输入"))
        if let path = ProcessInfo.processInfo.environment["NOTESLITE_EVIDENCE_DIR"] {
            let result: [String: Any] = ["lines":5003,"initialCharacters":body.count,"openThroughFirstRunloopMs":firstLayoutMs,"synchronousNativeInsertMs":insertMs,"note":"First layout includes a 60ms runloop observation; this is not a frame-rate benchmark"]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: path).appendingPathComponent("long-document.json"))
        }
    }
    func testSearchAndEditorRemainUsableWithoutMetal() throws {
        _ = NSApplication.shared
        setenv("NOTESLITE_NO_METAL", "1", 1)
        defer { unsetenv("NOTESLITE_NO_METAL") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "降级验证")
        let host = NSHostingView(rootView: NoteWindow(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 1180, height: 800), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        NotificationCenter.default.post(name: .init("NotesLite.search"), object: nil)
        settle(host)
        func metalView(_ view: NSView) -> MTKView? {
            if let metal = view as? MTKView { return metal }
            return view.subviews.lazy.compactMap { metalView($0) }.first
        }
        let surface = try XCTUnwrap(metalView(host))
        XCTAssertNil(surface.device)
        XCTAssertTrue(surface.isPaused)
        workspace.query = "降级"
        XCTAssertEqual(workspace.visibleNotes.count, 1)
        workspace.edit("Metal 不可用仍能保存")
        try workspace.save()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("降级验证.md"), encoding: .utf8), workspace.text)
    }

    private func findEditor(_ root: NSView) -> NSTextView? {
        if let editor = root as? NSTextView, editor.accessibilityLabel() == "笔记正文" { return editor }
        return root.subviews.lazy.compactMap { self.findEditor($0) }.first
    }
    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        host.layoutSubtreeIfNeeded()
    }
}
