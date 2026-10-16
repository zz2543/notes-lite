import AppKit
import NotesCore
import SwiftUI

/// A stable native editor instance. Layout/focus transitions never replace its document.
struct NativeEditor: NSViewRepresentable {
    let workspace: Workspace
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
        c.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak c] _ in MainActor.assumeIsolated { c?.scheduleStyle() } }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.sync() }
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
        func sync() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            if path != workspace.current || revision != workspace.revision {
                path = workspace.current; revision = workspace.revision
                styling = true
                storage.setAttributedString(NSAttributedString(string: workspace.text, attributes: styler.baseAttributes()))
                tv.undoManager?.removeAllActions()
                tv.setSelectedRange(NSRange(location: 0, length: 0)); tv.scroll(.zero)
                styling = false
                styler.newDocument()
            }
            if source != workspace.source {
                source = workspace.source
                styler.setStyle(EditorStyle(font: .sans, typewriter: false, dim: false, zen: false, width: 680, plain: source))
            }
            tv.layoutColumn()
            style()
        }
        func textDidChange(_ notification: Notification) {
            guard !styling, let tv = textView else { return }
            workspace.edit(tv.string)
            scheduleStyle()
        }
        func textViewDidChangeSelection(_ notification: Notification) { if !styling { scheduleStyle() } }
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
            defer { styling = false }
            styler.setContainerWidth(container.size.width)
            styler.dark = tv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let glyphs = layout.glyphRange(forBoundingRect: tv.visibleRect.offsetBy(dx: -tv.textContainerOrigin.x, dy: -tv.textContainerOrigin.y), in: container)
            if glyphs.location < layout.numberOfGlyphs { styler.priorityLine = styler.lineIndex(at: layout.characterIndexForGlyph(at: glyphs.location)) }
            let selection = tv.selectedRange()
            let origin = scroll?.contentView.bounds.origin ?? .zero
            let focused = tv.window?.firstResponder === tv
            let ranges = styler.restyle(storage, caret: focused ? selection.location : nil)
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
    func layoutColumn() {
        guard let container = textContainer else { return }
        let inset = max(16, (bounds.width - 740) / 2)
        textContainerInset = NSSize(width: inset, height: 48)
        container.size = NSSize(width: max(120, bounds.width - inset * 2), height: .greatestFiniteMagnitude)
    }
    override func setFrameSize(_ size: NSSize) {
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
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); coordinator?.scheduleStyle(); return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); coordinator?.scheduleStyle(); return result }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); coordinator?.styler.reset(); coordinator?.scheduleStyle() }
    override func mouseDown(with event: NSEvent) {
        if coordinator?.handleClick(convert(event.locationInWindow, from: nil), event: event) == true { return }
        super.mouseDown(with: event)
    }
    override func paste(_ sender: Any?) {
        if importPasteboard(.general) { return }
        super.paste(sender)
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
    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let coordinator else { super.insertNewline(sender); return }
        let range = selectedRange()
        let lineRange = (string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        let line = (string as NSString).substring(with: lineRange).trimmingCharacters(in: .newlines)
        let lineIndex = coordinator.styler.lineIndex(at: range.location)
        guard !coordinator.styler.isCode(line: lineIndex), let continuation = Markdown.continuation(for: line) else { super.insertNewline(sender); return }
        if continuation.exit {
            insertText("\n", replacementRange: NSRange(location: lineRange.location, length: range.location - lineRange.location))
        } else { insertText("\n" + continuation.prefix, replacementRange: range) }
    }
}
