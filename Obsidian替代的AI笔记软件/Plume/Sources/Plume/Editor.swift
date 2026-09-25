import AppKit
import PlumeCore
import SwiftUI

extension NSAttributedString.Key {
    static let plumeHidden = NSAttributedString.Key("plumeHidden")
    static let plumeDeco = NSAttributedString.Key("plumeDeco")
    static let plumeWikiLink = NSAttributedString.Key("plumeWikiLink")
    static let plumeURL = NSAttributedString.Key("plumeURL")
}

/// Decoration drawn in the margin of a rendered (inactive) paragraph.
final class Deco: NSObject {
    enum Kind { case bullet, number(Int), task(done: Bool), quote, hr }
    let kind: Kind
    let line: Int
    init(_ kind: Kind, line: Int) { self.kind = kind; self.line = line }
}

struct EditorStyle: Equatable {
    var font: EditorFont
    var typewriter: Bool
    var dim: Bool
    var zen: Bool
    var width: CGFloat
}

// MARK: - Layout manager: hides syntax glyphs and draws decorations

final class PlumeLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let storage = lm.textStorage else { return 0 }
        var newProps: [NSLayoutManager.GlyphProperty]?
        for i in 0..<range.length {
            let ci = characterIndexes[i]
            guard ci < storage.length, storage.attribute(.plumeHidden, at: ci, effectiveRange: nil) != nil else { continue }
            if newProps == nil { newProps = Array(UnsafeBufferPointer(start: props, count: range.length)) }
            newProps![i] = .null
        }
        guard let newProps else { return 0 }
        lm.setGlyphs(glyphs, properties: newProps, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return range.length
    }

    /// Checkbox rects in text-view coordinates, rebuilt on every draw, used for clicks.
    var taskHitRects: [(CGRect, Int)] = []

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.plumeDeco, in: chars) { value, range, _ in
            guard let deco = value as? Deco else { return }
            var gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard numberOfGlyphs > 0 else { return }
            // Hidden prefix glyphs have no real position; anchor on the first visible one.
            var first = min(gr.location, numberOfGlyphs - 1)
            while first < NSMaxRange(gr) - 1, propertyForGlyph(at: first) == .null { first += 1 }
            gr = NSRange(location: first, length: max(0, NSMaxRange(gr) - first))
            var eff = NSRange()
            let frag = lineFragmentRect(forGlyphAt: first, effectiveRange: &eff)
            let para = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: 17)
            let textX = origin.x + frag.minX + (para?.firstLineHeadIndent ?? 0)
            let baseline = origin.y + frag.minY + location(forGlyphAt: first).y
            let lineTop = origin.y + frag.minY
            let lineH = frag.height - (para?.lineSpacing ?? 0)
            switch deco.kind {
            case .bullet:
                draw("•", font: font, color: Theme.NS.deco, x: textX - 17, baseline: baseline)
            case let .number(n):
                let attrs: [NSAttributedString.Key: Any] = [.font: font.monospacedDigits, .foregroundColor: Theme.NS.deco]
                let s = NSAttributedString(string: "\(n).", attributes: attrs)
                s.draw(at: NSPoint(x: textX - 22, y: baseline - font.ascender))
            case let .task(done):
                let box = CGRect(x: textX - 22, y: lineTop + (lineH - 14) / 2, width: 14, height: 14)
                taskHitRects.append((box.insetBy(dx: -4, dy: -4), deco.line))
                let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
                path.lineWidth = 1.5
                if done {
                    Theme.NS.accent.setFill(); path.fill()
                    Theme.NS.accent.setStroke(); path.stroke()
                    let check = NSAttributedString(string: "✓", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white])
                    let sz = check.size()
                    check.draw(at: NSPoint(x: box.midX - sz.width / 2, y: box.midY - sz.height / 2))
                } else {
                    Theme.NS.taskBorder.setStroke(); path.stroke()
                }
            case .quote:
                var lastEff = NSRange()
                let lastFrag = lineFragmentRect(forGlyphAt: max(first, NSMaxRange(gr) - 1), effectiveRange: &lastEff)
                let bottom = lastFrag.maxY - (para?.lineSpacing ?? 0)
                let bar = CGRect(x: origin.x + frag.minX, y: lineTop, width: 3, height: max(lineH, origin.y + bottom - lineTop))
                Theme.NS.quoteBar.setFill()
                bar.fill()
            case .hr:
                let y = lineTop + lineH / 2
                Theme.NS.hr.setFill()
                CGRect(x: origin.x + frag.minX, y: y, width: container.size.width, height: 1).fill()
            }
        }
    }

    private func draw(_ s: String, font: NSFont, color: NSColor, x: CGFloat, baseline: CGFloat) {
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        a.draw(at: NSPoint(x: x, y: baseline - font.ascender))
    }
}

