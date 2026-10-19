import AppKit
import XCTest
import SwiftUI
import NotesCore
@testable import NotesLite

/// Exiting lists, the blank line between a list and a paragraph, and the insertion caret on
/// empty lines — through the real AppKit editor and native text input, no editor mocks.
@MainActor final class ListEditingTests: XCTestCase {
    func testBlankLineBetweenListAndParagraphTakesNoRoom() throws {
        let note = try Note(self, "- 项目\n正文")
        let tight = try note.baseline(of: "正文")
        for text in ["- 项目\n\n正文", "1. 项目\n\n正文", "- [ ] 项目\n\n正文"] {
            try note.replace(with: text, caretAfter: "正文")
            XCTAssertEqual(try note.baseline(of: "正文"), tight, accuracy: 0.6, "A single blank line after a list adds no height: \(text)")
            XCTAssertEqual(note.editor.string, text, "Display only; the source keeps its blank line")
        }
        try note.caret(after: "项目\n")
        XCTAssertGreaterThan(try note.baseline(of: "正文") - tight, 20, "The blank line opens while the caret is on it")
        try note.replace(with: "- 项目\n\n\n正文", caretAfter: "正文")
        XCTAssertGreaterThan(try note.baseline(of: "正文") - tight, 20, "Two blank lines show as ordinary blank lines")
        try note.replace(with: "- 项目\n\n- 另一项", caretAfter: "另一项")
        let loose = try note.baseline(of: "另一项")
        try note.replace(with: "- 项目\n- 另一项", caretAfter: "另一项")
        XCTAssertGreaterThan(loose - (try note.baseline(of: "另一项")), 20, "A blank line between list items is untouched")
        try note.replace(with: "段落\n\n正文", caretAfter: "正文")
        let between = try note.baseline(of: "正文")
        try note.replace(with: "段落\n正文", caretAfter: "正文")
        XCTAssertGreaterThan(between - (try note.baseline(of: "正文")), 20, "A blank line between paragraphs is untouched")
    }

    func testExitingAListRemovesOnlyTheMarker() throws {
        for (list, kept) in [("- 项目\n- ", "- 项目\n"), ("1. 项目\n2. ", "1. 项目\n"), ("- [ ] 项目\n- [ ] ", "- [ ] 项目\n"), ("* 项目\n* ", "* 项目\n")] {
            let note = try Note(self, list)
            try note.caret(after: list)
            note.editor.insertNewline(nil)
            note.settle()
            XCTAssertEqual(note.editor.string, kept, "Only the marker goes; no new line")
            XCTAssertEqual(note.editor.selectedRange(), NSRange(location: (kept as NSString).length, length: 0))
            XCTAssertEqual(try note.savedText, kept, "Nothing typed: no blank line is added")
        }
    }

    func testTypingAfterExitingSeparatesTheParagraphWithoutMovingIt() throws {
        let note = try Note(self, "- 项目\n- ")
        try note.caret(after: "- 项目\n- ")
        note.editor.insertNewline(nil)
        note.settle()
        let line = try note.lineTop()
        note.editor.insertText("正", replacementRange: NSRange(location: NSNotFound, length: 0))
        note.editor.insertText("文", replacementRange: NSRange(location: NSNotFound, length: 0))
        note.settle()
        XCTAssertEqual(note.editor.string, "- 项目\n\n正文", "Markdown needs a blank line to end the list")
        XCTAssertEqual(note.editor.selectedRange(), NSRange(location: 8, length: 0))
        XCTAssertEqual(try note.lineTop(), line, accuracy: 0.6, "The line being typed stays where it was")
        XCTAssertEqual(try note.savedText, "- 项目\n\n正文")

        // Undo steps back to the exited list without ever showing the bare blank line.
        var states: [String] = []
        while note.editor.string != "- 项目\n- ", states.count < 6, note.editor.undoManager?.canUndo == true {
            note.editor.undoManager?.undo()
            note.settle()
            states.append(note.editor.string)
        }
        XCTAssertEqual(note.editor.string, "- 项目\n- ", "Undo returns to before the exit: \(states)")
        XCTAssertFalse(states.contains("- 项目\n\n"), "The separator never stands alone in history: \(states)")
    }

