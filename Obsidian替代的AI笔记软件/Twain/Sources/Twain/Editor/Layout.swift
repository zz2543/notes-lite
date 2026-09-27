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
        var hiddenEnd = -1
        for i in 0..<range.length {
            let ci = characterIndexes[i]
            guard ci < storage.length else { continue }
            if ci >= hiddenEnd {
                var eff = NSRange()
                if storage.attribute(.twainHidden, at: ci, effectiveRange: &eff) == nil {
                    hiddenEnd = -1
                    continue
                }
                hiddenEnd = NSMaxRange(eff)
            }
            if newProps == nil { newProps = Array(UnsafeBufferPointer(start: props, count: range.length)) }
            newProps![i] = .null
        }
        guard let newProps else { return 0 }
        lm.setGlyphs(glyphs, properties: newProps, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return range.length
    }

    /// Checkbox rects in text-view coordinates with the start of their line, rebuilt on every draw.
    var taskHitRects: [(CGRect, Int)] = []
    /// Pictures and videos drawn in place, for clicks.
    var embedHitRects: [(CGRect, Embed)] = []

    /// Inline code and highlights: a rounded box around the glyphs instead of the whole line height.
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        guard let storage = textStorage, charRange.location < storage.length,
              let font = storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? NSFont,
              (storage.attribute(.paragraphStyle, at: charRange.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0 > 0 else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        let gi = glyphIndexForCharacter(at: charRange.location)
        let baseline = location(forGlyphAt: gi).y
        let text = (font.ascender - font.descender)
        color.setFill()
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
        storage.enumerateAttribute(.twainDeco, in: paras) { value, range, _ in
            guard let deco = value as? Deco else { return }
            draw(deco, range: range, storage: storage, origin: origin, width: width)
        }
        storage.enumerateAttribute(.twainEmbed, in: paras) { value, range, _ in
            guard let e = value as? EmbedDeco else { return }
            draw(e, range: range, origin: origin)
        }
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
        case let .quote(depth, tint):
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