private extension NSFont {
    var monospacedDigits: NSFont {
        let d = fontDescriptor.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                                                      NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}

// MARK: - Text view

final class PlumeTextView: NSTextView {
    weak var coordinator: EditorView.Coordinator?
    var ghost = "" { didSet { if ghost != oldValue { needsDisplay = true } } }
    var topInset: CGFloat = 56
    var bottomInset: CGFloat = 300

    override var textContainerOrigin: NSPoint {
        NSPoint(x: textContainerInset.width, y: topInset)
    }

    func updateInsets(style: EditorStyle, visibleHeight: CGFloat) {
        let w = bounds.width
        let pad: CGFloat = w < 700 ? 20 : 48
        let side = max(pad, (w - style.width) / 2)
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
        lm.ensureLayout(for: tc)
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

    override func doCommand(by selector: Selector) {
        if coordinator?.handle(selector) == true { return }
        super.doCommand(by: selector)
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
    private static let restingTrailOpacity: Float = 0.28
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
            caretTrail.opacity = Self.restingTrailOpacity
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        let visible = caret.opacity <= 0.5
        caret.opacity = visible ? 1 : 0
        caretTrail.opacity = visible ? Self.restingTrailOpacity : 0
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
        caretTrail.opacity = width > 0 ? Self.restingTrailOpacity : 0
        CATransaction.commit()
        if moved && width > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let trail = CABasicAnimation(keyPath: "opacity")
            trail.fromValue = 0.9
            trail.toValue = Self.restingTrailOpacity
            trail.duration = Self.trailDuration
            trail.timingFunction = CAMediaTimingFunction(name: .easeOut)
            caretTrail.add(trail, forKey: "movementTrail")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        (layoutManager as? PlumeLayoutManager)?.taskHitRects = []
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

// MARK: - SwiftUI bridge

struct EditorView: NSViewRepresentable {
    @Bindable var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let lm = PlumeLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        lm.addTextContainer(container)

        let tv = PlumeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
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
        let style = EditorStyle(font: model.font, typewriter: model.typewriter, dim: model.dim, zen: model.zen, width: model.editorWidth)
        c.sync(version: model.editorVersion, text: model.editorText, style: style,
               ghost: model.ghost, readOnly: model.editorReadOnly, focus: model.focusRequest)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: PlumeTextView?
        weak var scrollView: NSScrollView?
        private var version = -1
        private var style: EditorStyle?
        private var focusToken = -1
        private var activeLine: Int?
        private var restyling = false

        init(model: AppModel) {
            self.model = model
            super.init()
            NotificationCenter.default.addObserver(forName: .plumeApplySlash, object: nil, queue: .main) { [weak self] n in
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
                    storage.beginEditing()
                    storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
                    storage.endEditing()
                    tv.undoManager?.removeAllActions()
                    let len = (text as NSString).length
                    tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
                    tv.resetCaretTrailTracking()
                    if focus == nil || focus!.token == focusToken { tv.scroll(.zero) }
                }
                needsRestyle = true
            }
            if s != style {
                style = s
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

        func currentLine() -> Int? {
            guard let tv = textView, isFocused else { return nil }
            return newlines(in: tv.string as NSString, upTo: tv.selectedRange().location)
        }

        private func newlines(in ns: NSString, upTo end: Int) -> Int {
            var n = 0
            let limit = min(end, ns.length)
            var i = 0
            while i < limit {
                if ns.character(at: i) == 0x0A { n += 1 }
                i += 1
            }
            return n
        }

        func restyle() {
            guard let tv = textView, let storage, let style, !restyling else { return }
            if tv.hasMarkedText() { return }
            restyling = true
            defer { restyling = false }
            let active = currentLine()
            activeLine = active
            let F = style.font
            let bodySize: CGFloat = F == .mono ? 15.5 : 17
            let body = F.nsFont(size: bodySize)

            tv.holdingHeight {
                storage.beginEditing()
                let full = NSRange(location: 0, length: storage.length)
                storage.setAttributes([.font: body, .foregroundColor: Theme.NS.ink], range: full)
                let dimOthers = style.dim && active != nil
                let lines = storage.string.components(separatedBy: "\n")
                var loc = 0
                for (i, text) in lines.enumerated() {
                    let len = (text as NSString).length
                    let range = NSRange(location: loc, length: len)
                    let line = NSRange(location: loc, length: len + (i < lines.count - 1 ? 1 : 0))
                    styleLine(text, range: range, fullRange: line, line: i, isActive: i == active,
                              dimmed: dimOthers && i != active, font: F, bodySize: bodySize)
                    loc += line.length
                }
                storage.endEditing()
                if let lm = tv.layoutManager {
                    lm.invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
                    lm.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
                }
            }
            tv.typingAttributes = [.font: body, .foregroundColor: Theme.NS.ink, .paragraphStyle: paragraph(for: .p, font: body, first: false, active: true)]
            tv.needsDisplay = true
            tv.updateCaret(animated: true)
        }

        private func paragraph(for type: BlockType, font: NSFont, first: Bool, active: Bool) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            let lh: CGFloat = type.isHeading ? 1.35 : 1.8
            let natural = font.ascender - font.descender + font.leading
            p.lineSpacing = max(0, font.pointSize * lh - natural)
            switch type {
            case .h1: p.paragraphSpacingBefore = first ? 0 : 30; p.paragraphSpacing = 16
            case .h2: p.paragraphSpacingBefore = first ? 0 : 30; p.paragraphSpacing = 10
            case .h3: p.paragraphSpacingBefore = first ? 0 : 22; p.paragraphSpacing = 6
            case .li, .task, .ol: p.paragraphSpacing = 2
            default: p.paragraphSpacing = 12
            }
            var indent: CGFloat = 0
            if type.isList && !active { indent = 26 }
            if type == .quote { indent = 18 }
            p.firstLineHeadIndent = indent
            p.headIndent = indent
            return p
        }

        private func styleLine(_ text: String, range: NSRange, fullRange: NSRange, line: Int, isActive: Bool,
                               dimmed: Bool, font F: EditorFont, bodySize: CGFloat) {
            guard let storage else { return }
            let m = Markdown.parseLine(text)
            let type = m.type
            let size: CGFloat = type == .h1 ? 30 : type == .h2 ? 22 : type == .h3 ? 18 : bodySize
            let weight: NSFont.Weight = type == .h1 ? .bold : type == .h2 ? .semibold : type == .h3 ? .semibold : .regular
            let font = F.nsFont(size: size, weight: weight)
            let para = paragraph(for: type, font: font, first: line == 0, active: isActive)
            let alpha: CGFloat = dimmed ? 0.26 : 1
            var color = type == .quote ? Theme.NS.quote : Theme.NS.ink
            color = color.withAlphaComponent(alpha)
            let styleRange = fullRange.length > 0 ? fullRange : range
            if styleRange.length > 0 {
                storage.addAttributes([.font: font, .paragraphStyle: para, .foregroundColor: color], range: styleRange)
                if type == .h1 { storage.addAttribute(.kern, value: -0.012 * size, range: range) }
            }
            if !isActive, styleRange.length > 0 {
                let deco: Deco.Kind? = switch type {
                case .li: .bullet
                case .ol: .number(Markdown.orderedNumber(text) ?? 1)
                case .task: .task(done: Markdown.isTaskDone(text))
                case .quote: .quote
                case .hr: .hr
                default: nil
                }
                if let deco { storage.addAttribute(.plumeDeco, value: Deco(deco, line: line), range: styleRange) }
            }
            guard range.length > 0 else { return }
            let abs = { (r: NSRange) in NSRange(location: range.location + r.location, length: r.length) }

            if type == .hr {
                if isActive { storage.addAttribute(.foregroundColor, value: Theme.NS.mark.withAlphaComponent(alpha), range: range) }
                else { storage.addAttribute(.plumeHidden, value: true, range: range) }
                return
            }
            if type == .task, Markdown.isTaskDone(text), !isActive {
                let body = NSRange(location: range.location + m.prefix.length, length: range.length - m.prefix.length)
                storage.addAttributes([.foregroundColor: Theme.NS.doneText.withAlphaComponent(alpha),
                                       .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .strikethroughColor: Theme.NS.strike], range: body)
            }
            for span in m.spans {
                let r = abs(span.content)
                switch span.kind {
                case .bold:
                    storage.addAttribute(.font, value: F.nsFont(size: size, weight: type.isHeading ? .heavy : .semibold), range: r)
                case .italic:
                    storage.addAttribute(.font, value: F.nsFont(size: size, weight: weight, italic: true), range: r)
                case .code:
                    storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size * 0.84, weight: .regular),
                                           .backgroundColor: Theme.NS.codeBg], range: r)
                case let .wikilink(title):
                    storage.addAttributes([.foregroundColor: Theme.NS.accent.withAlphaComponent(alpha),
                                           .underlineStyle: NSUnderlineStyle.single.rawValue,
                                           .underlineColor: Theme.NS.accent.withAlphaComponent(0.3 * alpha),
                                           .plumeWikiLink: title], range: r)
                case let .link(url):
                    storage.addAttributes([.foregroundColor: Theme.NS.accent.withAlphaComponent(alpha),
                                           .underlineStyle: NSUnderlineStyle.single.rawValue,
                                           .plumeURL: url], range: r)
                }
            }
            for mark in m.allMarks {
                let r = abs(mark)
                if isActive {
                    storage.addAttribute(.foregroundColor, value: Theme.NS.mark, range: r)
                    storage.removeAttribute(.backgroundColor, range: r)
                } else {
                    storage.addAttribute(.plumeHidden, value: true, range: r)
                }
            }
        }