    func testCompositionAndPasteAlsoSeparateTheParagraph() throws {
        let note = try Note(self, "- 项目\n- ")
        try note.caret(after: "- 项目\n- ")
        note.editor.insertNewline(nil)
        note.settle()
        let line = try note.lineTop()
        note.editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        note.settle()
        XCTAssertEqual(note.editor.string, "- 项目\n\nzhong", "Composition starting counts as input")
        XCTAssertEqual(try note.lineTop(), line, accuracy: 0.6)
        note.editor.insertText("中", replacementRange: note.editor.markedRange())
        note.settle()
        XCTAssertEqual(note.editor.string, "- 项目\n\n中")

        let pasted = try Note(self, "- 项目\n- ")
        try pasted.caret(after: "- 项目\n- ")
        pasted.editor.insertNewline(nil)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("粘贴", forType: .string)
        pasted.editor.paste(nil)
        pasted.settle()
        XCTAssertEqual(pasted.editor.string, "- 项目\n\n粘贴")
    }

    func testTheSeparatorGoesAwayWhenTheLineIsAListAgainOrEmpty() throws {
        let note = try Note(self, "- 项目\n- ")
        try note.caret(after: "- 项目\n- ")
        note.editor.insertNewline(nil)
        note.editor.insertText("-", replacementRange: NSRange(location: NSNotFound, length: 0))
        note.settle()
        XCTAssertEqual(note.editor.string, "- 项目\n\n-", "A dash alone may start a paragraph")
        note.editor.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        note.settle()
        XCTAssertEqual(note.editor.string, "- 项目\n- ", "A complete marker joins the list above")
        XCTAssertEqual(note.editor.selectedRange(), NSRange(location: 7, length: 0))

        let emptied = try Note(self, "- 项目\n- ")
        try emptied.caret(after: "- 项目\n- ")
        emptied.editor.insertNewline(nil)
        emptied.settle()
        let line = try emptied.lineTop()
        emptied.editor.insertText("正", replacementRange: NSRange(location: NSNotFound, length: 0))
        emptied.settle()
        emptied.editor.deleteBackward(nil)
        emptied.settle()
        XCTAssertEqual(emptied.editor.string, "- 项目\n", "Back to just having exited")
        XCTAssertEqual(try emptied.lineTop(), line, accuracy: 0.6)
        emptied.editor.insertText("再", replacementRange: NSRange(location: NSNotFound, length: 0))
        emptied.settle()
        XCTAssertEqual(emptied.editor.string, "- 项目\n\n再", "Typing again separates again")
    }

    func testReturnUndoAndSwitchingNotesKeepTheSeparatorHonest() throws {
        let note = try Note(self, "- 项目\n- ")
        try note.caret(after: "- 项目\n- ")
        note.editor.insertNewline(nil)
        note.settle()
        note.editor.insertNewline(nil)
        note.settle()
        XCTAssertEqual(note.editor.string, "- 项目\n\n", "Return is a new line, not text that needs a separator")

        let undone = try Note(self, "- 项目\n- ")
        try undone.caret(after: "- 项目\n- ")
        undone.editor.insertNewline(nil)
        undone.settle()
        undone.editor.breakUndoCoalescing()
        undone.editor.insertText("正", replacementRange: NSRange(location: NSNotFound, length: 0))
        undone.settle()
        undone.editor.undoManager?.undo()
        undone.settle()
        XCTAssertEqual(undone.editor.string, "- 项目\n", "Undo takes the text and its separator together")
        undone.editor.insertText("再", replacementRange: NSRange(location: NSNotFound, length: 0))
        undone.settle()
        XCTAssertEqual(undone.editor.string, "- 项目\n\n再", "Typing after undo separates again")

        let switched = try Note(self, "- 项目\n- ")
        try switched.caret(after: "- 项目\n- ")
        switched.editor.insertNewline(nil)
        switched.editor.insertText("正", replacementRange: NSRange(location: NSNotFound, length: 0))
        switched.settle()
        try switched.workspace.createNote(title: "另一篇")
        switched.settle()
        let fresh = switched.editor.string
        switched.editor.insertText("新", replacementRange: NSRange(location: NSNotFound, length: 0))
        switched.settle()
        XCTAssertEqual(switched.editor.string, "新" + fresh, "Another note gets no stray blank line")
    }

