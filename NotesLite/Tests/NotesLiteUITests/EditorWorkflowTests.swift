import AppKit
import XCTest
import SwiftUI
import MetalKit
import NotesCore
@testable import NotesLite

/// Runs the real SwiftUI window and AppKit editor against a temporary note library.
/// Uses native text-input operations, including marked-text composition; no editor mocks.
@MainActor final class EditorWorkflowTests: XCTestCase {
    func testNavigationSettingsKeepNativeEditorAndComposition() throws {
        _ = NSApplication.shared
        let keys = ["navigation.mode", "navigation.showAll", "navigation.showRecent"]
        let defaults = UserDefaults.standard
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("split", forKey: keys[0])
        defaults.set(true, forKey: keys[1]); defaults.set(true, forKey: keys[2])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createFolder("目录")
        try workspace.createNote(title: "正文", folder: "目录")
        let host = NSHostingView(rootView: NoteWindow(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 1180, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let editor = try XCTUnwrap(findEditor(host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let range = editor.selectedRange()
        let revision = workspace.revision
        for mode in ["unified", "split", "unified"] {
            defaults.set(mode, forKey: keys[0]); settle(host)
            XCTAssertTrue(findEditor(host) === editor)
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(editor.selectedRange(), range)
            XCTAssertEqual(workspace.revision, revision)
        }
        defaults.set(false, forKey: keys[1]); settle(host)
        XCTAssertEqual(workspace.selectedFolder, "目录")
        XCTAssertTrue(findEditor(host) === editor)
        workspace.recentsOnly = true; workspace.selectedFolder = nil; settle(host)
        defaults.set(false, forKey: keys[2]); settle(host)
        XCTAssertFalse(workspace.recentsOnly)
        XCTAssertEqual(workspace.selectedFolder, "目录")
        XCTAssertFalse(workspace.recent.isEmpty)
        editor.insertText("中文", replacementRange: editor.markedRange()); editor.unmarkText()
        try workspace.save()
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("目录/正文.md"), encoding: .utf8).contains("中文"))
    }

    func testFontChangesPreserveNativeDocumentSelectionCompositionAndUndo() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "字体验证")
        workspace.edit("English 中文，标点。\n\n第二段")
        let host = NSHostingView(rootView: NativeEditor(workspace: workspace, font: .sans))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let editor = try XCTUnwrap(findEditor(host))
        window.makeFirstResponder(editor)
        let original = editor.string
        let selection = NSRange(location: 2, length: 3)
        editor.setSelectedRange(selection)
        for family in EditorFont.allCases {
            host.rootView = NativeEditor(workspace: workspace, font: family)
            settle(host)
            XCTAssertTrue(findEditor(host) === editor)
            XCTAssertEqual(editor.string, original)
            XCTAssertEqual(editor.selectedRange(), selection)
            let latin = try XCTUnwrap(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(latin.fontName, family.nsFont(size: latin.pointSize).fontName)
            let chinese = try XCTUnwrap(editor.textStorage?.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(chinese.familyName, family.cjkFamily)
        }
        editor.setSelectedRange(NSRange(location: (original as NSString).length, length: 0))
        editor.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        host.rootView = NativeEditor(workspace: workspace, font: .serif)
        settle(host)
        XCTAssertTrue(editor.hasMarkedText())
        editor.insertText("中文", replacementRange: editor.markedRange())
        editor.unmarkText()
        settle(host)
        editor.undoManager?.beginUndoGrouping()
        editor.insertText("X", replacementRange: editor.selectedRange())
        editor.undoManager?.endUndoGrouping()
        host.rootView = NativeEditor(workspace: workspace, font: .sans)
        settle(host)
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, original + "中文")
        try workspace.save()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("字体验证.md"), encoding: .utf8), original + "中文")
    }

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
        for _ in 0..<3 {
            withAnimation(Motion.panel) { workspace.focus = true }
            settle(host)
            withAnimation(Motion.panel) { workspace.focus = false }
            settle(host)
        }
        XCTAssertTrue(editor.hasMarkedText(), "Reversing focus motion must retain the active composition")
        XCTAssertTrue(findEditor(host) === editor)
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

    func testGlassShaderBuildsNativePipelineOnAvailableDevice() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device on this machine") }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "Glass", withExtension: "metal", subdirectory: "Shaders"))
        let library = try device.makeLibrary(source: String(contentsOf: source, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "glassVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "glassFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        _ = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func testTypingKeepsCaretTravelThroughNativeLayoutAndRestyling() throws {
        try assertTypingTravel(marked: nil, committed: "d")
        try assertTypingTravel(marked: "zhong", committed: "中文输入")
    }

    private func assertTypingTravel(marked: String?, committed: String) throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "输入动画")
        workspace.edit("连续输入 abc")
        let host = NSHostingView(rootView: NativeEditor(workspace: workspace))
        // XCTest's process cannot reliably activate. Substitute only the focus gate;
        // all text input, TextKit layout and layer animation remain the production path.
        let window = CaretAnimationTestWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let editor = try XCTUnwrap(findEditor(host) as? NoteTextView)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        settle(host)
        editor.updateInsertionCaret(animated: false)
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.18))
        if let marked {
            editor.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            CATransaction.flush()
            let preedit = try XCTUnwrap(editor.insertionCaret.layer.animation(forKey: "travel") as? CABasicAnimation, "Chinese preedit typing must animate before candidate confirmation")
            let preeditTarget = try XCTUnwrap(preedit.toValue as? NSValue).pointValue
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
            XCTAssertGreaterThan(abs(try XCTUnwrap(editor.insertionCaret.layer.presentation()).position.x - preeditTarget.x), 0.1)
            // Some IMEs select the whole candidate inside their marked range.
            editor.setMarkedText("你好", selectedRange: NSRange(location: 0, length: 2), replacementRange: editor.markedRange())
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertNotNil(editor.insertionCaret.rect, "An IME candidate selection must not hide the visual insertion caret")
            XCTAssertNotNil(editor.insertionCaret.layer.animation(forKey: "travel"))
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        }
        editor.insertText(committed, replacementRange: marked == nil ? editor.selectedRange() : editor.markedRange())
        editor.unmarkText()
        editor.coordinator?.style()
        host.layoutSubtreeIfNeeded()
        CATransaction.flush()
        let animation = try XCTUnwrap(editor.insertionCaret.layer.animation(forKey: "travel") as? CABasicAnimation, "Typing must leave a live movement animation after TextKit layout and restyling")
        let from = try XCTUnwrap(animation.fromValue as? NSValue).pointValue
        let to = try XCTUnwrap(animation.toValue as? NSValue).pointValue
        XCTAssertNotEqual(from, to, "A movement from the target back to itself is invisible")
        XCTAssertTrue(from.x.isFinite)
        RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        let sample = try XCTUnwrap(editor.insertionCaret.layer.presentation()).position
        XCTAssertGreaterThan(abs(sample.x - to.x), 0.1, "During typing the displayed caret must still be moving toward the committed text")
    }

    func testCaretGeometryNavigationCompositionAndListExit() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "光标验证")
        workspace.edit("# 标题\n\n中文 English 😀 混排\n\n- 项目\n- ")
        let host = NSHostingView(rootView: NativeEditor(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let editor = try XCTUnwrap(findEditor(host) as? NoteTextView)
        window.makeFirstResponder(editor)
        let text = editor.string as NSString
        for position in [0, text.range(of: "中文").location, text.range(of: "English").location, text.range(of: "😀").location, text.length] {
            editor.setSelectedRange(NSRange(location: position, length: 0))
            settle(host)
            let caret = try XCTUnwrap(editor.insertionCaretRect())
            let native = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            let local = editor.convert(window.convertFromScreen(native), from: nil)
            XCTAssertEqual(caret.minX, local.minX, accuracy: 0.6, "AppKit owns horizontal positioning")
            let font = position < text.length ? editor.textStorage?.attribute(.font, at: position, effectiveRange: nil) as? NSFont : editor.typingAttributes[.font] as? NSFont
            let metrics = try XCTUnwrap(font)
            XCTAssertEqual(caret.height, min(metrics.ascender - metrics.descender, metrics.pointSize + 2), accuracy: 0.6, "Caret must exclude extra line spacing and excess accent room")
            if position < text.length {
                let lm = try XCTUnwrap(editor.layoutManager)
                let glyph = lm.glyphIndexForCharacter(at: position)
                let baseline = editor.textContainerOrigin.y + lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + lm.location(forGlyphAt: glyph).y
                XCTAssertEqual(caret.midY, baseline - (metrics.ascender + metrics.descender) / 2, accuracy: 0.6)
            }
            XCTAssertTrue(caret.minY.isFinite)
            XCTAssertEqual(caret.width, 2)
            XCTAssertGreaterThan(caret.height, 10)
        }
        // Moving in both directions must keep AppKit's composed-character selection semantics.
        editor.setSelectedRange(NSRange(location: text.range(of: "😀").location, length: 0))
        let beforeEmoji = editor.selectedRange().location
        editor.moveRight(nil)
        XCTAssertEqual(editor.selectedRange().location, beforeEmoji + 2)
        editor.moveLeft(nil)
        XCTAssertEqual(editor.selectedRange().location, beforeEmoji)
        editor.setSelectedRange(NSRange(location: text.range(of: "中文").location, length: 2))
        editor.updateInsertionCaret(animated: true)
        XCTAssertNil(editor.insertionCaret.rect, "A selection hides the insertion point")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertNewline(nil)
        settle(host)
        XCTAssertTrue(editor.string.hasSuffix("- 项目\n\n"))
        let exited = editor.string
        editor.insertText("- ", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(editor.string, exited, "Ignore an IME's immediate list-marker echo")
        editor.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        settle(host)
        XCTAssertTrue(editor.hasMarkedText())
        editor.insertText("中文输入", replacementRange: editor.markedRange())
        editor.unmarkText()
        settle(host)
        XCTAssertTrue(editor.string.hasSuffix("中文输入"))
        let emptyLineCaret = try XCTUnwrap(editor.insertionCaretRect())
        XCTAssertTrue(emptyLineCaret.minY.isFinite)
        try workspace.save()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("光标验证.md"), encoding: .utf8), editor.string)
        editor.selectAll(nil)
        editor.insertText("", replacementRange: editor.selectedRange())
        settle(host)
        XCTAssertNotNil(editor.insertionCaretRect(), "An empty note still has an insertion point")
        editor.insertText(String(repeating: "中文 English 😀 ", count: 30) + "\nمرحبا بالعالم\n", replacementRange: editor.selectedRange())
        settle(host)
        for offset in [80, (editor.string as NSString).length - 3, (editor.string as NSString).length] {
            editor.setSelectedRange(NSRange(location: offset, length: 0))
            settle(host)
            let r = try XCTUnwrap(editor.insertionCaretRect())
            let native = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            let local = editor.convert(window.convertFromScreen(native), from: nil)
            XCTAssertEqual(r.minX, local.minX, accuracy: 0.6)
            XCTAssertTrue(r.minY.isFinite)
        }

    }

    func testTextSelectionHugsSelectedTextInsteadOfThePage() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "选区验证")
        let long = String(repeating: "这是一段需要换行的正文。", count: 9)
        workspace.edit("开头\n\n\(long)\n\n短行\n\n\n\n---\n\n末段文字\n")
        let host = NSHostingView(rootView: NativeEditor(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let editor = try XCTUnwrap(findEditor(host) as? NoteTextView)
        window.makeFirstResponder(editor)
        let text = editor.string as NSString
        let start = text.range(of: long).location + 3
        let end = text.range(of: "末段文字").location + 2
        editor.setSelectedRange(NSRange(location: start, length: end - start))
        settle(host)

        for source in [false, true] {
            workspace.source = source
            settle(host)
            editor.setSelectedRange(NSRange(location: start, length: end - start))
            settle(host)
            let mode = source ? "source" : "styled"
            let rects = editor.selectionHighlightRects()
            XCTAssertFalse(rects.isEmpty, mode)
            let tc = try XCTUnwrap(editor.textContainer)
            let column = (editor.textContainerOrigin.x, editor.textContainerOrigin.x + tc.size.width)
            for r in rects {
                XCTAssertGreaterThanOrEqual(r.minX, column.0 - 0.5, "\(mode): never spills into the page margin")
                XCTAssertLessThanOrEqual(r.maxX, column.1 + 0.5, "\(mode): never spills into the page margin")
            }
            func local(_ range: NSRange) -> CGRect {
                editor.convert(window.convertFromScreen(editor.firstRect(forCharacterRange: range, actualRange: nil)), from: nil)
            }
            let font = try XCTUnwrap(editor.textStorage?.attribute(.font, at: text.range(of: "短行").location, effectiveRange: nil) as? NSFont)
            let short = local(text.range(of: "短行"))
            let shortRect = try XCTUnwrap(rects.first { $0.contains(CGPoint(x: short.midX, y: short.midY)) }, "\(mode): the short line is highlighted")
            XCTAssertLessThanOrEqual(shortRect.maxX, short.maxX + font.pointSize * 0.5 + 1, "\(mode): a short line's highlight stops at its last character")
            XCTAssertEqual(shortRect.minX, short.minX, accuracy: 1, "\(mode): and starts at its first")
            let lm = try XCTUnwrap(editor.layoutManager)
            let shortLine = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: text.range(of: "短行").location), effectiveRange: nil)
                .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
            XCTAssertTrue(shortLine.contains(shortRect), "\(mode): a line's highlight stays inside its line, which AppKit redraws")

            // The wrapped paragraph is one unbroken band; the gap after it stays blank.
            let paragraph = rects.filter { $0.maxY <= shortRect.minY && $0.width > font.pointSize * 2 }.sorted { $0.minY < $1.minY }
            XCTAssertGreaterThanOrEqual(paragraph.count, 2, "\(mode): the long paragraph wraps")
            for (a, b) in zip(paragraph, paragraph.dropFirst()) {
                XCTAssertEqual(b.minY, a.maxY, accuracy: 0.5, "\(mode): lines of one paragraph join without stripes")
            }
            let lastLine = try XCTUnwrap(paragraph.last)
            XCTAssertGreaterThan(shortRect.minY - lastLine.maxY, 4, "\(mode): spacing between paragraphs is not highlighted")
            let gapMid = CGPoint(x: (column.0 + column.1) / 2, y: (shortRect.minY + lastLine.maxY) / 2)
            XCTAssertFalse(rects.contains { $0.contains(gapMid) }, "\(mode): spacing between paragraphs is not highlighted")

            // Selected empty lines show a narrow marker, not a full-width bar.
            let markers = rects.filter { $0.minY > shortRect.maxY && $0.width <= font.pointSize * 0.5 + 1 }
            XCTAssertFalse(markers.isEmpty, "\(mode): selected empty lines show a marker")
            for m in markers { XCTAssertEqual(m.minX, short.minX, accuracy: 1, "\(mode): the marker sits where the line starts") }
            XCTAssertFalse(rects.contains { $0.width > tc.size.width - 1 }, "\(mode): no full-width bars")
        }

        // In styled mode the rule is a block: only a slim box around the drawn line is tinted.
        workspace.source = false
        settle(host)
        editor.setSelectedRange(NSRange(location: start, length: end - start))
        settle(host)
        let rules = editor.selectionHighlightRects().filter { $0.height < 20 && $0.width > 200 }
        XCTAssertEqual(rules.count, 1, "The rule is tinted as one slim box")
        let lm = try XCTUnwrap(editor.layoutManager)
        let ruleGlyph = lm.glyphIndexForCharacter(at: text.range(of: "---").location + 3)
        let ruleLine = lm.lineFragmentRect(forGlyphAt: ruleGlyph, effectiveRange: nil).offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        if let rule = rules.first {
            XCTAssertLessThan(rule.height, ruleLine.height, "Not the rule's whole line")
            XCTAssertTrue(ruleLine.contains(CGPoint(x: rule.midX, y: rule.midY)))
        }
    }

    func testReturnAtBottomOfLongNoteKeepsInsertionVisibleAndUndoable() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace()
        try workspace.open(root)
        try workspace.createNote(title: "滚动验证")
        workspace.edit((1...200).map { "第\($0)行 中文内容" }.joined(separator: "\n"))
        let host = NSHostingView(rootView: NativeEditor(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 800, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let editor = try XCTUnwrap(findEditor(host) as? NoteTextView)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        settle(host)
        let initialY = editor.visibleRect.minY
        let original = editor.string
        editor.undoManager?.beginUndoGrouping()
        editor.insertNewline(nil)
        editor.insertText("继续写作", replacementRange: editor.selectedRange())
        editor.undoManager?.endUndoGrouping()
        settle(host)
        let caret = try XCTUnwrap(editor.insertionCaretRect())
        XCTAssertTrue(editor.visibleRect.insetBy(dx: -2, dy: -2).intersects(caret), "Return must keep the insertion point on screen")
        XCTAssertGreaterThanOrEqual(editor.visibleRect.minY, initialY - 2, "Editing must not jump up the document")
        editor.undoManager?.undo()
        settle(host)
        XCTAssertEqual(editor.string, original)
        editor.undoManager?.redo()
        settle(host)
        XCTAssertTrue(editor.string.hasSuffix("\n继续写作"))
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

/// Only compensates for a non-activating test runner; not used by the application.
@MainActor private final class CaretAnimationTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