        // MARK: text changes

        func textDidChange(_ notification: Notification) {
            textView?.updateCaret(animated: true)
            guard let tv = textView, !tv.hasMarkedText() else { return }
            model.editorDidChange(tv.string)
            restyle()
            updateSlash()
            center(smooth: true)
            schedulePause()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            textView?.updateCaret(animated: true)
            guard let tv = textView, !tv.hasMarkedText(), !restyling else { return }
            if currentLine() != activeLine { restyle() }
            updateSlash()
            if tv.selectedRange().length == 0 { center(smooth: true) }
        }

        private func lineInfo() -> (text: String, range: NSRange, index: Int)? {
            guard let tv = textView else { return nil }
            let ns = tv.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            var r = ns.lineRange(for: NSRange(location: loc, length: 0))
            if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
            return (ns.substring(with: r), r, currentLine() ?? 0)
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
            guard let tv = textView, isFocused, let info = lineInfo(), let items = SlashItem.matching(info.text),
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
            let state = SlashState(items: items, selection: sel, anchor: CGPoint(x: inScroll.minX, y: top - (tv.defaultParagraphStyle?.lineSpacing ?? 0) + 6))
            if model.slash != state { model.slash = state }
        }

        func applySlash(_ item: SlashItem) {
            guard let tv = textView, let info = lineInfo() else { return }
            model.slash = nil
            if let agent = item.ai {
                tv.insertText("", replacementRange: info.range)
                model.runAgent(prompt: agent == .claude ? "根据上下文续写这篇笔记，保持我的语气" : "整理这篇笔记的结构和待办", agent: agent)
                return
            }
            if item.hr {
                tv.insertText("---\n", replacementRange: info.range)
                return
            }
            tv.insertText(item.prefix, replacementRange: info.range)
        }

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
                guard let info = lineInfo() else { return false }
                if let cont = Markdown.continuation(for: info.text) {
                    if cont.exit {
                        tv.insertText("", replacementRange: info.range)
                    } else {
                        tv.insertText("\n" + cont.prefix, replacementRange: tv.selectedRange())
                    }
                    return true
                }
                return false
            case #selector(NSResponder.insertTab(_:)):
                acceptGhost()
                return true
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