    func testANestedEmptyItemStepsOutOneLevelTakingItsParentsMarker() throws {
        let cases = [
            ("- 父\n  - 子\n  - ", "- 父\n  - 子\n- "),
            ("1. 父\n2. 父二\n   1. 子\n   2. ", "1. 父\n2. 父二\n   1. 子\n3. "),
            ("1) 父\n   - 子\n   - ", "1) 父\n   - 子\n2) "),
            ("- [x] 父\n  - [ ] 子\n  - [ ] ", "- [x] 父\n  - [ ] 子\n- [ ] "),
            ("- 父\n  1. 子\n  2. ", "- 父\n  1. 子\n- "),
        ]
        for (list, stepped) in cases {
            let note = try Note(self, list)
            try note.caret(after: list)
            note.editor.insertNewline(nil)
            note.settle()
            XCTAssertEqual(note.editor.string, stepped, "One level out, with the parent's marker")
            XCTAssertEqual(note.editor.selectedRange(), NSRange(location: (stepped as NSString).length, length: 0))
        }

        let deep = try Note(self, "- 一\n  - 二\n    - 三\n    - ")
        try deep.caret(after: "    - ")
        deep.editor.insertNewline(nil)
        XCTAssertEqual(deep.editor.string, "- 一\n  - 二\n    - 三\n  - ")
        deep.editor.insertNewline(nil)
        XCTAssertEqual(deep.editor.string, "- 一\n  - 二\n    - 三\n- ")
        deep.editor.insertNewline(nil)
        XCTAssertEqual(deep.editor.string, "- 一\n  - 二\n    - 三\n", "At the outermost level the list ends")
        deep.editor.undoManager?.undo()
        deep.settle()
        XCTAssertEqual(deep.editor.string, "- 一\n  - 二\n    - 三\n    - ", "Undo, at the system's typing granularity, restores the nested item")

        let numbered = try Note(self, "1. 甲\n   1. 乙\n   2. \n2. 丙")
        try numbered.caret(after: "   2. ")
        numbered.editor.insertNewline(nil)
        XCTAssertEqual(numbered.editor.string, "1. 甲\n   1. 乙\n2. \n2. 丙", "Later items are not renumbered")
    }

