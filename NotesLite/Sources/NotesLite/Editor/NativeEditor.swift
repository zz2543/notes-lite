import AppKit
import QuartzCore
import NotesCore
import SwiftUI

/// A stable native editor instance. Layout/focus transitions never replace its document.
struct NativeEditor: NSViewRepresentable {
    let workspace: Workspace
    var font: EditorFont = .sans
    func makeCoordinator() -> Coordinator { Coordinator(workspace) }
    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NotesLayoutManager()
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 650, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false; container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let textView = NoteTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 600), textContainer: container)
        let c = context.coordinator
        textView.coordinator = c; textView.delegate = c; storage.delegate = c
        textView.setUpInsertionCaret()
        // The layout manager draws the selection, hugging the text; selected text keeps its colors.
        textView.selectedTextAttributes = [:]
        textView.isRichText = false; textView.importsGraphics = false; textView.allowsUndo = true
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero; textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.backgroundColor = Theme.NS.paper
        textView.textColor = Theme.NS.ink
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.setAccessibilityLabel("笔记正文")
        textView.registerForDraggedTypes([.fileURL, .png, .tiff])
        let scroll = NSScrollView()
        scroll.documentView = textView; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.backgroundColor = Theme.NS.paper; scroll.scrollerStyle = .overlay
        scroll.contentView.postsBoundsChangedNotifications = true
        c.textView = textView; c.scroll = scroll
        c.insertObserver = NotificationCenter.default.addObserver(forName: .init("NotesLite.insert"), object: nil, queue: .main) { [weak c] notification in
            guard let snippet = notification.object as? String else { return }
            MainActor.assumeIsolated {
                guard let tv = c?.textView else { return }
                tv.window?.makeFirstResponder(tv)
                tv.insertText("\n" + snippet + "\n", replacementRange: tv.selectedRange())
            }
        }
        c.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak c] _ in MainActor.assumeIsolated { c?.scheduleStyle(); c?.textView?.updateInsertionCaret(animated: false) } }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.sync(font: font) }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        if let observer = coordinator.insertObserver { NotificationCenter.default.removeObserver(observer) }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        let workspace: Workspace
        weak var textView: NoteTextView?
        weak var scroll: NSScrollView?
        var observer: NSObjectProtocol?
        var insertObserver: NSObjectProtocol?
        private var path: String?
        private var revision = -1
        private var styling = false
        private var scheduled = false
        private var source = false
        let styler = MarkdownStyler(style: EditorStyle(font: .sans, typewriter: false, dim: false, zen: false, width: 680))
        init(_ workspace: Workspace) {
            self.workspace = workspace
            super.init()
            styler.needsRestyle = { [weak self] in self?.scheduleStyle() }
            styler.resolveEmbed = { [weak workspace] target in workspace?.resolveFile(target) }
        }
        func sync(font: EditorFont) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            if path != workspace.current || revision != workspace.revision {
                path = workspace.current; revision = workspace.revision
                styling = true
                storage.setAttributedString(NSAttributedString(string: workspace.text, attributes: styler.baseAttributes()))
                tv.insertionCaret.hide()
                tv.undoManager?.removeAllActions()
                tv.forgetListGap()
                tv.setSelectedRange(NSRange(location: 0, length: 0)); tv.scroll(.zero)
                styling = false
                styler.newDocument()
            }
            if source != workspace.source || styler.style.font != font {
                source = workspace.source
                styler.setStyle(EditorStyle(font: font, typewriter: false, dim: false, zen: false, width: 680, plain: source))
            }
            tv.layoutColumn()
            style()
        }
        func textDidChange(_ notification: Notification) {
            guard !styling, let tv = textView else { return }
            workspace.edit(tv.string)
            scheduleStyle()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            if !styling {
                textView?.updateInsertionCaret(animated: true)
                scheduleStyle()
            }
        }
        func textStorage(_ storage: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
            if !styling, mask.contains(.editedCharacters) { styler.noteEdit(range, delta: delta) }
        }
        func scheduleStyle() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in self?.scheduled = false; self?.style() }
        }
        func style() {
            guard !styling, let tv = textView, !tv.hasMarkedText(), let storage = tv.textStorage, let layout = tv.layoutManager, let container = tv.textContainer else { return }
            styling = true
            defer {
                styling = false
                tv.updateInsertionCaret(animated: false)
            }
            styler.setContainerWidth(container.size.width)
            styler.dark = tv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            styler.listGap = tv.listGap
            let glyphs = layout.glyphRange(forBoundingRect: tv.visibleRect.offsetBy(dx: -tv.textContainerOrigin.x, dy: -tv.textContainerOrigin.y), in: container)
            if glyphs.location < layout.numberOfGlyphs { styler.priorityLine = styler.lineIndex(at: layout.characterIndexForGlyph(at: glyphs.location)) }
            let selection = tv.selectedRange()
            let origin = scroll?.contentView.bounds.origin ?? .zero
            let focused = tv.window?.firstResponder === tv
            var ranges: [NSRange] = []
            tv.holdingHeight { ranges = styler.restyle(storage, caret: focused ? selection.location : nil) }
            for range in ranges {
                layout.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
                layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                layout.invalidateDisplay(forCharacterRange: range)
            }
            tv.typingAttributes = styler.baseAttributes()
            if tv.selectedRange() != selection { tv.setSelectedRange(selection) }
            if let scroll, scroll.contentView.bounds.origin != origin { scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView) }
            if styler.pending { scheduleStyle() }
        }
        func openLink(_ target: String) {
            performNoteAction(workspace) {
                if target.hasPrefix("http://") || target.hasPrefix("https://") {
                    if let u = URL(string: target) { NSWorkspace.shared.open(u) }
                } else if let file = workspace.resolveFile(target), file.pathExtension.lowercased() != "md" {
                    NSWorkspace.shared.open(file)
                } else {
                    try workspace.followLink(target)
                }
            }
        }
        func handleClick(_ point: NSPoint, event: NSEvent) -> Bool {
            guard let tv = textView, let lm = tv.layoutManager as? NotesLayoutManager, let tc = tv.textContainer, let storage = tv.textStorage else { return false }
            if event.clickCount == 2 {
                if let hit = lm.embedHitRects.first(where: { $0.0.contains(point) }), let url = hit.1.url { NSWorkspace.shared.open(url); return true }
                if let hit = lm.blockHitRects.first(where: { $0.rect.contains(point) }) {
                    tv.setSelectedRange(NSRange(location: hit.start, length: 0)); tv.window?.makeFirstResponder(tv); scheduleStyle(); return true
                }
            }
            if let hit = lm.taskHitRects.first(where: { $0.0.contains(point) }) {
                let range = (tv.string as NSString).lineRange(for: NSRange(location: hit.1, length: 0))
                let line = (tv.string as NSString).substring(with: range)
                tv.insertText(Markdown.toggleTask(line), replacementRange: range)
                return true
            }
            // Command-click follows links; an ordinary click always remains an editing action.
            guard event.modifierFlags.contains(.command) else { return false }
            let local = NSPoint(x: point.x - tv.textContainerOrigin.x, y: point.y - tv.textContainerOrigin.y)
            let glyph = lm.glyphIndex(for: local, in: tc)
            guard glyph < lm.numberOfGlyphs else { return false }
            let index = lm.characterIndexForGlyph(at: glyph)
            guard index < storage.length else { return false }
            if let target = storage.attribute(.notesliteWikiLink, at: index, effectiveRange: nil) as? String ?? storage.attribute(.notesliteURL, at: index, effectiveRange: nil) as? String {
                openLink(target); return true
            }
            return false
        }
    }
}