        // MARK: clicks

        func handleClick(at p: NSPoint, event: NSEvent) -> Bool {
            guard let tv = textView, let lm = tv.layoutManager as? PlumeLayoutManager, let tc = tv.textContainer, let storage else { return false }
            if let hit = lm.taskHitRects.first(where: { $0.0.contains(p) }) {
                toggleTask(line: hit.1)
                return true
            }
            let origin = tv.textContainerOrigin
            let local = NSPoint(x: p.x - origin.x, y: p.y - origin.y)
            var fraction: CGFloat = 0
            let gi = lm.glyphIndex(for: local, in: tc, fractionOfDistanceThroughGlyph: &fraction)
            guard gi < lm.numberOfGlyphs, lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc).contains(local) else { return false }
            let ci = lm.characterIndexForGlyph(at: gi)
            guard ci < storage.length else { return false }
            let clickedLine = lineNumber(at: ci)
            let followable = event.modifierFlags.contains(.command) || clickedLine != activeLine
            if followable, let title = storage.attribute(.plumeWikiLink, at: ci, effectiveRange: nil) as? String {
                model.openByTitle(title)
                return true
            }
            if followable, let url = storage.attribute(.plumeURL, at: ci, effectiveRange: nil) as? String, let u = URL(string: url) {
                NSWorkspace.shared.open(u)
                return true
            }
            return false
        }

