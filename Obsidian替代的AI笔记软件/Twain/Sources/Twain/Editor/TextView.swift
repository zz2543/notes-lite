import AppKit
import TwainCore

// MARK: - Text view

final class TwainTextView: NSTextView {
    weak var coordinator: EditorView.Coordinator?
    var ghost = "" { didSet { if ghost != oldValue { needsDisplay = true } } }
    var topInset: CGFloat = 56
    var bottomInset: CGFloat = 300

    override var textContainerOrigin: NSPoint {
        NSPoint(x: textContainerInset.width, y: topInset)
    }

    func updateInsets(style: EditorStyle, visibleHeight: CGFloat) {
        let w = bounds.width
        // A rail on the right holds annotation cards; the text column centers in what is left.
        let avail = w - style.rail
        let pad: CGFloat = avail < 700 ? 20 : 48
        // The container starts a gutter left of the text column, so syntax can hang into it.
        let side = max(0, max(pad, (avail - style.width) / 2) - MarkdownStyler.gutter)
        let containerWidth = max(120, avail - 2 * side)
        if let tc = textContainer, abs(tc.size.width - containerWidth) > 0.5 {
            tc.size = NSSize(width: containerWidth, height: .greatestFiniteMagnitude)
        }
        if style.typewriter {
            topInset = visibleHeight * 0.5
            bottomInset = visibleHeight * 0.55
        } else {
            topInset = style.zen ? 96 : 56
            bottomInset = visibleHeight * 0.4
        }
        let inset = NSSize(width: side, height: (topInset + bottomInset) / 2)
        if inset != textContainerInset { textContainerInset = inset }
    }

    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        // Mid-edit, NSLayoutManager briefly reports a used rect far shorter than the text
        // (seen: 3224pt for a 5258pt note). Shrinking to it makes NSClipView clamp the scroll
        // offset, which reads as the view jumping up and gliding back on every Return.
        if heightHeld, size.height < frame.height { size.height = frame.height }
        let widthChanged = size.width != frame.width
        super.setFrameSize(size)
        if widthChanged { coordinator?.layoutChanged() }
    }

    private var heightHeld = false

    /// Runs a text or attribute edit without letting the view shrink midway, then fits it once.
    func holdingHeight(_ edit: () -> Void) {
        let outer = !heightHeld
        heightHeld = true
        edit()
        if outer { releaseHeightSoon() }
    }

    /// The used rect is still stale right after an edit, even after ensureLayout; it settles
    /// by the next main-queue turn, so the hold is released and the height fitted only then.
    private func releaseHeightSoon() {
        guard !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fitScheduled = false
            heightHeld = false
            fitHeightToLayout()
        }
    }

    private var fitScheduled = false

    private func fitHeightToLayout() {
        guard let lm = layoutManager, let tc = textContainer else { return }
        // Non-contiguous layout: lay out what is on screen; the rest of the height is the
        // layout manager's estimate, refined as the reader scrolls.
        lm.ensureLayout(forBoundingRect: visibleRect.offsetBy(dx: 0, dy: -textContainerOrigin.y), in: tc)
        let h = max(minSize.height, lm.usedRect(for: tc).height + topInset + bottomInset)
        if abs(h - frame.height) > 0.5 { setFrameSize(NSSize(width: frame.width, height: h)) }
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let ok = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if ok { heightHeld = true }
        return ok
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        let ok = super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        if ok { heightHeld = true }
        return ok
    }

    override func didChangeText() {
        super.didChangeText()
        if heightHeld { releaseHeightSoon() }
    }

    override func keyDown(with event: NSEvent) {
        listExitCaret = nil
        pendingTrailSide = event.keyCode == 51 ? .right : event.keyCode == 117 ? .left : nil
        defer { pendingTrailSide = nil }
        if let c = coordinator {
            if event.keyCode == 48, !event.modifierFlags.contains(.shift) { // Tab
                c.acceptGhost()
                return
            }
            if !ghost.isEmpty, event.keyCode != 56, event.keyCode != 60 { c.dropGhost() }
        }
        super.keyDown(with: event)
    }

    /// Caret left by Return on an empty list item, until the next key press.
    var listExitCaret: Int?

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Some input methods (WeType) continue lists on their own: right after Twain clears an
        // empty "- " they see a blank line under a list item and type the marker back in.
        if let caret = listExitCaret {
            listExitCaret = nil
            let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
            if replacementRange.location == NSNotFound, selectedRange() == NSRange(location: caret, length: 0),
               Markdown.blockType(text).isList, Markdown.prefixLength(text) == (text as NSString).length { return }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func doCommand(by selector: Selector) {
        if coordinator?.handle(selector) == true { return }
        super.doCommand(by: selector)
    }

    // MARK: paste & drop

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.fileURL, .png, .tiff]
    }

    override func paste(_ sender: Any?) {
        if coordinator?.pasteMedia(from: .general, at: nil) == true { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if EditorView.Coordinator.hasMedia(sender.draggingPasteboard) { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if EditorView.Coordinator.hasMedia(pb) {
            let p = convert(sender.draggingLocation, from: nil)
            let at = characterIndexForInsertion(at: p)
            if coordinator?.pasteMedia(from: pb, at: at) == true { return true }
        }
        return super.performDragOperation(sender)
    }

    // MARK: footnotes

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(a)
        hoverArea = a
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        let local = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        let gi = lm.glyphIndex(for: local, in: tc)
        var tip: String?
        if gi < lm.numberOfGlyphs, lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc).insetBy(dx: -2, dy: -2).contains(local) {
            let ci = lm.characterIndexForGlyph(at: gi)
            if ci < storage.length, let label = storage.attribute(.twainFootnote, at: ci, effectiveRange: nil) as? String {
                tip = coordinator?.footnoteText(label) ?? "没有找到脚注 [^\(label)] 的内容"
            }
        }
        if toolTip != tip { toolTip = tip }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let c = coordinator, c.handleClick(at: p, event: event) { return }
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let r = super.becomeFirstResponder()
        resetCaretTrailTracking()
        coordinator?.focusChanged()
        updateCaret(animated: false)
        return r
    }

    override func resignFirstResponder() -> Bool {
        let r = super.resignFirstResponder()
        coordinator?.focusChanged()
        updateCaret(animated: false)
        return r
    }

    // MARK: caret
    //
    // The system insertion point is hidden and replaced by a thicker, taller layer that
    // glides to its new position and only blinks after the writer pauses.

    let caret = CALayer()
    private let caretTrail = CAGradientLayer()
    private let trailMask = CAGradientLayer()
    private enum TrailSide { case left, right }
    private var trailSide: TrailSide = .left
    private var pendingTrailSide: TrailSide?
    private var lastObservedCaretLocation: Int?
    private var blinkTimer: Timer?
    private var lastMove = Date.distantPast
    static let caretWidth: CGFloat = 2.5
    private static let trailDuration: CFTimeInterval = 0.8

    func setUpCaret() {
        wantsLayer = true
        insertionPointColor = .clear
        let accent = NSColor.controlAccentColor
        caretTrail.startPoint = CGPoint(x: 0, y: 0.5)
        caretTrail.endPoint = CGPoint(x: 1, y: 0.5)
        caretTrail.locations = [0, 0.45, 1]
        caretTrail.opacity = 0
        caretTrail.zPosition = 9
        caretTrail.actions = ["bounds": NSNull(), "colors": NSNull(), "opacity": NSNull(),
                              "startPoint": NSNull(), "endPoint": NSNull()]
        trailMask.startPoint = CGPoint(x: 0.5, y: 0)
        trailMask.endPoint = CGPoint(x: 0.5, y: 1)
        trailMask.colors = [NSColor.clear.cgColor, NSColor.white.cgColor,
                            NSColor.white.cgColor, NSColor.clear.cgColor]
        trailMask.locations = [0, 0.16, 0.84, 1]
        caretTrail.mask = trailMask
        updateTrailColors(accent)
        caret.cornerRadius = Self.caretWidth / 2
        caret.backgroundColor = accent.cgColor
        caret.opacity = 0
        caret.zPosition = 10
        caret.actions = ["bounds": NSNull(), "backgroundColor": NSNull()]
        layer?.addSublayer(caretTrail)
        layer?.addSublayer(caret)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in self?.blink() }
    }

    deinit { blinkTimer?.invalidate() }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        coordinator?.appearanceChanged()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            caret.backgroundColor = accent.cgColor
            updateTrailColors(accent)
        }
    }

    private func updateTrailColors(_ accent: NSColor) {
        caretTrail.colors = [accent.withAlphaComponent(0).cgColor,
                             accent.withAlphaComponent(0.18).cgColor,
                             accent.withAlphaComponent(0.55).cgColor]
    }

    func resetCaretTrailTracking() {
        lastObservedCaretLocation = selectedRange().location
        trailSide = .left
        caretTrail.removeAnimation(forKey: "movementTrail")
    }

    override func layout() {
        super.layout()
        hideSystemIndicator(in: self)
    }

    private func hideSystemIndicator(in view: NSView) {
        for sub in view.subviews {
            if let ind = sub as? NSTextInsertionIndicator { ind.displayMode = .hidden }
        }
    }

    static var forceCaret = false

    private var caretVisible: Bool {
        window?.firstResponder === self && (window?.isKeyWindow == true || Self.forceCaret) && selectedRange().length == 0 && isEditable
    }

    private func blink() {
        guard caretVisible else { caret.opacity = 0; caretTrail.opacity = 0; return }
        guard Date().timeIntervalSince(lastMove) > 0.65 else {
            caret.opacity = 1
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        caret.opacity = caret.opacity <= 0.5 ? 1 : 0
        CATransaction.commit()
    }

    /// Caret rect in view coordinates for the current insertion point.
    private func caretRect() -> CGRect? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage else { return nil }
        let len = storage.length
        let loc = min(selectedRange().location, len)
        let origin = textContainerOrigin
        let fontAt = loc > 0 ? loc - 1 : loc
        let font = (len > 0 ? storage.attribute(.font, at: min(fontAt, len - 1), effectiveRange: nil) as? NSFont : nil)
            ?? (typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 17)
        lm.ensureLayout(forCharacterRange: NSRange(location: max(0, loc - 1), length: min(2, len - max(0, loc - 1))))
        var x: CGFloat
        var baseline: CGFloat
        var lineFont = font
        if len == 0 || (loc == len && lm.extraLineFragmentTextContainer != nil) {
            let r = lm.extraLineFragmentRect
            let para = typingAttributes[.paragraphStyle] as? NSParagraphStyle
            lineFont = (typingAttributes[.font] as? NSFont) ?? font
            x = r.minX + (para?.firstLineHeadIndent ?? 0)
            baseline = r.minY + lineFont.ascender
        } else if loc < len {
            let gi = lm.glyphIndexForCharacter(at: loc)
            var eff = NSRange()
            let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: &eff)
            let p = lm.location(forGlyphAt: gi)
            x = frag.minX + p.x
            baseline = frag.minY + p.y
            // At a line start the character's own font decides the height.
            if let f = storage.attribute(.font, at: loc, effectiveRange: nil) as? NSFont,
               loc == 0 || (storage.string as NSString).character(at: loc - 1) == 0x0A { lineFont = f }
        } else {
            let gi = lm.glyphIndexForCharacter(at: len - 1)
            var eff = NSRange()
            let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: &eff)
            x = lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc).maxX
            baseline = frag.minY + lm.location(forGlyphAt: gi).y
        }
        let glyphH = lineFont.ascender - lineFont.descender
        let h = (glyphH * 1.2).rounded()
        let top = baseline - lineFont.ascender - (h - glyphH) / 2
        return CGRect(x: origin.x + x - Self.caretWidth / 2, y: origin.y + top, width: Self.caretWidth, height: h)
    }

    func updateCaret(animated: Bool) {
        guard caretVisible, let r = caretRect() else {
            caret.opacity = 0
            caretTrail.opacity = 0
            caretTrail.removeAnimation(forKey: "movementTrail")
            return
        }
        let loc = min(selectedRange().location, (string as NSString).length)
        var moved = false
        if animated, let pendingTrailSide {
            trailSide = pendingTrailSide
            moved = true
        } else if animated, let previous = lastObservedCaretLocation {
            if loc > previous { trailSide = .left; moved = true }
            if loc < previous { trailSide = .right; moved = true }
        }
        if animated || lastObservedCaretLocation == nil { lastObservedCaretLocation = loc }
        lastMove = Date()
        CATransaction.begin()
        if animated && caret.opacity > 0 {
            CATransaction.setAnimationDuration(0.12)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        caret.frame = r
        let lineStart = (string as NSString).lineRange(for: NSRange(location: loc, length: 0)).location
        let maxWidth = max(24, r.height * 1.25)
        let width = trailSide == .left
            ? (loc > lineStart ? min(maxWidth, max(0, r.midX - textContainerOrigin.x)) : 0)
            : maxWidth
        caretTrail.startPoint = CGPoint(x: trailSide == .left ? 0 : 1, y: 0.5)
        caretTrail.endPoint = CGPoint(x: trailSide == .left ? 1 : 0, y: 0.5)
        caretTrail.frame = CGRect(x: trailSide == .left ? r.midX - width : r.midX,
                                  y: r.minY - 3, width: width, height: r.height + 6)
        trailMask.frame = caretTrail.bounds
        caret.opacity = 1
        // The glow only exists while the caret travels; at rest it is fully gone.
        caretTrail.opacity = 0
        CATransaction.commit()
        if moved && width > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let trail = CABasicAnimation(keyPath: "opacity")
            trail.fromValue = 0.9
            trail.toValue = 0
            trail.duration = Self.trailDuration
            trail.timingFunction = CAMediaTimingFunction(name: .easeOut)
            caretTrail.add(trail, forKey: "movementTrail")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let lm = layoutManager as? TwainLayoutManager {
            lm.taskHitRects = []
            lm.embedHitRects = []
            // Only rects in the redrawn area are rebuilt; keep the rest.
            lm.blockHitRects.removeAll { $0.rect.intersects(dirtyRect) }
            lm.foldHitRects.removeAll { $0.0.intersects(dirtyRect) }
        }
        super.draw(dirtyRect)
        drawGhost()
    }

    private func drawGhost() {
        guard !ghost.isEmpty, let lm = layoutManager, let tc = textContainer, let storage = textStorage else { return }
        let caret = selectedRange().location
        guard caret > 0, caret <= storage.length else { return }
        let gi = lm.glyphIndexForCharacter(at: caret - 1)
        let r = lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc)
        var eff = NSRange()
        let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: &eff)
        let origin = textContainerOrigin
        let font = (storage.attribute(.font, at: caret - 1, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: 17)
        let baseline = origin.y + frag.minY + lm.location(forGlyphAt: gi).y
        let text = NSAttributedString(string: ghost, attributes: [.font: font, .foregroundColor: Theme.NS.ghost])
        let x = origin.x + r.maxX
        text.draw(at: NSPoint(x: x, y: baseline - font.ascender))
        let pillFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let pill = NSAttributedString(string: "Tab", attributes: [.font: pillFont, .foregroundColor: Theme.NS.ghostPillText])
        let ps = pill.size()
        let pr = CGRect(x: x + text.size().width + 8, y: baseline - ps.height + 2, width: ps.width + 10, height: 16)
        let path = NSBezierPath(roundedRect: pr, xRadius: 4, yRadius: 4)
        Theme.NS.ghostPill.setStroke()
        path.lineWidth = 1
        path.stroke()
        pill.draw(at: NSPoint(x: pr.minX + 5, y: pr.midY - ps.height / 2))
    }
}

/// Keeps the text view exactly as wide as the visible area.
final class EditorScrollView: NSScrollView {
    var onTile: (() -> Void)?

    override func tile() {
        super.tile()
        DispatchQueue.main.async { self.onTile?() }
        if let doc = documentView, doc.frame.width != contentView.bounds.width {
            doc.setFrameSize(NSSize(width: contentView.bounds.width, height: doc.frame.height))
        }
    }
}