final class NoteTextView: NSTextView {
    weak var coordinator: NativeEditor.Coordinator?
    private var lastWidth: CGFloat = 0
    let insertionCaret = InsertionCaret()
    private(set) var caretInputDepth = 0
    private var windowObservers: [NSObjectProtocol] = []
    private var heightHeld = false
    private var fitScheduled = false
    private var listExitCaret: Int?
    func forgetListGap() { listGap = nil }
    /// The blank line (分隔空行) this editor put in to end a list, while the line below it is being
    /// written; taken out again if that line ends up empty or a list item.
    private(set) var listGap: Int?
    private var editingListGap = false

    func setUpInsertionCaret() {
        wantsLayer = true
        insertionPointColor = .clear
        layer?.addSublayer(insertionCaret.layer)
    }
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
        // The selection follows the accent color.
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        })
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.needsDisplay = true; self?.updateInsertionCaret(animated: false) }
                })
            }
        }
        updateInsertionCaret(animated: false)
    }
    deinit { windowObservers.forEach { NotificationCenter.default.removeObserver($0) } }
    override func layout() {
        super.layout()
        // macOS also creates an insertion-indicator subview, independent of drawInsertionPoint.
        for indicator in subviews.compactMap({ $0 as? NSTextInsertionIndicator }) { indicator.displayMode = .hidden }
        updateInsertionCaret(animated: false)
    }
    func holdingHeight(_ edit: () -> Void) {
        heightHeld = true
        edit()
        releaseHeightSoon()
    }
    private func releaseHeightSoon() {
        guard !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fitScheduled = false
            heightHeld = false
            guard let lm = layoutManager, let tc = textContainer else { return }
            lm.ensureLayout(forBoundingRect: visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y), in: tc)
            let contentHeight = max(lm.usedRect(for: tc).maxY, lm.extraLineFragmentRect.maxY)
            setFrameSize(NSSize(width: frame.width, height: max(minSize.height, contentHeight + textContainerInset.height * 2)))
            updateInsertionCaret(animated: false)
        }
    }
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let allowed = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if allowed { heightHeld = true }
        return allowed
    }
    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        let allowed = super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        if allowed { heightHeld = true }
        return allowed
    }
    override func didChangeText() {
        super.didChangeText()
        closeListGapIfNeeded()
        if heightHeld { releaseHeightSoon() }
        updateInsertionCaret(animated: true)
    }
    override func keyDown(with event: NSEvent) {
        listExitCaret = nil
        super.keyDown(with: event)
    }
    override func insertText(_ text: Any, replacementRange: NSRange) {
        if let caret = listExitCaret {
            listExitCaret = nil
            let incoming = Self.string(text)
            if replacementRange.location == NSNotFound, selectedRange() == NSRange(location: caret, length: 0),
               Markdown.blockType(incoming).isList, Markdown.prefixLength(incoming) == (incoming as NSString).length { return }
        }
        caretInputDepth += 1
        defer {
            caretInputDepth -= 1
            updateInsertionCaret(animated: true)
        }
        var replacementRange = replacementRange
        openListGap(for: text, &replacementRange)
        super.insertText(text, replacementRange: replacementRange)
    }
    override func setMarkedText(_ text: Any, selectedRange: NSRange, replacementRange: NSRange) {
        caretInputDepth += 1
        defer {
            caretInputDepth -= 1
            updateInsertionCaret(animated: true)
        }
        var replacementRange = replacementRange
        openListGap(for: text, &replacementRange)
        super.setMarkedText(text, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // The blank line is kept or taken out only while the caret stays on the line below it.
        guard !editingListGap, let gap = listGap else { return }
        let ns = string as NSString
        let sel = selectedRange()
        if sel.length > 0 || ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0)).location != gap + 1 { listGap = nil }
    }
    private static func string(_ text: Any) -> String { (text as? NSAttributedString)?.string ?? text as? String ?? "" }
    /// Text is about to start on an empty line right below a list item: Markdown needs a blank line
    /// (分隔空行) above it to end the list, or the text would continue the item.
    private func openListGap(for text: Any, _ replacementRange: inout NSRange) {
        guard listGap == nil, !hasMarkedText(), let coordinator, selectedRange().length == 0,
              !Self.string(text).allSatisfy(\.isNewline) else { return }
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        guard line.location > 0, ns.substring(with: line).trimmingCharacters(in: .newlines).isEmpty else { return }
        let above = ns.lineRange(for: NSRange(location: line.location - 1, length: 0))
        guard Markdown.blockType(ns.substring(with: above).trimmingCharacters(in: .newlines)).isList,
              !coordinator.styler.isCode(line: coordinator.styler.lineIndex(at: above.location)) else { return }
        replaceListGap(NSRange(location: line.location, length: 0), with: "\n")
        listGap = line.location
        // Styling waits while text is composed; the blank line must take no room before that.
        coordinator.style()
        if replacementRange.location != NSNotFound, replacementRange.location >= line.location { replacementRange.location += 1 }
    }
    /// After an edit: the blank line goes again once the line below it is empty or a list item.
    private func closeListGapIfNeeded() {
        guard !editingListGap, let gap = listGap, !hasMarkedText() else { return }
        // Undo and redo replay recorded edits, the blank line's included.
        if undoManager?.isUndoing == true || undoManager?.isRedoing == true { listGap = nil; return }
        let ns = string as NSString
        guard gap + 1 <= ns.length else { listGap = nil; return }
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: gap + 1, length: 0))).trimmingCharacters(in: .newlines)
        guard line.isEmpty || (Markdown.blockType(line).isList && Markdown.prefixLength(line) > 0) else { return }
        replaceListGap(NSRange(location: gap, length: 1), with: "")
        listGap = nil
    }
    /// An undoable edit that keeps the caret on its text.
    private func replaceListGap(_ range: NSRange, with text: String) {
        editingListGap = true
        defer { editingListGap = false }
        let sel = selectedRange()
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        let delta = (text as NSString).length - range.length
        setSelectedRange(NSRange(location: sel.location >= range.location ? sel.location + delta : sel.location, length: sel.length))
    }
    override func unmarkText() {
        caretInputDepth += 1
        defer {
            caretInputDepth -= 1
            updateInsertionCaret(animated: true)
        }
        super.unmarkText()
    }
    func layoutColumn() {
        guard let container = textContainer else { return }
        let inset = max(16, (bounds.width - 740) / 2)
        textContainerInset = NSSize(width: inset, height: 48)
        container.size = NSSize(width: max(120, bounds.width - inset * 2), height: .greatestFiniteMagnitude)
    }
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if heightHeld { size.height = max(size.height, frame.height) }
        let widthChanged = abs(size.width - lastWidth) > 0.5
        var anchor: (index: Int, offset: CGFloat)?
        if widthChanged, let lm = layoutManager, let container = textContainer, lm.numberOfGlyphs > 0, let clip = enclosingScrollView?.contentView {
            let location = NSPoint(x: 0, y: max(0,clip.bounds.minY-textContainerOrigin.y))
            let glyph = lm.glyphIndex(for: location, in: container)
            if glyph < lm.numberOfGlyphs {
                let rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                anchor = (lm.characterIndexForGlyph(at: glyph), clip.bounds.minY-(rect.minY+textContainerOrigin.y))
            }
        }
        super.setFrameSize(size)
        if widthChanged {
            lastWidth = size.width; layoutColumn()
            if let anchor, anchor.index < (string as NSString).length, let lm = layoutManager, let container = textContainer, let scroll = enclosingScrollView {
                lm.ensureLayout(forCharacterRange: NSRange(location: anchor.index, length: 1))
                let glyph = lm.glyphIndexForCharacter(at: anchor.index)
                if glyph < lm.numberOfGlyphs {
                    let rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0,rect.minY+textContainerOrigin.y+anchor.offset)))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                _ = container
            }
            coordinator?.scheduleStyle()
        }
    }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); coordinator?.scheduleStyle(); needsDisplay = true; updateInsertionCaret(animated: false); return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); coordinator?.scheduleStyle(); needsDisplay = true; updateInsertionCaret(animated: false); return result }
    /// Where the selection is highlighted, in view coordinates.
    func selectionHighlightRects() -> [CGRect] {
        guard let lm = layoutManager as? NotesLayoutManager else { return [] }
        return selectedRanges.flatMap { lm.selectionShapes(for: $0.rangeValue, origin: textContainerOrigin).map(\.rect) }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); coordinator?.styler.reset(); coordinator?.scheduleStyle(); updateInsertionCaret(animated: false) }
    override func mouseDown(with event: NSEvent) {
        listExitCaret = nil
        if coordinator?.handleClick(convert(event.locationInWindow, from: nil), event: event) == true { return }
        super.mouseDown(with: event)
    }
    override func paste(_ sender: Any?) {
        listExitCaret = nil
        if importPasteboard(.general) { return }
        if let pasted = NSPasteboard.general.string(forType: .string) {
            var none = NSRange(location: NSNotFound, length: 0)
            openListGap(for: pasted, &none)
        }
        super.paste(sender)
        closeListGapIfNeeded()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        return importPasteboard(sender.draggingPasteboard) || super.performDragOperation(sender)
    }
    private func importPasteboard(_ board: NSPasteboard) -> Bool {
        guard let coordinator else { return false }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls {
                do { let snippet = try coordinator.workspace.importAttachment(from: url); insertText("\n" + snippet + "\n", replacementRange: selectedRange()) }
                catch { coordinator.workspace.error = error.localizedDescription }
            }
            return true
        }
        if let data = board.data(forType: .png) ?? board.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
            do {
                let snippet = try coordinator.workspace.importAttachment(data: png, name: "图片-" + String(UUID().uuidString.prefix(8)) + ".png")
                insertText("\n" + snippet + "\n", replacementRange: selectedRange())
            } catch { coordinator.workspace.error = error.localizedDescription }
            return true
        }
        return false
    }
    /// The nearest list item above `location` indented less than `line`; nil at the outermost level.
    private func parentItem(of line: String, above location: Int) -> String? {
        func indent(_ s: String) -> Int { s.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }
        let own = indent(line)
        guard own > 0 else { return nil }
        let ns = string as NSString
        var end = location
        while end > 0 {
            let r = ns.lineRange(for: NSRange(location: end - 1, length: 0))
            end = r.location
            let text = ns.substring(with: r).trimmingCharacters(in: .newlines)
            if text.allSatisfy(\.isWhitespace) { continue }
            let depth = indent(text)
            if depth < own { return Markdown.blockType(text).isList ? text : nil }
        }
        return nil
    }
    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let coordinator else { super.insertNewline(sender); return }
        let range = selectedRange()
        let lineRange = (string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        let line = (string as NSString).substring(with: lineRange).trimmingCharacters(in: .newlines)
        let lineIndex = coordinator.styler.lineIndex(at: range.location)
        guard !coordinator.styler.isCode(line: lineIndex), let continuation = Markdown.continuation(for: line) else { super.insertNewline(sender); return }
        if continuation.exit, let parent = parentItem(of: line, above: lineRange.location), let next = Markdown.continuation(for: parent), !next.exit {
            // A nested empty item steps out one level and continues its parent's list.
            insertText(next.prefix, replacementRange: NSRange(location: lineRange.location, length: NSMaxRange(range) - lineRange.location))
        } else if continuation.exit {
            // Only the marker goes; the blank line that ends the list waits for text (`openListGap`).
            insertText("", replacementRange: NSRange(location: lineRange.location, length: NSMaxRange(range) - lineRange.location))
            listExitCaret = selectedRange().location
        } else { insertText("\n" + continuation.prefix, replacementRange: range) }
    }
}