        private func lineNumber(at ci: Int) -> Int {
            guard let tv = textView else { return 0 }
            return newlines(in: tv.string as NSString, upTo: ci)
        }

        private func toggleTask(line: Int) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            var loc = 0
            for _ in 0..<line {
                let r = ns.lineRange(for: NSRange(location: loc, length: 0))
                loc = NSMaxRange(r)
            }
            var r = ns.lineRange(for: NSRange(location: loc, length: 0))
            if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
            let text = ns.substring(with: r)
            let toggled = Markdown.toggleTask(text)
            guard toggled != text, tv.shouldChangeText(in: NSRange(location: r.location, length: 6), replacementString: String(toggled.prefix(6))) else { return }
            tv.textStorage?.replaceCharacters(in: NSRange(location: r.location, length: 6), with: String(toggled.prefix(6)))
            tv.didChangeText()
        }

        // MARK: scrolling

        func center(smooth: Bool) {
            guard let tv = textView, let scroll = scrollView, let lm = tv.layoutManager, let tc = tv.textContainer, let style else { return }
            lm.ensureLayout(for: tc)
            let loc = min(tv.selectedRange().location, (tv.string as NSString).length)
            let caretRect: CGRect
            if lm.numberOfGlyphs == 0 {
                caretRect = CGRect(x: 0, y: tv.textContainerOrigin.y, width: 1, height: 20)
            } else {
                let gi = loc >= (tv.string as NSString).length ? max(0, lm.numberOfGlyphs - 1) : lm.glyphIndexForCharacter(at: loc)
                var r = NSRange()
                var frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: &r)
                if loc >= (tv.string as NSString).length, lm.extraLineFragmentTextContainer != nil { frag = lm.extraLineFragmentRect }
                caretRect = frag.offsetBy(dx: 0, dy: tv.textContainerOrigin.y)
            }
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
