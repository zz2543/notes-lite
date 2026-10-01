import AppKit
import TwainCore
import SwiftUI

// MARK: - SwiftUI bridge

struct EditorView: NSViewRepresentable {
    @Bindable var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    /// The page gives way to a space or a desk: take the typed text out while the view still has it.
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        _ = coordinator.model.editor.editorText
    }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        storage.delegate = context.coordinator
        let lm = TwainLayoutManager()
        // Only what is visible gets laid out: an edit no longer re-typesets the rest of the note.
        lm.allowsNonContiguousLayout = true
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        // Sized by the text view (updateInsets), which may keep a rail free on the right.
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        lm.addTextContainer(container)

        let tv = TwainTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.drawsBackground = true
        tv.backgroundColor = Theme.NS.paper
        tv.setUpCaret()
        tv.linkTextAttributes = [:]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.registerForDraggedTypes([.fileURL] + Coordinator.imageTypes)

        let scroll = EditorScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.NS.paper
        scroll.scrollerStyle = .overlay
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll
        scroll.onTile = { [weak coordinator = context.coordinator] in coordinator?.visibleSizeChanged() }
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) {
            [weak coordinator = context.coordinator] _ in MainActor.assumeIsolated { coordinator?.scrolled() }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        let style = EditorStyle(font: model.prefs.font, typewriter: model.prefs.typewriter, dim: model.prefs.dim, zen: model.chrome.zen, width: model.prefs.editorWidth,
                                plain: model.activeNote?.isHTML == true || model.editor.oversized,
                                rail: model.visibleAnnotations.isEmpty || model.chrome.zen ? 0 : AnnotationRail.width)
        c.sync(version: model.editor.editorVersion, rel: model.editor.activeRel, text: model.editorDisplayText, style: style,
               ghost: model.editor.ghost, readOnly: model.editorReadOnly, focus: model.editor.focusRequest)
        // Annotations and the selected one change what the rail and highlights show.
        _ = (model.editor.annotations, model.editor.selectedAnnotation)
        c.scheduleRail()
    }

    // MARK: Coordinator

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        let model: AppModel
        weak var textView: TwainTextView?
        weak var scrollView: NSScrollView?
        private var version = -1
        private var style: EditorStyle?
        private var focusToken = -1
        private var restyling = false
        /// Set while the whole text is being replaced: the selection passes through the end of the
        /// new text on the way, and centering on it would lay out the entire note.
        private var swapping = false
        /// How the text's length changed since the model last heard of an edit.
        private var typedDelta = 0
        /// The note on the page, to tell a switch to another note from a reload of this one.
        private var shownRel: String?

        /// Another note's text arrives. 克制: it fades in instead of cutting in. 活泼: it also rises
        /// a few points and settles with a spring. 简洁: it cuts in. Run by Core Animation on the
        /// render server; the main thread only adds the animation.
        private func fadeIn() {
            guard Motion.style != .minimal, !Motion.reduce, let scroll = scrollView else { return }
            scroll.wantsLayer = true
            guard let layer = scroll.layer else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = Motion.style == .lively ? 0 : 0.2
            fade.toValue = 1
            fade.duration = Motion.style == .lively ? 0.2 : 0.24
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "noteSwitch")
            if Motion.style == .lively, let rise = Motion.spring("transform.translation.y", from: layer.contentsAreFlipped() ? 10 : -10, to: 0) {
                layer.add(rise, forKey: "noteSwitchRise")
            }
        }
        private var styler = MarkdownStyler(style: EditorStyle(font: .serif, typewriter: true, dim: true, zen: false, width: 680))

        init(model: AppModel) {
            self.model = model
            super.init()
            styler.resolveEmbed = { [weak model] target in model?.resolveEmbed(target) }
            styler.resolveNote = { [weak model] target in model?.resolveEmbeddedNote(target) }
            styler.pluginPage = { [weak model] lang in model?.blockRendererPage(lang) }
            model.noteFilesChanged = { [weak self] in
                self?.styler.notesChanged()
                self?.restyle()
            }
            model.applyEditorEdit = { [weak self] range, text in
                guard let tv = self?.textView, NSMaxRange(range) <= (tv.string as NSString).length else { return }
                tv.window?.makeFirstResponder(tv)
                tv.insertText(text, replacementRange: range)
            }
            // A native copy: comparing and slicing a bridged NSString is many times slower.
            model.editor.live = { [weak self] in
                guard let tv = self?.textView else { return nil }
                return String(decoding: Array(tv.string.utf8), as: UTF8.self)
            }
            model.selectEditorRange = { [weak self] range in
                guard let self, let tv = self.textView, NSMaxRange(range) <= (tv.string as NSString).length else { return }
                tv.setSelectedRange(range)
                tv.scrollRangeToVisible(range)
            }
            // Pictures that finished rendering or loading, and folded callouts, fade in.
            styler.needsRestyle = { [weak self] in
                if let tv = self?.textView { EditorEffects.fadeNextDraw(of: tv) }
                self?.restyle()
            }
            model.scrollEditorTo = { [weak self] offset in self?.scrollToLine(at: offset) }
            NotificationCenter.default.addObserver(forName: .twainApplySlash, object: nil, queue: .main) { [weak self] n in
                let item = n.object as? SlashItem
                MainActor.assumeIsolated { if let item { self?.applySlash(item) } }
            }
        }

        var storage: NSTextStorage? { textView?.textStorage }

        func sync(version v: Int, rel: String?, text: String, style s: EditorStyle, ghost: String, readOnly: Bool, focus: (caret: Int, token: Int)?) {
            guard let tv = textView, let storage else { return }
            var needsRestyle = false
            if v != version {
                version = v
                if tv.string != text {
                    styler.newDocument()
                    BlockRenderer.shared.vaultRoot = model.vault?.root
                    #if DEBUG
                    let t0 = CACurrentMediaTime()
                    defer { if Self.profile { FileHandle.standardError.write(String(format: "sync swap %.1fms\n", (CACurrentMediaTime() - t0) * 1000).data(using: .utf8)!) } }
                    #endif
                    let sel = tv.selectedRange()
                    swapping = true
                    storage.beginEditing()
                    storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                              with: NSAttributedString(string: text, attributes: styler.baseAttributes()))
                    storage.endEditing()
                    tv.undoManager?.removeAllActions()
                    let len = (text as NSString).length
                    // A pending focus request already says where the caret goes.
                    let pendingCaret = focus.flatMap { $0.token != focusToken ? $0.caret : nil }
                    tv.setSelectedRange(NSRange(location: min(pendingCaret ?? sel.location, len), length: 0))
                    swapping = false
                    tv.resetCaretTrailTracking()
                    if focus == nil || focus!.token == focusToken { tv.scroll(.zero) }
                    if rel != shownRel, shownRel != nil { fadeIn() }
                }
                shownRel = rel
                needsRestyle = true
            }
            if s != style {
                style = s
                styler.setStyle(s)
                needsRestyle = true
                layoutChanged()
                laidOutHeight = -1
                DispatchQueue.main.async { self.visibleSizeChanged() }
            }
            tv.isEditable = !readOnly
            tv.ghost = ghost
            if let f = focus, f.token != focusToken {
                focusToken = f.token
                DispatchQueue.main.async {
                    tv.window?.makeFirstResponder(tv)
                    let len = (tv.string as NSString).length
                    tv.setSelectedRange(NSRange(location: min(f.caret, len), length: 0))
                    tv.resetCaretTrailTracking()
                    self.restyle()
                    self.center(smooth: false)
                }
            }
            if needsRestyle { restyle() }
        }

        private var laidOutHeight: CGFloat = -1

        private var outlineWork: DispatchWorkItem?

        /// The page scrolled: once it settles, find which heading's section is at the top (only
        /// for notes long enough to show an outline). Waiting for the scroll to settle keeps the
        /// typewriter's scroll on every key free of it; the hook then slides over in one go.
        func scrolled() {
            guard model.editor.outline.count >= OutlineRail.minimumEntries else { return }
            outlineWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.updateOutlineCurrent() }
            outlineWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
        }

        private func updateOutlineCurrent() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            let outline = model.editor.outline
            // A point a little below the top edge, so a heading counts once it's in view; in
            // typewriter mode the line being read sits in the middle of the page.
            let y = model.prefs.typewriter ? tv.visibleRect.midY : tv.visibleRect.minY + 60
            let probe = CGPoint(x: 1, y: y - tv.textContainerOrigin.y)
            let glyph = lm.glyphIndex(for: probe, in: tc)
            let char = lm.characterIndexForGlyph(at: glyph)
            let current = outline.lastIndex { $0.offset <= char } ?? 0
            if model.editor.outlineCurrent != current { model.editor.outlineCurrent = current }
        }

        /// Puts the line at `offset` near the top of the page; slides there unless the style says not to move.
        func scrollToLine(at offset: Int) {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, let scroll = scrollView,
                  offset <= (tv.string as NSString).length else { return }
            let range = NSRange(location: offset, length: 0)
            // Typewriter mode keeps the caret's line in the middle: moving the caret is the jump.
            if model.prefs.typewriter {
                tv.setSelectedRange(range)
                return
            }
            lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(offset + 1, (tv.string as NSString).length)))
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyphs.location, length: max(glyphs.length, 1)), in: tc)
            let maxY = max(0, tv.frame.height - scroll.contentView.bounds.height)
            let y = min(max(0, rect.minY + tv.textContainerOrigin.y - 72), maxY)
            let target = NSPoint(x: scroll.contentView.bounds.minX, y: y)
            let duration = Motion.standardDuration
            if duration > 0 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration + 0.1
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                    scroll.contentView.animator().setBoundsOrigin(target)
                } completionHandler: {
                    MainActor.assumeIsolated { scroll.reflectScrolledClipView(scroll.contentView) }
                }
            } else {
                scroll.contentView.setBoundsOrigin(target)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            // The caret stays where it was: moving it would make the editor scroll it into view
            // and fight the slide. The outline is for reading; a click in the text moves the caret.
        }

        func visibleSizeChanged() {
            guard let scroll = scrollView, style != nil else { return }
            let h = scroll.contentView.bounds.height
            guard h > 0, h != laidOutHeight else { return }
            laidOutHeight = h
            layoutChanged()
            center(smooth: false)
        }

        func layoutChanged() {
            guard let tv = textView, let style, let scroll = scrollView else { return }
            tv.updateInsets(style: style, visibleHeight: scroll.contentView.bounds.height)
            if !model.editor.annotations.isEmpty { scheduleRail() }
            if let tc = tv.textContainer {
                let before = styler.containerWidth
                styler.setContainerWidth(tc.size.width)
                if before != styler.containerWidth { DispatchQueue.main.async { self.restyle() } }
            }
            tv.updateCaret(animated: false)
        }

        /// Pictures are drawn for the light or the dark look.
        func appearanceChanged() {
            guard let tv = textView else { return }
            let dark = tv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            guard dark != styler.dark else { return }
            styler.dark = dark
            restyle()
        }

        func focusChanged() {
            DispatchQueue.main.async {
                self.restyle()
                if self.textView?.window?.firstResponder !== self.textView {
                    self.model.editor.slash = nil
                    self.model.clearGhost()
                }
            }
        }

        // MARK: styling

        private var isFocused: Bool {
            guard let tv = textView else { return false }
            return tv.window?.firstResponder === tv
        }

        /// The note's storage is only ever edited on the main thread.
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated {
                styler.noteEdit(editedRange, delta: delta)
                if !swapping { typedDelta += delta }
            }
        }

        func currentLine() -> Int? {
            guard let tv = textView, isFocused else { return nil }
            return styler.lineIndex(at: tv.selectedRange().location)
        }

        /// Restyles what changed since last time; cheap when nothing did.
        #if DEBUG
        static let profile = ProcessInfo.processInfo.environment["TWAIN_PROFILE"] != nil
        #endif

        func restyle() {
            guard let tv = textView, let storage, let lm = tv.layoutManager, !restyling else { return }
            if tv.hasMarkedText() { return }
            restyling = true
            defer { restyling = false }
            let caret = isFocused ? tv.selectedRange().location : nil
            styler.dark = tv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            styler.priorityLine = topVisibleLine() ?? caret.map { styler.lineIndex(at: $0) } ?? 0
            var ranges: [NSRange] = []
            tv.holdingHeight {
                #if DEBUG
                let t0 = CACurrentMediaTime()
                #endif
                ranges = styler.restyle(storage, caret: caret)
                #if DEBUG
                let t1 = CACurrentMediaTime()
                #endif
                for r in ranges {
                    lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
                    lm.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil)
                    lm.invalidateDisplay(forCharacterRange: r)
                }
                #if DEBUG
                if Self.profile, CACurrentMediaTime() - t0 > 0.004 {
                    FileHandle.standardError.write(String(format: "restyle style %.1fms invalidate %.1fms lines %d\n", (t1 - t0) * 1000,
                                                          (CACurrentMediaTime() - t1) * 1000, ranges.count).data(using: .utf8)!)
                }
                #endif
            }
            let body = styler.typo.body
            let p = NSMutableParagraphStyle()
            p.lineSpacing = max(0, body.pointSize * 1.8 - (body.ascender - body.descender + body.leading))
            p.paragraphSpacing = 12
            p.firstLineHeadIndent = MarkdownStyler.gutter
            p.headIndent = MarkdownStyler.gutter
            p.tailIndent = -MarkdownStyler.gutter
            tv.typingAttributes = [.font: body, .foregroundColor: Theme.NS.ink, .paragraphStyle: p]
            updateFocus()
            tv.updateCaret(animated: true)
            // A long note is styled in slices, nearest to the screen first; the rest follows
            // on later turns so typing and scrolling stay responsive.
            if styler.pending, !continuing {
                continuing = true
                DispatchQueue.main.async { [weak self] in
                    self?.continuing = false
                    self?.restyle()
                }
            }
        }

        private var continuing = false

        /// Paragraph dimming: the caret's line at full strength, the rest faded, while the editor
        /// has focus. Drawn by the layout manager; only the lines that change are redrawn.
        private func updateFocus() {
            guard let tv = textView, let lm = tv.layoutManager as? TwainLayoutManager, let style else { return }
            let len = (tv.string as NSString).length
            let new: NSRange? = {
                guard style.dim, !style.plain, isFocused else { return nil }
                return styler.lineRange(styler.lineIndex(at: min(tv.selectedRange().location, len)), length: len)
            }()
            guard new != lm.focus else { return }
            let old = lm.focus
            lm.focus = new
            if let old, let new {
                for r in [old, new] where NSMaxRange(r) <= len { lm.invalidateDisplay(forCharacterRange: r) }
            } else {
                tv.setNeedsDisplay(tv.visibleRect)
            }
        }

        /// The line at the top of the visible area, when layout already knows it.
        private func topVisibleLine() -> Int? {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, tv.textStorage?.length ?? 0 > 0,
                  let clip = scrollView?.contentView else { return nil }
            let top = tv.convert(clip.bounds, from: clip).minY - tv.textContainerOrigin.y
            guard top > 0 else { return 0 }
            // Only ask layout where it already has laid out: it must not typeset the whole note to answer.
            guard lm.firstUnlaidCharacterIndex() > 0 || !lm.allowsNonContiguousLayout else { return nil }
            let gi = lm.glyphIndex(for: NSPoint(x: 0, y: top), in: tc)
            return styler.lineIndex(at: lm.characterIndexForGlyph(at: gi))
        }

        // MARK: annotations

        private let rail = AnnotationRail()
        private var railWork: DispatchWorkItem?
        private var lastHighlights: [NSRange] = []

        /// Re-anchors the annotations and lays out their cards once the current burst of work is done.
        func scheduleRail() {
            railWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.layoutRail() }
            railWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: w)
        }

        private func layoutRail() {
            guard let tv = textView, let lm = tv.layoutManager as? TwainLayoutManager else { return }
            let list = model.chrome.zen ? [] : model.visibleAnnotations
            let text = tv.string
            var anchors: [String: NSRange] = [:]
            for a in list { if let r = Anchor.locate(a.quote, in: text, line: a.line) { anchors[a.id] = r } }
            lm.highlights = list.compactMap { a in
                anchors[a.id].map { ($0, NSColor(AnnotationCard.tint(a.kind)), a.id == model.editor.selectedAnnotation) }
            }
            for r in lastHighlights + lm.highlights.map(\.range) where NSMaxRange(r) <= (text as NSString).length {
                lm.invalidateDisplay(forCharacterRange: r)
            }
            lastHighlights = lm.highlights.map(\.range)
            if list.isEmpty { rail.clear() } else { rail.layout(in: tv, model: model, anchors: anchors, selected: model.editor.selectedAnnotation) }
        }

        // MARK: text changes

        func textDidChange(_ notification: Notification) {
            textView?.updateCaret(animated: true)
            guard let tv = textView, !tv.hasMarkedText(), !swapping else { return }
            // The model copies the text out of the editor only when it needs it.
            let delta = typedDelta
            typedDelta = 0
            model.editorEdited(delta: delta)
            restyle()
            if !model.editor.annotations.isEmpty { scheduleRail() }
            updateSlash()
            center(smooth: true)
            schedulePause()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            textView?.updateCaret(animated: true)
            guard let tv = textView, !tv.hasMarkedText(), !restyling, !swapping else { return }
            model.editor.editorSelection = tv.selectedRange()
            restyle()
            updateSlash()
            if tv.selectedRange().length == 0, !swapping { center(smooth: true) }
        }

        /// The caret's line: its text, range (without the newline) and index.
        private func lineInfo(at loc: Int? = nil) -> (text: String, range: NSRange, index: Int)? {
            guard let tv = textView else { return nil }
            let ns = tv.string as NSString
            let at = min(loc ?? tv.selectedRange().location, ns.length)
            var r = ns.lineRange(for: NSRange(location: at, length: 0))
            if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
            return (ns.substring(with: r), r, styler.lineIndex(at: r.location))
        }

        private func schedulePause() {
            guard let tv = textView, let info = lineInfo() else { return }
            let atEnd = tv.selectedRange().location == NSMaxRange(info.range) && tv.selectedRange().length == 0
            model.textPaused(paragraph: info.text, caretAtEnd: atEnd, lineIndex: info.index)
        }

        func acceptGhost() {
            guard let tv = textView, !model.editor.ghost.isEmpty else { return }
            let g = model.editor.ghost
            model.clearGhost()
            tv.insertText(g, replacementRange: tv.selectedRange())
        }

        func dropGhost() { model.clearGhost() }

        // MARK: slash menu

        func updateSlash() {
            guard let tv = textView, isFocused, let info = lineInfo(), let items = SlashItem.matching(info.text, commands: model.userCommands),
                  let lm = tv.layoutManager, let tc = tv.textContainer, let scroll = scrollView else {
                if model.editor.slash != nil { model.editor.slash = nil }
                return
            }
            let gr = lm.glyphRange(forCharacterRange: NSRange(location: info.range.location, length: max(1, info.range.length)), actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: gr, in: tc)
            rect.origin.x += tv.textContainerOrigin.x
            rect.origin.y += tv.textContainerOrigin.y
            let inScroll = tv.convert(rect, to: scroll)
            let top = scroll.isFlipped ? inScroll.maxY : scroll.bounds.height - inScroll.minY
            let sel = min(model.editor.slash?.selection ?? 0, items.count - 1)
            let state = SlashState(items: items, selection: sel, anchor: CGPoint(x: inScroll.minX, y: top + 6))
            if model.editor.slash != state { model.editor.slash = state }
        }

        func applySlash(_ item: SlashItem) {
            guard let tv = textView, let info = lineInfo() else { return }
            model.editor.slash = nil
            if let key = item.command, let cmd = model.userCommand(named: key) {
                tv.insertText("", replacementRange: info.range)
                do { try model.runUserCommand(cmd, input: nil) } catch let e as RPCError { model.showToast(e.message) } catch {}
                return
            }
            if item.hr {
                tv.insertText("---\n", replacementRange: info.range)
                return
            }
            tv.insertText(item.prefix, replacementRange: info.range)
        }

        // MARK: keys

        /// Keyboard commands. Returns true when handled.
        func handle(_ sel: Selector) -> Bool {
            guard let tv = textView else { return false }
            if let s = model.editor.slash {
                switch sel {
                case #selector(NSResponder.moveDown(_:)):
                    model.editor.slash?.selection = (s.selection + 1) % s.items.count; return true
                case #selector(NSResponder.moveUp(_:)):
                    model.editor.slash?.selection = (s.selection + s.items.count - 1) % s.items.count; return true
                case #selector(NSResponder.insertNewline(_:)):
                    applySlash(s.items[min(s.selection, s.items.count - 1)]); return true
                case #selector(NSResponder.cancelOperation(_:)):
                    if let info = lineInfo() { tv.insertText("", replacementRange: info.range) }
                    model.editor.slash = nil
                    return true
                default: break
                }
            }
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                return newline()
            case #selector(NSResponder.deleteBackward(_:)):
                return deleteMarker()
            case #selector(NSResponder.insertTab(_:)):
                if !model.editor.ghost.isEmpty { acceptGhost(); return true }
                return shiftListLevel(by: 1)
            case #selector(NSResponder.insertBacktab(_:)):
                return shiftListLevel(by: -1)
            case #selector(NSResponder.moveToEndOfLine(_:)), #selector(NSResponder.moveToRightEndOfLine(_:)):
                if !model.editor.ghost.isEmpty { acceptGhost(); return true }
                return false
            case #selector(NSResponder.cancelOperation(_:)):
                model.clearGhost()
                tv.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        private func isCode(line: Int) -> Bool { styler.isCode(line: line) }

        /// Return: continue lists and quotes, leave an empty item, keep code indentation.
        private func newline() -> Bool {
            guard let tv = textView, let info = lineInfo() else { return false }
            let sel = tv.selectedRange()
            let caretCol = sel.location - info.range.location
            if isCode(line: info.index) {
                let indent = String(info.text.prefix { $0 == " " || $0 == "\t" })
                guard !indent.isEmpty else { return false }
                tv.insertText("\n" + indent, replacementRange: sel)
                return true
            }
            if let cont = Markdown.continuation(for: info.text) {
                let prefixLen = Markdown.prefixLength(info.text)
                if cont.exit {
                    if Markdown.indentLevel(String(info.text.prefix { $0 == " " || $0 == "\t" })) > 0 {
                        return shiftListLevel(by: -1)
                    }
                    tv.insertText("", replacementRange: info.range)
                    tv.listExitCaret = info.range.location
                    return true
                }
                // Return inside the marker itself just opens a line above.
                if caretCol < prefixLen { return false }
                tv.insertText("\n" + cont.prefix, replacementRange: sel)
                return true
            }
            if Markdown.blockType(info.text) == .quote {
                let pre = (info.text as NSString).substring(to: Markdown.prefixLength(info.text))
                if info.text == pre || info.text.trimmingCharacters(in: .whitespaces) == ">" {
                    tv.insertText("", replacementRange: info.range)
                    return true
                }
                if caretCol >= pre.utf16.count {
                    tv.insertText("\n" + pre, replacementRange: sel)
                    return true
                }
            }
            return false
        }

        /// Backspace right after a list or quote marker removes the marker (or a nesting level) at once.
        private func deleteMarker() -> Bool {
            guard let tv = textView, tv.selectedRange().length == 0, let info = lineInfo() else { return false }
            let type = Markdown.blockType(info.text)
            guard type.isList || type == .quote else { return false }
            let prefixLen = Markdown.prefixLength(info.text)
            guard tv.selectedRange().location == info.range.location + prefixLen else { return false }
            if type.isList, Markdown.indentLevel(String(info.text.prefix { $0 == " " || $0 == "\t" })) > 0 {
                return shiftListLevel(by: -1)
            }
            tv.insertText("", replacementRange: NSRange(location: info.range.location, length: prefixLen))
            return true
        }

        /// Tab / ⇧Tab on list lines (every selected one) nest or un-nest them.
        private func shiftListLevel(by d: Int) -> Bool {
            guard let tv = textView else { return false }
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let block = ns.lineRange(for: sel)
            var starts: [Int] = []
            var loc = block.location
            while loc < NSMaxRange(block) || (loc == block.location && block.length == 0) {
                starts.append(loc)
                let r = ns.lineRange(for: NSRange(location: loc, length: 0))
                if NSMaxRange(r) == loc { break }
                loc = NSMaxRange(r)
            }
            let lines = starts.map { s -> (Int, String) in
                var r = ns.lineRange(for: NSRange(location: s, length: 0))
                if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
                return (s, ns.substring(with: r))
            }
            guard lines.contains(where: { Markdown.blockType($0.1).isList }) else { return false }
            let unit = lines.first { $0.1.hasPrefix(" ") }.map { _ in "    " } ?? "\t"
            // Edit bottom-up so earlier offsets stay valid; one undo step for the lot.
            tv.undoManager?.beginUndoGrouping()
            var shift = 0, firstShift = 0
            for (start, text) in lines.reversed() where Markdown.blockType(text).isList {
                if d > 0 {
                    tv.insertText(unit, replacementRange: NSRange(location: start, length: 0))
                    shift += unit.utf16.count
                    if start == lines.first!.0 { firstShift = unit.utf16.count }
                } else {
                    var n = 0
                    if text.hasPrefix("\t") { n = 1 } else { n = min(4, text.prefix { $0 == " " }.count) }
                    guard n > 0 else { continue }
                    tv.insertText("", replacementRange: NSRange(location: start, length: n))
                    shift -= n
                    if start == lines.first!.0 { firstShift = -n }
                }
            }
            tv.undoManager?.endUndoGrouping()
            let newLoc = max(block.location, sel.location + firstShift)
            tv.setSelectedRange(NSRange(location: newLoc, length: max(0, sel.length + shift - firstShift)))
            return true
        }

        // MARK: paste & drop

        static let mediaExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "svg", "avif",
                                                   "mp4", "mov", "m4v", "webm", "mkv", "avi", "mp3", "m4a", "wav", "pdf"]

        static func mediaURLs(_ pb: NSPasteboard) -> [URL] {
            let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            return urls.filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
        }

        static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"),
                                                                 NSPasteboard.PasteboardType("public.heic")]

        /// Pictures and video files: from Finder, a screenshot, or a copied image. Real text wins
        /// when both are there; a browser's "Copy Image" also puts the picture's address as text,
        /// and then the picture wins.
        static func hasMedia(_ pb: NSPasteboard) -> Bool {
            if !mediaURLs(pb).isEmpty { return true }
            guard pb.availableType(from: imageTypes) != nil else { return false }
            guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return true }
            let isAddress = !text.contains("\n") && !text.contains(" ") && (text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("file://"))
            return isAddress
        }

        /// Stores the pasted or dropped media as attachments and links them on their own lines.
        func pasteMedia(from pb: NSPasteboard, at loc: Int?) -> Bool {
            guard let tv = textView, tv.isEditable, Self.hasMedia(pb) else { return false }
            var names: [String] = []
            let urls = Self.mediaURLs(pb)
            if !urls.isEmpty {
                names = urls.compactMap { model.importAttachment($0) }
            } else if let data = pb.data(forType: .png) {
                names = model.saveAttachment(data, ext: "png").map { [$0] } ?? []
            } else if let data = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
                // Photos stay JPEG: re-encoding them as PNG makes them several times larger.
                names = model.saveAttachment(data, ext: "jpg").map { [$0] } ?? []
            } else if let data = pb.data(forType: .tiff) ?? pb.data(forType: NSPasteboard.PasteboardType("public.heic")),
                      let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
                names = model.saveAttachment(png, ext: "png").map { [$0] } ?? []
            }
            guard !names.isEmpty else { return false }
            let ns = tv.string as NSString
            let at = loc.map { NSRange(location: min($0, ns.length), length: 0) } ?? tv.selectedRange()
            let line = ns.lineRange(for: NSRange(location: at.location, length: 0))
            var text = names.map { "![[\($0)]]" }.joined(separator: "\n")
            if at.location > line.location { text = "\n" + text }
            let lineEnd = NSMaxRange(line) - (NSMaxRange(line) > line.location && ns.character(at: NSMaxRange(line) - 1) == 0x0A ? 1 : 0)
            if NSMaxRange(at) < lineEnd { text += "\n" }
            if loc != nil { tv.setSelectedRange(at) }
            tv.insertText(text, replacementRange: at)
            return true
        }

        // MARK: clicks

        #if DEBUG
        /// Clicks the first unchecked task's box, as the mouse would.
        func debugCheckFirstTask() {
            guard let tv = textView, let lm = tv.layoutManager as? TwainLayoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(forBoundingRect: tv.visibleRect, in: tc)
            tv.display()
            let ns = tv.string as NSString
            guard let hit = lm.taskHitRects.first(where: { $0.1 < ns.length && !Markdown.isTaskDone(ns.substring(with: ns.lineRange(for: NSRange(location: $0.1, length: 0)))) }),
                  let e = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            _ = handleClick(at: NSPoint(x: hit.0.midX, y: hit.0.midY), event: e)
        }
        #endif

        func handleClick(at p: NSPoint, event: NSEvent) -> Bool {
            guard let tv = textView, let lm = tv.layoutManager as? TwainLayoutManager, let tc = tv.textContainer, let storage else { return false }
            if let hit = lm.taskHitRects.first(where: { $0.0.contains(p) }) {
                toggleTask(lineStart: hit.1)
                // Checked (not unchecked): the box animates into its new state.
                let ns = tv.string as NSString
                if hit.1 < ns.length, Markdown.isTaskDone(ns.substring(with: ns.lineRange(for: NSRange(location: hit.1, length: 0)))) {
                    EditorEffects.taskChecked(in: tv, box: hit.0.insetBy(dx: 5, dy: 5))
                }
                return true
            }
            if let hit = lm.foldHitRects.first(where: { $0.0.contains(p) }) {
                styler.toggleFold(hit.1)
                return true
            }
            if let hit = lm.blockHitRects.last(where: { $0.rect.contains(p) }), hit.start <= storage.length {
                return clickBlock(hit.deco, start: hit.start, at: p, event: event)
            }
            if let hit = lm.embedHitRects.first(where: { $0.0.contains(p) }), let url = hit.1.url {
                if hit.1.kind == .video || event.clickCount == 2 || event.modifierFlags.contains(.command) {
                    NSWorkspace.shared.open(url)
                    return true
                }
            }
            let origin = tv.textContainerOrigin
            let local = NSPoint(x: p.x - origin.x, y: p.y - origin.y)
            var fraction: CGFloat = 0
            let gi = lm.glyphIndex(for: local, in: tc, fractionOfDistanceThroughGlyph: &fraction)
            guard gi < lm.numberOfGlyphs, lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc).contains(local) else { return false }
            let ci = lm.characterIndexForGlyph(at: gi)
            guard ci < storage.length else { return false }
            let followable = event.modifierFlags.contains(.command) || styler.lineIndex(at: ci) != currentLine()
            if followable, let title = storage.attribute(.twainWikiLink, at: ci, effectiveRange: nil) as? String {
                model.openByTitle(NoteOutline.linkTarget(title))
                return true
            }
            if followable, let url = storage.attribute(.twainURL, at: ci, effectiveRange: nil) as? String, let u = URL(string: url) {
                NSWorkspace.shared.open(u)
                return true
            }
            if followable, let label = storage.attribute(.twainFootnote, at: ci, effectiveRange: nil) as? String,
               let def = footnoteDefinition(label) {
                tv.setSelectedRange(NSRange(location: def.location, length: 0))
                tv.scrollRangeToVisible(def)
                return true
            }
            return false
        }

        /// A click on a drawn block. Tables put the caret in the clicked cell's source; formulas
        /// and diagrams reveal their source; embedded notes open on a double click (or ⌘-click).
        private func clickBlock(_ deco: BlockDeco, start: Int, at p: NSPoint, event: NSEvent) -> Bool {
            guard let tv = textView else { return false }
            let len = (tv.string as NSString).length
            var caret = start
            switch deco.content {
            case let .note(e):
                if event.clickCount >= 2 || event.modifierFlags.contains(.command) {
                    model.open(e.rel)
                    return true
                }
                if deco.revealed { return false }
                // The end of the `![[…]]` line: the source shows and the card stays below it.
                let line = (tv.string as NSString).lineRange(for: NSRange(location: min(start, len), length: 0))
                caret = NSMaxRange(line) - (NSMaxRange(line) > line.location && NSMaxRange(line) <= len && (tv.string as NSString).character(at: NSMaxRange(line) - 1) == 0x0A ? 1 : 0)
            case let .table(t):
                if let rect = (textView?.layoutManager as? TwainLayoutManager)?.blockHitRects.last(where: { $0.deco === deco })?.rect,
                   let off = t.sourceOffset(at: NSPoint(x: p.x - rect.minX, y: p.y - rect.minY)) {
                    caret = start + off
                }
            case .picture:
                if deco.revealed { return false }
                // Just inside the opening `$$` or fence line.
                let line = (tv.string as NSString).lineRange(for: NSRange(location: min(start, len), length: 0))
                caret = max(line.location, NSMaxRange(line) - 1)
            }
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: min(max(0, caret), len), length: 0))
            return true
        }

        /// The `[^label]: …` line for a footnote reference.
        func footnoteDefinition(_ label: String) -> NSRange? {
            guard let tv = textView else { return nil }
            let pattern = "^\\[\\^" + NSRegularExpression.escapedPattern(for: label) + "\\]:.*$"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
            let ns = tv.string as NSString
            return re.firstMatch(in: tv.string, range: NSRange(location: 0, length: ns.length))?.range
        }

        /// The text of a footnote, for the tooltip over its reference.
        func footnoteText(_ label: String) -> String? {
            guard let tv = textView, let r = footnoteDefinition(label) else { return nil }
            let line = (tv.string as NSString).substring(with: r)
            let m = Markdown.parseLine(line)
            return (line as NSString).substring(from: m.prefix.length).trimmingCharacters(in: .whitespaces)
        }

        private func toggleTask(lineStart: Int) {
            guard let tv = textView, let info = lineInfo(at: lineStart) else { return }
            let toggled = Markdown.toggleTask(info.text)
            guard toggled != info.text else { return }
            let prefix = Markdown.prefixLength(info.text)
            let r = NSRange(location: info.range.location, length: prefix)
            let new = (toggled as NSString).substring(to: prefix)
            guard tv.shouldChangeText(in: r, replacementString: new) else { return }
            tv.textStorage?.replaceCharacters(in: r, with: new)
            tv.didChangeText()
        }

        // MARK: scrolling

        func center(smooth: Bool) {
            guard let tv = textView, let scroll = scrollView, let lm = tv.layoutManager, let tc = tv.textContainer, let style else { return }
            let len = (tv.string as NSString).length
            let loc = min(tv.selectedRange().location, len)
            lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(len, loc + 1)))
            let caretRect: CGRect
            if len == 0 {
                caretRect = CGRect(x: 0, y: tv.textContainerOrigin.y, width: 1, height: 20)
            } else {
                let gi = lm.glyphIndexForCharacter(at: min(loc, len - 1))
                var r = NSRange()
                var frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: &r)
                if loc >= len, lm.extraLineFragmentTextContainer != nil { frag = lm.extraLineFragmentRect }
                caretRect = frag.offsetBy(dx: 0, dy: tv.textContainerOrigin.y)
            }
            _ = tc
            let clip = scroll.contentView
            let visible = clip.bounds
            // NSTextView can have a nonzero origin inside NSClipView. Both the caret
            // and scroll limits must be measured in the clip view's coordinates.
            let caretInClip = tv.convert(caretRect, to: clip)
            var target: CGFloat?
            if style.typewriter {
                target = caretInClip.midY - visible.height * 0.5
            } else if caretInClip.maxY > visible.maxY - 60 {
                target = visible.minY + caretInClip.maxY - visible.maxY + 90
            } else if caretInClip.minY < visible.minY + 20 {
                target = caretInClip.minY - 40
            }
            guard var t = target else { return }
            let minY = tv.frame.minY
            let maxY = max(minY, tv.frame.maxY - visible.height)
            t = max(minY, min(t, maxY))
            guard abs(t - visible.minY) > 1 else { return }
            if smooth {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.allowsImplicitAnimation = true
                    clip.animator().setBoundsOrigin(NSPoint(x: visible.minX, y: t))
                }
            } else {
                clip.setBoundsOrigin(NSPoint(x: visible.minX, y: t))
            }
            scroll.reflectScrolledClipView(clip)
        }
    }
}
