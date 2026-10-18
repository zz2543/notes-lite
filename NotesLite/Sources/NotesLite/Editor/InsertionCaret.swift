import AppKit
import QuartzCore

/// A visual insertion point only. TextKit continues to own selection, hit testing and IME rects.
@MainActor final class InsertionCaret {
    let layer = CALayer()
    private(set) var rect: CGRect?

    init() {
        layer.anchorPoint = .zero
        layer.cornerRadius = 1
        layer.opacity = 0
        layer.zPosition = 10
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "backgroundColor": NSNull()]
    }

    func hide() {
        layer.removeAllAnimations()
        layer.opacity = 0
        rect = nil
    }

    func show(at target: CGRect, color: NSColor, animated: Bool) {
        layer.backgroundColor = color.cgColor
        guard rect != target else { return }
        let previous = layer.presentation()?.position ?? layer.position
        // TextKit can refine the insertion rect after committing text (font fallback,
        // hidden Markdown syntax, IME attributes). Carry an active travel through those
        // layout-only updates instead of snapping it to the corrected destination.
        let shouldTravel = animated || layer.animation(forKey: "travel") != nil
        let wasVisible = rect != nil
        rect = target
        layer.removeAnimation(forKey: "travel")
        layer.position = target.origin
        layer.bounds = CGRect(origin: .zero, size: target.size)
        layer.opacity = 1
        if shouldTravel && wasVisible && previous != target.origin {
            // Retarget from the currently displayed position, including rapid direction changes.
            let travel = CABasicAnimation(keyPath: "position")
            travel.fromValue = NSValue(point: previous)
            travel.toValue = NSValue(point: target.origin)
            travel.duration = 0.12
            travel.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(travel, forKey: "travel")
        }
        layer.removeAnimation(forKey: "blink")
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0, 1]
        blink.keyTimes = [0, 0.38, 0.5, 0.88, 1]
        blink.duration = 1.06
        blink.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + 0.65
        blink.repeatCount = .infinity
        layer.add(blink, forKey: "blink")
    }
}

extension NoteTextView {
    /// The horizontal insertion position comes from AppKit (including bidi and wrapped text).
    /// Only the vertical geometry is replaced: line spacing must not enlarge the caret.
    func insertionCaretRect() -> CGRect? {
        guard let window, let storage = textStorage, let lm = layoutManager,
              textContainer != nil, selectedRange().location != NSNotFound else { return nil }
        // An IME may select its candidate inside marked text. Its visual insertion
        // point belongs at that candidate's end, while AppKit retains the real selection.
        let location = min(hasMarkedText() ? NSMaxRange(selectedRange()) : selectedRange().location, storage.length)
        lm.ensureLayout(forCharacterRange: NSRange(location: max(0, location - 1), length: min(storage.length, location + 1) - max(0, location - 1)))
        let screenRect = firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        let native = convert(window.convertFromScreen(screenRect), from: nil)
        var font = (typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 17)
        let baseline: CGFloat
        if storage.length == 0 || (location == storage.length && lm.extraLineFragmentTextContainer != nil) {
            baseline = textContainerOrigin.y + lm.extraLineFragmentRect.minY + lm.defaultBaselineOffset(for: font)
        } else {
            let index = min(location, storage.length - 1)
            font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? font
            let glyph = lm.glyphIndexForCharacter(at: index)
            baseline = textContainerOrigin.y + lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + lm.location(forGlyphAt: glyph).y
        }
        let scale = window.backingScaleFactor
        // Optical height follows the type size, centered within its ascent/descent envelope.
        // Font metrics include room for accents that otherwise makes a CJK caret look too tall.
        let height = min(font.ascender - font.descender + 2, font.pointSize + 6)
        let top = baseline - (font.ascender + font.descender) / 2 - height / 2
        return CGRect(x: ((native.minX + 1) * scale).rounded() / scale,
                      y: (top * scale).rounded() / scale, width: 2.5,
                      height: (height * scale).rounded() / scale)
    }

    func updateInsertionCaret(animated: Bool) {
        // Native input emits intermediate selection/layout notifications while replacing
        // marked text. Present only the final position of that synchronous input update.
        guard caretInputDepth == 0 else { return }
        guard window?.firstResponder === self, window?.isKeyWindow == true,
              isEditable, selectedRanges.count == 1, (selectedRange().length == 0 || hasMarkedText()),
              let rect = insertionCaretRect() else { insertionCaret.hide(); return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            insertionCaret.show(at: rect, color: .controlAccentColor, animated: animated)
        }
    }
}
