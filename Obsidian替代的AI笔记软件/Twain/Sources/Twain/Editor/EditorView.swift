import AppKit
import TwainCore
import SwiftUI

// MARK: - SwiftUI bridge

struct EditorView: NSViewRepresentable {
    @Bindable var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        storage.delegate = context.coordinator
        let lm = TwainLayoutManager()
        // Only what is visible gets laid out: an edit no longer re-typesets the rest of the note.
        lm.allowsNonContiguousLayout = true
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
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
        tv.registerForDraggedTypes([.fileURL, .png, .tiff])

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
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        let style = EditorStyle(font: model.font, typewriter: model.typewriter, dim: model.dim, zen: model.zen, width: model.editorWidth,
                                plain: model.activeNote?.isHTML == true)
        c.sync(version: model.editorVersion, text: model.editorText, style: style,
               ghost: model.ghost, readOnly: model.editorReadOnly, focus: model.focusRequest)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        let model: AppModel
        weak var textView: TwainTextView?
        weak var scrollView: NSScrollView?
        private var version = -1
        private var style: EditorStyle?
        private var focusToken = -1
        private var restyling = false
        private var styler = MarkdownStyler(style: EditorStyle(font: .serif, typewriter: true, dim: true, zen: false, width: 680))

        init(model: AppModel) {
            self.model = model
            super.init()
            styler.resolveEmbed = { [weak model] target in model?.resolveEmbed(target) }
            styler.needsRestyle = { [weak self] in self?.restyle() }
            NotificationCenter.default.addObserver(forName: .twainApplySlash, object: nil, queue: .main) { [weak self] n in
                if let item = n.object as? SlashItem { self?.applySlash(item) }
            }
        }

        var storage: NSTextStorage? { textView?.textStorage }

        func sync(version v: Int, text: String, style s: EditorStyle, ghost: String, readOnly: Bool, focus: (caret: Int, token: Int)?) {
            guard let tv = textView, let storage else { return }
            var needsRestyle = false
            if v != version {
                version = v
                if tv.string != text {
                    let sel = tv.selectedRange()
                    styler.reset()
                    storage.beginEditing()
                    storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
                    storage.endEditing()
                    tv.undoManager?.removeAllActions()
                    let len = (text as NSString).length
                    // A pending focus request already says where the caret goes.
                    let pendingCaret = focus.flatMap { $0.token != focusToken ? $0.caret : nil }
                    tv.setSelectedRange(NSRange(location: min(pendingCaret ?? sel.location, len), length: 0))
                    tv.resetCaretTrailTracking()
                    if focus == nil || focus!.token == focusToken { tv.scroll(.zero) }
                }
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
            if let tc = tv.textContainer {
                let before = styler.containerWidth
                styler.setContainerWidth(tc.size.width)
                if before != styler.containerWidth { DispatchQueue.main.async { self.restyle() } }
            }
            tv.updateCaret(animated: false)
        }

        func focusChanged() {
            DispatchQueue.main.async {
                self.restyle()
                if self.textView?.window?.firstResponder !== self.textView {
                    self.model.slash = nil
                    self.model.clearGhost()
                }
            }
        }

        // MARK: styling

        private var isFocused: Bool {
            guard let tv = textView else { return false }
            return tv.window?.firstResponder === tv
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            if editedMask.contains(.editedCharacters) { styler.noteEdit(editedRange, delta: delta) }
        }

        func currentLine() -> Int? {
            guard let tv = textView, isFocused else { return nil }
            return styler.lineIndex(at: tv.selectedRange().location)
        }

        /// Restyles what changed since last time; cheap when nothing did.
        func restyle() {
            guard let tv = textView, let storage, let lm = tv.layoutManager, !restyling else { return }
            if tv.hasMarkedText() { return }
            restyling = true
            defer { restyling = false }
            let caret = isFocused ? tv.selectedRange().location : nil
            var ranges: [NSRange] = []
            tv.holdingHeight {
                ranges = styler.restyle(storage, caret: caret)
                for r in ranges {
                    lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
                    lm.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil)
                    lm.invalidateDisplay(forCharacterRange: r)
                }
            }
            let body = styler.typo.body
            let p = NSMutableParagraphStyle()
            p.lineSpacing = max(0, body.pointSize * 1.8 - (body.ascender - body.descender + body.leading))
            p.paragraphSpacing = 12
            p.firstLineHeadIndent = MarkdownStyler.gutter
            p.headIndent = MarkdownStyler.gutter
            p.tailIndent = -MarkdownStyler.gutter
            tv.typingAttributes = [.font: body, .foregroundColor: Theme.NS.ink, .paragraphStyle: p]
            tv.updateCaret(animated: true)
        }