    func testTheCaretOnAnEmptyLineSitsWhereTypingWillPutIt() throws {
        // Between paragraphs, at the end of the note, and just after exiting a list; typed in the
        // body face or composed. (A committed CJK character takes its own face and caret metrics.)
        for (text, marker) in [("段落\n\n后文", "段落\n"), ("段落\n", "段落\n"), ("- 项目\n- ", "- 项目\n- ")] {
            for compose in [false, true] {
                let note = try Note(self, text)
                try note.caret(after: marker)
                if text.hasPrefix("- ") { note.editor.insertNewline(nil); note.settle() }
                let empty = try XCTUnwrap(note.editor.insertionCaretRect())
                if compose {
                    note.editor.setMarkedText("zi", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                } else {
                    note.editor.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
                }
                note.settle()
                let typed = try XCTUnwrap(note.editor.insertionCaretRect())
                XCTAssertEqual(empty.midY, typed.midY, accuracy: 0.6, "No vertical jump: \(text) compose: \(compose)")
                XCTAssertEqual(empty.height, typed.height, accuracy: 0.6, "Same height: \(text) compose: \(compose)")
            }
        }
    }

    func testLeavingTheExitedLineEmptyAddsNothingAndCodeIsUntouched() throws {
        let note = try Note(self, "- 项目\n- \n\n后文")
        try note.caret(after: "- 项目\n- ")
        note.editor.insertNewline(nil)
        try note.caret(after: "后文")
        note.editor.insertText("！", replacementRange: NSRange(location: NSNotFound, length: 0))
        note.settle()
        XCTAssertEqual(note.editor.string, "- 项目\n\n\n后文！", "Typing elsewhere adds no separator")

        let code = try Note(self, "```\n- 项目\n- ")
        try code.caret(after: "- 项目\n- ")
        code.editor.insertNewline(nil)
        code.settle()
        XCTAssertEqual(code.editor.string, "```\n- 项目\n- \n", "Inside code Return is just a new line")
    }
}

/// One note open in a real window with the native editor focused.
@MainActor private final class Note {
    let root: URL
    let workspace = Workspace()
    let host: NSHostingView<NativeEditor>
    let window: NSWindow
    let editor: NoteTextView

    init(_ test: XCTestCase, _ text: String, title: String = "列表验证") throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try workspace.open(root)
        try workspace.createNote(title: title)
        workspace.edit(text)
        host = NSHostingView(rootView: NativeEditor(workspace: workspace))
        window = KeyTestWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        editor = try XCTUnwrap(Self.findEditor(host) as? NoteTextView)
        window.makeFirstResponder(editor)
        let root = root, window = window
        test.addTeardownBlock { @MainActor in
            window.orderOut(nil)
            try? FileManager.default.removeItem(at: root)
        }
    }

    func settle() {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        host.layoutSubtreeIfNeeded()
    }

    func replace(with text: String, caretAfter marker: String) throws {
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        try caret(after: marker)
    }

    func caret(after marker: String) throws {
        let r = (editor.string as NSString).range(of: marker, options: .backwards)
        XCTAssertNotEqual(r.location, NSNotFound)
        editor.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
        settle()
    }

    /// The baseline of the line showing the last occurrence of `marker`, in editor coordinates.
    func baseline(of marker: String) throws -> CGFloat {
        let r = (editor.string as NSString).range(of: marker, options: .backwards)
        XCTAssertNotEqual(r.location, NSNotFound)
        return try baseline(at: r.location)
    }

    func baseline(at location: Int) throws -> CGFloat {
        let lm = try XCTUnwrap(editor.layoutManager)
        lm.ensureLayout(for: try XCTUnwrap(editor.textContainer))
        let glyph = lm.glyphIndexForCharacter(at: location)
        return editor.textContainerOrigin.y + lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + lm.location(forGlyphAt: glyph).y
    }

    /// The top of the line the caret is on, in editor coordinates; for an empty last line too.
    func lineTop() throws -> CGFloat {
        let lm = try XCTUnwrap(editor.layoutManager)
        lm.ensureLayout(for: try XCTUnwrap(editor.textContainer))
        let location = editor.selectedRange().location
        let length = (editor.string as NSString).length
        if location == length, lm.extraLineFragmentTextContainer != nil {
            return editor.textContainerOrigin.y + lm.extraLineFragmentRect.minY
        }
        let glyph = lm.glyphIndexForCharacter(at: min(location, length - 1))
        return editor.textContainerOrigin.y + lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }

    var savedText: String {
        get throws {
            try workspace.save()
            return try String(contentsOf: root.appendingPathComponent("列表验证.md"), encoding: .utf8)
        }
    }

    private static func findEditor(_ root: NSView) -> NSTextView? {
        if let editor = root as? NSTextView, editor.accessibilityLabel() == "笔记正文" { return editor }
        return root.subviews.lazy.compactMap { findEditor($0) }.first
    }
}

/// Only compensates for a non-activating test runner; not used by the application.
@MainActor private final class KeyTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
