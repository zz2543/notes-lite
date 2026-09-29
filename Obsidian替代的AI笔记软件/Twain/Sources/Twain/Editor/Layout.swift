import AppKit

/// Hides syntax glyphs and draws what replaces them: bullets, checkboxes, quote bars, code
/// block backgrounds, rules and embedded pictures.
final class TwainLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
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
        // Attribute runs are looked up once each, not per character.
        var runEnd = -1
        var hidden = false, inline = false
        for i in 0..<range.length {
            let ci = characterIndexes[i]
            guard ci < storage.length else { continue }
            if ci >= runEnd {
                var eff = NSRange()
                let attrs = storage.attributes(at: ci, effectiveRange: &eff)
                hidden = attrs[.twainHidden] != nil
                inline = attrs[.twainInline] != nil
                runEnd = NSMaxRange(eff)
            }
            guard hidden || inline else { continue }
            if newProps == nil { newProps = Array(UnsafeBufferPointer(start: props, count: range.length)) }
            // Inline math: one control glyph as wide as the picture (see boundingBoxForControlGlyph).
            newProps![i] = inline ? .controlCharacter : .null
        }
        guard let newProps else { return 0 }
        lm.setGlyphs(glyphs, properties: newProps, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return range.length
    }

    func layoutManager(_ lm: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        if let s = lm.textStorage, charIndex < s.length, s.attribute(.twainInline, at: charIndex, effectiveRange: nil) != nil { return .whitespace }
        return action
    }

    func layoutManager(_ lm: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer,
                       proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex: Int) -> NSRect {
        guard let s = lm.textStorage, characterIndex < s.length,
              let pic = s.attribute(.twainInline, at: characterIndex, effectiveRange: nil) as? InlinePicture else { return .zero }
        let r = pic.rendered
        return NSRect(x: glyphPosition.x, y: glyphPosition.y - r.baseline, width: r.size.width + 2, height: r.size.height)
    }

    /// Checkbox rects in text-view coordinates with the start of their line, rebuilt on every draw.
    var taskHitRects: [(CGRect, Int)] = []
    /// Pictures and videos drawn in place, for clicks.
    var embedHitRects: [(CGRect, Embed)] = []
    /// Tables, formulas, diagrams and embedded notes, with where their source starts.
    var blockHitRects: [(rect: CGRect, deco: BlockDeco, start: Int)] = []
    /// Callout fold chevrons, by the callout's key.
    var foldHitRects: [(CGRect, String)] = []
    /// Passages with an annotation: a soft marker under the text, stronger for the selected one.
    var highlights: [(range: NSRange, color: NSColor, selected: Bool)] = []

    /// Paragraph focus: characters outside `focus` are drawn faded. Applied while drawing, so
    /// moving the caret to another line or focusing the editor redraws the screen and nothing
    /// else; the text's attributes never depend on it. Nil draws everything at full strength.
    var focus: NSRange?
    static let dimAlpha: CGFloat = 0.26

    func alpha(forCharacters r: NSRange) -> CGFloat {
        guard let f = focus else { return 1 }
        let inside = r.length == 0 ? NSLocationInRange(r.location, f) || r.location == NSMaxRange(f) : NSIntersectionRange(f, r).length > 0
        return inside ? 1 : Self.dimAlpha
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let f = focus, glyphsToShow.length > 0 else { return super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin) }
        let fg = glyphRange(forCharacterRange: f, actualCharacterRange: nil)
        let start = glyphsToShow.location, end = NSMaxRange(glyphsToShow)
        let a = max(start, min(end, fg.location)), b = max(a, min(end, NSMaxRange(fg)))
        drawGlyphs(start, a, alpha: Self.dimAlpha, at: origin)
        drawGlyphs(a, b, alpha: 1, at: origin)
        drawGlyphs(b, end, alpha: Self.dimAlpha, at: origin)
    }

    private func drawGlyphs(_ lo: Int, _ hi: Int, alpha: CGFloat, at origin: NSPoint) {
        guard hi > lo else { return }
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        if alpha < 1 { ctx?.setAlpha(alpha) }
        super.drawGlyphs(forGlyphRange: NSRange(location: lo, length: hi - lo), at: origin)
        ctx?.restoreGState()
    }

    /// Inline code and highlights: a rounded box around the glyphs instead of the whole line height.
    /// The selection comes through here too, as one tall rect for all its middle lines; it is
    /// left to the default fill (it is not the run's own background color).
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        guard let storage = textStorage, charRange.location < storage.length,
              storage.attribute(.backgroundColor, at: charRange.location, effectiveRange: nil) as? NSColor == color,
              let font = storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? NSFont,
              (storage.attribute(.paragraphStyle, at: charRange.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0 > 0 else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        let gi = glyphIndexForCharacter(at: charRange.location)
        let baseline = location(forGlyphAt: gi).y
        let text = (font.ascender - font.descender)
        color.withAlphaComponent(color.alphaComponent * alpha(forCharacters: charRange)).setFill()
        for i in 0..<rectCount {
            let r = rectArray[i]
            // Each rect spans its line fragment (view coordinates): place the box on the baseline.
            let box = CGRect(x: r.minX - 2, y: r.minY + baseline - font.ascender - 2, width: r.width + 4, height: text + 4)
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first, glyphsToShow.length > 0 else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // Whole paragraphs, so a block that starts above the dirty rect still draws its part.
        let paras = (storage.string as NSString).paragraphRange(for: chars)
        let width = container.size.width
        for h in highlights where NSIntersectionRange(h.range, paras).length > 0 && NSMaxRange(h.range) <= storage.length {
            let gr = glyphRange(forCharacterRange: h.range, actualCharacterRange: nil)
            enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                let font = (storage.attribute(.font, at: h.range.location, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: 17)
                let spacing = (storage.attribute(.paragraphStyle, at: h.range.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
                // The rect spans the line with its spacing below; mark just the glyph band.
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                let bandH = font.ascender - font.descender + 2
                let band = CGRect(x: r.minX - 1, y: r.minY + max(0, (r.height - spacing - bandH) / 2), width: r.width + 2, height: bandH)
                h.color.withAlphaComponent(h.selected ? 0.28 : 0.13).setFill()
                NSBezierPath(roundedRect: band, xRadius: 3, yRadius: 3).fill()
                h.color.withAlphaComponent(h.selected ? 0.9 : 0.55).setFill()
                CGRect(x: band.minX, y: band.maxY - 1.5, width: band.width, height: 1.5).fill()
            }
        }
        storage.enumerateAttribute(.twainDeco, in: paras) { value, range, _ in
            guard let deco = value as? Deco else { return }
            draw(deco, range: range, storage: storage, origin: origin, width: width)
        }
        storage.enumerateAttribute(.twainEmbed, in: paras) { value, range, _ in
            guard let e = value as? EmbedDeco else { return }
            draw(e, range: range, origin: origin)
        }
        storage.enumerateAttribute(.twainBlock, in: paras) { value, range, _ in
            guard let b = value as? BlockDeco else { return }
            draw(b, range: range, origin: origin, width: width)
        }
        storage.enumerateAttribute(.twainInline, in: paras) { value, range, _ in
            guard let pic = value as? InlinePicture, let img = pic.rendered.image else { return }
            let gi = glyphIndexForCharacter(at: range.location)
            guard gi < numberOfGlyphs else { return }
            let frag = lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
            let loc = location(forGlyphAt: gi)
            let r = pic.rendered
            let rect = CGRect(x: origin.x + frag.minX + loc.x + 1, y: origin.y + frag.minY + loc.y - r.baseline, width: r.size.width, height: r.size.height)
            // Dimmed paragraphs dim their formulas too.
            img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha(forCharacters: range), respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
    }

    private func draw(_ b: BlockDeco, range: NSRange, origin: NSPoint, width: CGFloat) {
        let fs = frags(range)
        guard let first = fs.first, let last = fs.last else { return }
        let para = textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let y = b.revealed ? origin.y + last.used.maxY + 14 : origin.y + first.rect.minY + (para?.paragraphSpacingBefore ?? 0)
        let gutter = MarkdownStyler.gutter
        let frame = CGRect(x: origin.x + gutter, y: y, width: max(40, width - 2 * gutter), height: b.height)
        let drawn = b.draw(in: frame, alpha: alpha(forCharacters: range))
        blockHitRects.append((drawn, b, range.location))
    }

    /// Line fragments of a paragraph. Hidden glyphs at a line's start sit in the previous
    /// line's fragment, so the paragraph starts at its first visible glyph (or its newline).
    private func frags(_ range: NSRange) -> [(rect: CGRect, used: CGRect, glyphs: NSRange)] {
        var gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var out: [(CGRect, CGRect, NSRange)] = []
        guard gr.length > 0 else { return out }
        var first = gr.location
        while first < NSMaxRange(gr) - 1, propertyForGlyph(at: first) == .null { first += 1 }
        gr = NSRange(location: first, length: NSMaxRange(gr) - first)
        enumerateLineFragments(forGlyphRange: gr) { rect, used, _, g, _ in out.append((rect, used, g)) }
        return out
    }

    /// Baseline and x-height center of the paragraph's first visible line, in view coordinates.
    private func firstLine(_ range: NSRange, storage: NSTextStorage, origin: NSPoint) -> (top: CGFloat, baseline: CGFloat, mid: CGFloat, font: NSFont)? {
        let gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard gr.length > 0 else { return nil }
        var first = gr.location
        while first < NSMaxRange(gr) - 1, propertyForGlyph(at: first) == .null { first += 1 }
        let frag = lineFragmentRect(forGlyphAt: first, effectiveRange: nil)
        let ci = characterIndexForGlyph(at: first)
        let font = (storage.attribute(.font, at: min(ci, storage.length - 1), effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: 17)
        let para = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let top = origin.y + frag.minY + (para?.paragraphSpacingBefore ?? 0)
        let baseline = origin.y + frag.minY + location(forGlyphAt: first).y
        return (top, baseline, baseline - font.xHeight / 2, font)
    }

    private func draw(_ deco: Deco, range: NSRange, storage: NSTextStorage, origin: NSPoint, width: CGFloat) {
        let x0 = origin.x + deco.contentX
        switch deco.kind {
        case let .bullet(level):
            guard let l = firstLine(range, storage: storage, origin: origin) else { return }
            let r: CGFloat = level == 0 ? 2.8 : 2.6
            let dot = CGRect(x: x0 - 15 - r, y: l.mid - r, width: 2 * r, height: 2 * r)
            Theme.NS.deco.set()
            switch level % 3 {
            case 0: NSBezierPath(ovalIn: dot).fill()
            case 1:
                let p = NSBezierPath(ovalIn: dot.insetBy(dx: 0.6, dy: 0.6))
                p.lineWidth = 1.2
                p.stroke()
            default: NSBezierPath(rect: dot.insetBy(dx: 0.3, dy: 0.3)).fill()
            }
        case let .number(n):
            guard let l = firstLine(range, storage: storage, origin: origin) else { return }
            let s = NSAttributedString(string: n, attributes: [.font: l.font.monospacedDigits, .foregroundColor: Theme.NS.deco])
            s.draw(at: NSPoint(x: x0 - 6 - s.size().width, y: l.baseline - l.font.ascender))
        case let .task(done):
            guard let l = firstLine(range, storage: storage, origin: origin) else { return }
            let box = CGRect(x: x0 - 23, y: l.mid - 7.5, width: 15, height: 15)
            let lineStart = (storage.string as NSString).lineRange(for: NSRange(location: range.location, length: 0)).location
            taskHitRects.append((box.insetBy(dx: -5, dy: -5), lineStart))
            let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4.5, yRadius: 4.5)
            path.lineWidth = 1.5
            if done {
                Theme.NS.accent.setFill(); path.fill()
                Theme.NS.accent.setStroke(); path.stroke()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: box.minX + 4, y: box.midY))
                check.line(to: NSPoint(x: box.minX + 6.6, y: box.maxY - 4))
                check.line(to: NSPoint(x: box.maxX - 3.6, y: box.minY + 4))
                check.lineWidth = 1.8
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            } else {
                Theme.NS.taskBorder.setStroke(); path.stroke()
            }
        case let .quote(depth, tint, head):
            let fs = frags(range)
            guard let firstRect = fs.first?.rect, let lastRect = fs.last?.rect else { return }
            let para = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let top = origin.y + firstRect.minY + (para?.paragraphSpacingBefore ?? 0)
            let bottom = origin.y + lastRect.maxY
            let gutter = MarkdownStyler.gutter
            if let tint {
                tint.withAlphaComponent(0.07).setFill()
                CGRect(x: origin.x + gutter, y: top, width: width - 2 * gutter, height: bottom - top).fill()
            }
            for k in 0...depth {
                (tint ?? Theme.NS.quoteBar).setFill()
                CGRect(x: origin.x + gutter + CGFloat(k) * MarkdownStyler.quoteUnit, y: top, width: 3, height: bottom - top).fill()
            }
            if let head, let tint, let l = firstLine(range, storage: storage, origin: origin) {
                drawCalloutHead(head, tint: tint, x: x0, line: l, right: origin.x + width - gutter)
            }
        case let .footnote(label):
            guard let l = firstLine(range, storage: storage, origin: origin) else { return }
            let font = NSFont.systemFont(ofSize: max(10, l.font.pointSize * 0.78), weight: .medium)
            let s = NSAttributedString(string: label, attributes: [.font: font.monospacedDigits, .foregroundColor: Theme.NS.accent])
            s.draw(at: NSPoint(x: x0 - 8 - s.size().width, y: l.baseline - font.ascender))
        case .hr:
            guard let f = frags(range).first else { return }
            let para = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let y = origin.y + f.rect.minY + (f.rect.height - (para?.paragraphSpacing ?? 0)) / 2
            Theme.NS.hr.setFill()
            CGRect(x: x0, y: y, width: width - deco.contentX - MarkdownStyler.gutter, height: 1).fill()
        case let .code(top, bottom):
            let fs = frags(range)
            guard let firstRect = fs.first?.rect, let lastRect = fs.last?.rect else { return }
            let para = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            var y0 = origin.y + firstRect.minY
            var y1 = origin.y + lastRect.maxY
            if top { y0 += (para?.paragraphSpacingBefore ?? 0) - 4 }
            if bottom { y1 -= (para?.paragraphSpacing ?? 0) - 4 }
            let gutter = MarkdownStyler.gutter
            let rect = CGRect(x: origin.x + gutter, y: y0, width: width - 2 * gutter, height: max(0, y1 - y0))
            Theme.NS.codeBlock.setFill()
            if top || bottom {
                let r: CGFloat = 8
                let path = NSBezierPath()
                // Flipped view: minY is the top edge.
                path.move(to: NSPoint(x: rect.minX, y: top ? rect.minY + r : rect.minY))
                if top {
                    path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: 180, endAngle: 270)
                    path.line(to: NSPoint(x: rect.maxX - r, y: rect.minY))
                    path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 270, endAngle: 360)
                } else {
                    path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
                }
                if bottom {
                    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - r))
                    path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: 90)
                    path.line(to: NSPoint(x: rect.minX + r, y: rect.maxY))
                    path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: 90, endAngle: 180)
                } else {
                    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                    path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
                }
                path.close()
                path.fill()
            } else {
                rect.fill()
            }
        }
    }

    /// A callout's icon before its title (or its kind when it has none) and, when it folds, a chevron.
    private func drawCalloutHead(_ head: CalloutHead, tint: NSColor, x: CGFloat, line l: (top: CGFloat, baseline: CGFloat, mid: CGFloat, font: NSFont), right: CGFloat) {
        let side: CGFloat = 16
        // From the line's top: an untitled head has only hidden glyphs, whose baseline isn't the text's.
        let baseline = l.top + l.font.ascender
        let capMid = baseline - l.font.capHeight / 2
        if let icon = NSImage(systemSymbolName: CalloutHead.symbol(head.kind), accessibilityDescription: head.kind)?
            .withSymbolConfiguration(.init(pointSize: side * 0.85, weight: .semibold)) {
            let s = icon.size
            let scale = min(side / s.width, side / s.height)
            let r = CGRect(x: x + 1, y: capMid - s.height * scale / 2, width: s.width * scale, height: s.height * scale)
            icon.tinted(tint).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if head.untitled {
            let title = NSAttributedString(string: CalloutHead.title(head.kind),
                                           attributes: [.font: NSFont.systemFont(ofSize: l.font.pointSize, weight: .semibold), .foregroundColor: tint])
            let font = title.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
            title.draw(at: NSPoint(x: x + MarkdownStyler.calloutIcon, y: baseline - font.ascender))
        }
        guard let folded = head.folded else { return }
        let chevron = NSImage(systemSymbolName: folded ? "chevron.right" : "chevron.down", accessibilityDescription: folded ? "展开" : "收起")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        let c = CGRect(x: right - 26, y: capMid - 10, width: 20, height: 20)
        if let chevron {
            let s = chevron.size
            chevron.tinted(tint).draw(in: CGRect(x: c.midX - s.width / 2, y: c.midY - s.height / 2, width: s.width, height: s.height),
                                      from: .zero, operation: .sourceOver, fraction: 0.9, respectFlipped: true, hints: nil)
        }
        foldHitRects.append((c.insetBy(dx: -6, dy: -6), head.key))
    }

    private func draw(_ e: EmbedDeco, range: NSRange, origin: NSPoint) {
        let fs = frags(range)
        guard let first = fs.first, let last = fs.last else { return }
        let x = origin.x + MarkdownStyler.gutter
        let y = e.revealed ? origin.y + last.used.maxY + 8 : origin.y + first.rect.minY
        let available = (textContainers.first?.size.width ?? 600) - 2 * MarkdownStyler.gutter
        let frame = e.embed.drawRect(in: CGRect(x: x, y: y, width: available, height: e.height))
        embedHitRects.append((frame, e.embed))
        let clip = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        if let img = e.embed.image {
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            img.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            if e.embed.kind == .video {
                let d: CGFloat = 52
                let c = CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
                NSColor.black.withAlphaComponent(0.45).setFill()
                NSBezierPath(ovalIn: c).fill()
                let tri = NSBezierPath()
                tri.move(to: NSPoint(x: c.minX + 20, y: c.minY + 15))
                tri.line(to: NSPoint(x: c.minX + 20, y: c.maxY - 15))
                tri.line(to: NSPoint(x: c.maxX - 14, y: c.midY))
                tri.close()
                NSColor.white.setFill()
                tri.fill()
            }
        } else {
            Theme.NS.codeBlock.setFill()
            clip.fill()
            let label = e.embed.failed ? "找不到附件：\(e.embed.target)" : "正在载入 \(e.embed.target)…"
            let s = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.NS.mark])
            s.draw(at: NSPoint(x: frame.minX + 12, y: frame.midY - s.size().height / 2))
        }
    }
}

extension NSFont {
    var monospacedDigits: NSFont {
        let d = fontDescriptor.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                                                      NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