        // MARK: text changes

        func textDidChange(_ notification: Notification) {
            textView?.updateCaret(animated: true)
            guard let tv = textView, !tv.hasMarkedText() else { return }
            // A native copy: comparing and slicing a bridged NSString is many times slower.
            model.editorDidChange(String(decoding: Array(tv.string.utf8), as: UTF8.self))
            restyle()
            updateSlash()
            center(smooth: true)
            schedulePause()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            textView?.updateCaret(animated: true)
            guard let tv = textView, !tv.hasMarkedText(), !restyling else { return }
            model.editorSelection = tv.selectedRange()
            restyle()
            updateSlash()
            if tv.selectedRange().length == 0 { center(smooth: true) }
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
            guard let tv = textView, !model.ghost.isEmpty else { return }
            let g = model.ghost
            model.clearGhost()
            tv.insertText(g, replacementRange: tv.selectedRange())
        }

        func dropGhost() { model.clearGhost() }

        // MARK: slash menu

        func updateSlash() {
            guard let tv = textView, isFocused, let info = lineInfo(), let items = SlashItem.matching(info.text, commands: model.userCommands),
                  let lm = tv.layoutManager, let tc = tv.textContainer, let scroll = scrollView else {
                if model.slash != nil { model.slash = nil }
                return
            }
            let gr = lm.glyphRange(forCharacterRange: NSRange(location: info.range.location, length: max(1, info.range.length)), actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: gr, in: tc)
            rect.origin.x += tv.textContainerOrigin.x
            rect.origin.y += tv.textContainerOrigin.y
            let inScroll = tv.convert(rect, to: scroll)
            let top = scroll.isFlipped ? inScroll.maxY : scroll.bounds.height - inScroll.minY
            let sel = min(model.slash?.selection ?? 0, items.count - 1)
            let state = SlashState(items: items, selection: sel, anchor: CGPoint(x: inScroll.minX, y: top + 6))
            if model.slash != state { model.slash = state }
        }

        func applySlash(_ item: SlashItem) {
            guard let tv = textView, let info = lineInfo() else { return }
            model.slash = nil
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
            if let s = model.slash {
                switch sel {
                case #selector(NSResponder.moveDown(_:)):
                    model.slash?.selection = (s.selection + 1) % s.items.count; return true
                case #selector(NSResponder.moveUp(_:)):
                    model.slash?.selection = (s.selection + s.items.count - 1) % s.items.count; return true
                case #selector(NSResponder.insertNewline(_:)):
                    applySlash(s.items[min(s.selection, s.items.count - 1)]); return true
                case #selector(NSResponder.cancelOperation(_:)):
                    if let info = lineInfo() { tv.insertText("", replacementRange: info.range) }
                    model.slash = nil
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
                if !model.ghost.isEmpty { acceptGhost(); return true }
                return shiftListLevel(by: 1)
            case #selector(NSResponder.insertBacktab(_:)):
                return shiftListLevel(by: -1)
            case #selector(NSResponder.moveToEndOfLine(_:)), #selector(NSResponder.moveToRightEndOfLine(_:)):
                if !model.ghost.isEmpty { acceptGhost(); return true }
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

        /// Pictures and video files: from Finder, a screenshot, or a copied image. Text wins when both are there.
        static func hasMedia(_ pb: NSPasteboard) -> Bool {
            if !mediaURLs(pb).isEmpty { return true }
            let hasText = pb.availableType(from: [.string]) != nil
            return !hasText && pb.availableType(from: [.png, .tiff]) != nil
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
            } else if let data = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: data),
                      let png = rep.representation(using: .png, properties: [:]) {
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

        func handleClick(at p: NSPoint, event: NSEvent) -> Bool {
            guard let tv = textView, let lm = tv.layoutManager as? TwainLayoutManager, let tc = tv.textContainer, let storage else { return false }
            if let hit = lm.taskHitRects.first(where: { $0.0.contains(p) }) {
                toggleTask(lineStart: hit.1)
                return true
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
            return false
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
