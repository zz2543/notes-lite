import AppKit
import TwainCore

extension NSAttributedString.Key {
    /// Syntax the layout manager turns into null glyphs.
    static let twainHidden = NSAttributedString.Key("twainHidden")
    /// A `Deco` drawn behind or beside the line.
    static let twainDeco = NSAttributedString.Key("twainDeco")
    static let twainWikiLink = NSAttributedString.Key("twainWikiLink")
    static let twainURL = NSAttributedString.Key("twainURL")
    /// An `EmbedDeco`: an image or video shown on the line.
    static let twainEmbed = NSAttributedString.Key("twainEmbed")
    static let twainTag = NSAttributedString.Key("twainTag")
}

/// Decoration the layout manager draws for a rendered line.
final class Deco: NSObject {
    enum Kind {
        case bullet(level: Int)
        case number(String)
        case task(done: Bool)
        /// Bars for each quote level; `tint` colors callouts.
        case quote(depth: Int, tint: NSColor?)
        case hr
        /// A code block line; `top`/`bottom` round the block's ends.
        case code(top: Bool, bottom: Bool)
    }
    let kind: Kind
    /// Where the line's content starts, in container coordinates.
    let contentX: CGFloat
    init(_ kind: Kind, contentX: CGFloat) { self.kind = kind; self.contentX = contentX }
}

/// An embed on its own line. `inline` is false when the source is hidden and the picture is the line.
final class EmbedDeco: NSObject {
    let embed: Embed
    let revealed: Bool
    let height: CGFloat
    init(_ embed: Embed, revealed: Bool, height: CGFloat) { self.embed = embed; self.revealed = revealed; self.height = height }
}

struct EditorStyle: Equatable {
    var font: EditorFont
    var typewriter: Bool
    var dim: Bool
    var zen: Bool
    var width: CGFloat
}

/// Styles the note line by line and, after an edit, restyles only the lines whose text or
/// rendering state changed. A line's rendering depends on its own text, the block it sits in
/// (code, front matter), whether it holds the caret, and the dimming of other paragraphs.
final class MarkdownStyler {
    /// Room left of the text column for syntax that hangs out of it (`## `, `- [ ] `).
    static let gutter: CGFloat = 40
    static let listUnit: CGFloat = 28
    static let quoteUnit: CGFloat = 18

    private(set) var typo: Typography
    private(set) var style: EditorStyle
    /// Resolves `![[name]]` / `![](path)` to a file.
    var resolveEmbed: (String) -> URL? = { _ in nil }
    /// Called when an embed finished loading and its line needs a new height.
    var needsRestyle: () -> Void = {}

    private struct Sig: Equatable {
        var forced: BlockType?
        var codeTop = false
        var codeBottom = false
        var active = false
        var reveal = false
        var dim = false
        var first = false
        var embedStamp = 0
    }

    private(set) var lineStarts: [Int] = [0]
    private var sigs: [Sig] = []
    /// Characters edited since the last restyle, in current coordinates; nil when none.
    private var dirtyChars: NSRange?
    private var everything = true
    /// Lines showing an embed, by target, and a stamp bumped when one of them finishes loading.
    private var embedStamps: [String: Int] = [:]
    private var markWidths: [String: CGFloat] = [:]
    private(set) var containerWidth: CGFloat = 600

    init(style: EditorStyle) {
        self.style = style
        typo = Typography(style.font)
    }

    func setStyle(_ s: EditorStyle) {
        guard s != style else { return }
        if s.font != style.font { typo = Typography(s.font); markWidths = [:] }
        style = s
        everything = true
    }

    func setContainerWidth(_ w: CGFloat) {
        guard abs(w - containerWidth) > 0.5 else { return }
        containerWidth = w
        // Embeds scale with the column.
        for k in embedStamps.keys { embedStamps[k, default: 0] += 1 }
    }

    /// Everything changed (new note, new style).
    func reset() { everything = true; dirtyChars = nil }

    /// Records a text edit reported by the text storage (new coordinates).
    func noteEdit(_ range: NSRange, delta: Int) {
        guard var d = dirtyChars else { dirtyChars = range; return }
        if NSMaxRange(d) >= range.location - max(0, -delta) { d.length = max(0, d.length + delta) }
        dirtyChars = NSUnionRange(d, range)
    }

    // MARK: lines

    func lineIndex(at loc: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= loc { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Whether line `i` sits inside a fenced code or math block, as of the last restyle.
    func isCode(line i: Int) -> Bool { i < sigs.count && sigs[i].forced == .code }

    /// Range of line `i` without its newline.
    func lineRange(_ i: Int, length: Int) -> NSRange {
        let start = lineStarts[i]
        let end = i + 1 < lineStarts.count ? lineStarts[i + 1] - 1 : length
        return NSRange(location: start, length: max(0, end - start))
    }

    private func scanLines(_ ns: NSString) {
        var starts = [0]
        starts.reserveCapacity(lineStarts.count + 8)
        let len = ns.length
        var buf = [unichar](repeating: 0, count: 8192)
        var pos = 0
        buf.withUnsafeMutableBufferPointer { b in
            let p = b.baseAddress!
            while pos < len {
                let n = min(8192, len - pos)
                ns.getCharacters(p, range: NSRange(location: pos, length: n))
                var k = 0
                while k < n {
                    if p[k] == 0x0A { starts.append(pos + k + 1) }
                    k += 1
                }
                pos += n
            }
        }
        lineStarts = starts
    }

    // MARK: restyle

    /// Brings the storage's attributes up to date. `caret` is nil when the editor isn't focused.
    /// Returns the ranges it restyled, for the layout manager to redo.
    @discardableResult
    func restyle(_ storage: NSTextStorage, caret: Int?) -> [NSRange] {
        let ns = storage.string as NSString
        let len = ns.length
        let oldCount = sigs.count
        scanLines(ns)
        let n = lineStarts.count
        let lineDelta = n - oldCount
        var textA = n, textB = -1
        if let d = dirtyChars {
            textA = lineIndex(at: min(d.location, len))
            textB = lineIndex(at: min(NSMaxRange(d), len))
        }
        let all = everything || oldCount == 0
        everything = false
        dirtyChars = nil

        let activeLine = caret.map { lineIndex(at: min($0, len)) }
        var newSigs = [Sig](repeating: Sig(), count: n)
        var dirty: [Int] = []
        var ctx = BlockContext.none
        for i in 0..<n {
            let r = lineRange(i, length: len)
            var sig = Sig()
            sig.first = i == 0
            // Only lines that can open or close a block need their text for the context.
            if needsText(ns, r, ctx) {
                let (forced, next) = Markdown.role(of: ns.substring(with: r), index: i, context: ctx)
                sig.forced = forced
                if forced == .fence { sig.codeTop = next != .none; sig.codeBottom = next == .none }
                ctx = next
            } else if ctx != .none {
                sig.forced = ctx == .frontmatter ? .frontmatter : .code
            }
            if i == activeLine {
                sig.active = true
                sig.reveal = reveals(ns, r, caret: caret! - r.location, forced: sig.forced)
            }
            sig.dim = style.dim && activeLine != nil && i != activeLine
            if let target = embedTarget(ns, r, forced: sig.forced) { sig.embedStamp = embedStamps[target, default: 0] }
            newSigs[i] = sig
            if all || (i >= textA && i <= textB) {
                dirty.append(i)
            } else {
                let old = i < textA ? i : i - lineDelta
                if old < 0 || old >= oldCount || sigs[old] != sig { dirty.append(i) }
            }
        }
        sigs = newSigs
        guard !dirty.isEmpty else { return [] }

        var ranges: [NSRange] = []
        storage.beginEditing()
        for i in dirty {
            let r = lineRange(i, length: len)
            let full = NSRange(location: r.location, length: r.length + (i + 1 < n ? 1 : 0))
            styleLine(storage, ns, i, r, full, newSigs[i])
            if let last = ranges.last, NSMaxRange(last) == full.location {
                ranges[ranges.count - 1].length += full.length
            } else {
                ranges.append(full)
            }
        }
        storage.endEditing()
        return ranges
    }

    private func firstChar(_ ns: NSString, _ r: NSRange) -> unichar? {
        var i = r.location
        let end = min(NSMaxRange(r), r.location + 4)
        while i < end {
            let c = ns.character(at: i)
            if c != 0x20 { return c }
            i += 1
        }
        return nil
    }

    private func needsText(_ ns: NSString, _ r: NSRange, _ ctx: BlockContext) -> Bool {
        guard let c = firstChar(ns, r) else { return false }
        switch ctx {
        case .none: return c == 0x60 || c == 0x7E || c == 0x24 || (c == 0x2D && r.location == 0)   // ` ~ $ -
        case let .code(fence): return c == fence.utf16.first
        case .math: return c == 0x24
        case .frontmatter: return c == 0x2D || c == 0x2E
        }
    }

    private func reveals(_ ns: NSString, _ r: NSRange, caret: Int, forced: BlockType?) -> Bool {
        guard forced == nil, r.length > 0 else { return true }
        let text = ns.substring(with: r)
        let type = Markdown.blockType(text)
        if type.isList { return caret <= Markdown.prefixLength(text) }
        return true
    }

    private func embedTarget(_ ns: NSString, _ r: NSRange, forced: BlockType?) -> String? {
        guard forced == nil, r.length > 4, let c = firstChar(ns, r), c == 0x21 else { return nil }   // !
        return Markdown.parseLine(ns.substring(with: r)).blockEmbed.flatMap { Embed.kind(of: $0) == .other ? nil : $0 }
    }

    // MARK: one line

    private func paragraph(_ type: BlockType, font: NSFont, first: Bool) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        let lh: CGFloat = type.isHeading ? 1.35 : type == .code || type == .fence || type == .frontmatter ? 1.5 : 1.8
        let natural = font.ascender - font.descender + font.leading
        p.lineSpacing = max(0, font.pointSize * lh - natural)
        switch type {
        case .h1: p.paragraphSpacingBefore = first ? 0 : 30; p.paragraphSpacing = 16
        case .h2: p.paragraphSpacingBefore = first ? 0 : 28; p.paragraphSpacing = 10
        case .h3: p.paragraphSpacingBefore = first ? 0 : 22; p.paragraphSpacing = 6
        case .h4, .h5, .h6: p.paragraphSpacingBefore = first ? 0 : 16; p.paragraphSpacing = 4
        case .li, .task, .ol: p.paragraphSpacing = 2
        case .code, .fence, .frontmatter, .table: p.paragraphSpacing = 0
        default: p.paragraphSpacing = 12
        }
        p.firstLineHeadIndent = Self.gutter
        p.headIndent = Self.gutter
        p.tailIndent = -Self.gutter
        return p
    }

    private func markWidth(_ s: String, _ font: NSFont) -> CGFloat {
        let k = s + "|" + font.fontName + "|\(font.pointSize)"
        if let w = markWidths[k] { return w }
        let w = ceil(NSAttributedString(string: s, attributes: [.font: font]).size().width)
        markWidths[k] = w
        return w
    }

    private func styleLine(_ storage: NSTextStorage, _ ns: NSString, _ i: Int, _ r: NSRange, _ full: NSRange, _ sig: Sig) {
        let text = ns.substring(with: r)
        let type = sig.forced ?? Markdown.blockType(text)
        let ink = Theme.NS.ink, mark = Theme.NS.mark
        let body = typo.body
        let bodySize = typo.bodySize
        let alpha: CGFloat = sig.dim ? 0.26 : 1
        func dimmed(_ c: NSColor) -> NSColor { alpha < 1 ? c.withAlphaComponent(c.alphaComponent * alpha) : c }

        guard full.length > 0 else { return }
        // Literal blocks: code, fences, front matter.
        if type.isLiteral {
            let size: CGFloat = type == .code ? (bodySize * 0.84).rounded() : 13
            let font = typo.mono(size: size)
            let p = paragraph(type, font: font, first: sig.first)
            let inset: CGFloat = type == .frontmatter ? 0 : 14
            p.firstLineHeadIndent += inset
            p.headIndent += inset
            p.tailIndent -= inset
            if sig.codeTop { p.paragraphSpacingBefore = sig.first ? 0 : 8 }
            if sig.codeBottom { p.paragraphSpacing = 12 }
            let color = type == .code ? ink : mark
            storage.setAttributes([.font: font, .foregroundColor: dimmed(type == .frontmatter ? Theme.NS.quote : color), .paragraphStyle: p], range: full)
            if type != .frontmatter {
                storage.addAttribute(.twainDeco, value: Deco(.code(top: sig.codeTop, bottom: sig.codeBottom), contentX: p.headIndent), range: full)
            }
            typo.applyCJK(storage, in: r)
            return
        }

        let m = Markdown.parseLine(text, type: type)
        let level = type.headingLevel
        let size: CGFloat = switch level {
        case 1: 30
        case 2: 22
        case 3: 18
        case 4: bodySize
        case 5: bodySize - 1
        case 6: bodySize - 2
        default: type == .table ? bodySize - 1 : bodySize
        }
        let weight: NSFont.Weight = level == 1 ? .bold : level != nil ? .semibold : .regular
        let font = typo.font(size: size, weight: weight)
        let p = paragraph(type, font: font, first: sig.first)
        var color = type == .quote ? Theme.NS.quote : level == 6 ? Theme.NS.quote : ink

        // Where the content starts, and how the prefix hangs to its left.
        let ws = text.prefix { $0 == " " || $0 == "\t" }.utf16.count
        let markerRange = NSRange(location: r.location + (type.isList ? ws : 0),
                                  length: m.prefix.length - (type.isList ? ws : 0))
        let markFont = level != nil ? typo.mono(size: min(15, (size * 0.62).rounded())) : body
        var contentX = Self.gutter
        var deco: Deco.Kind?
        switch type {
        case .li, .task, .ol:
            contentX += Self.listUnit * CGFloat(m.depth + 1)
            switch type {
            case .li: deco = .bullet(level: m.depth)
            case .ol: deco = .number(Markdown.orderedNumber(text).map { "\($0)." } ?? "1.")
            default: deco = .task(done: Markdown.isTaskDone(text))
            }
        case .quote:
            contentX += Self.quoteUnit * CGFloat(m.depth + 1)
            deco = .quote(depth: m.depth, tint: m.callout.map(Self.calloutColor))
            if m.callout != nil { color = ink }
        case .hr where !sig.active:
            deco = .hr
        default: break
        }
        let revealPrefix = sig.reveal && markerRange.length > 0
        let hang = revealPrefix ? markWidth(ns.substring(with: markerRange), markFont) : 0
        p.headIndent = contentX
        p.firstLineHeadIndent = max(0, contentX - hang)
        if revealPrefix, type.isList || type == .quote { deco = nil }

        // A line that is just an image: the picture is the line.
        if let target = m.blockEmbed, Embed.kind(of: target) != .other {
            let url = resolveEmbed(target)
            let embed = EmbedCache.shared.embed(target: target, url: url) { [weak self] in
                guard let self else { return }
                self.embedStamps[target, default: 0] += 1
                self.needsRestyle()
            }
            let h = embed.height(fitting: containerWidth - 2 * Self.gutter)
            if sig.active {
                p.paragraphSpacing = h + 16
                storage.setAttributes([.font: typo.font(size: 13), .foregroundColor: mark, .paragraphStyle: p], range: full)
            } else {
                p.lineSpacing = 0
                p.minimumLineHeight = h
                p.maximumLineHeight = h
                p.paragraphSpacing = 12
                storage.setAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: p], range: full)
            }
            storage.addAttribute(.twainEmbed, value: EmbedDeco(embed, revealed: sig.active, height: h), range: full)
            if let url { storage.addAttribute(.twainURL, value: url.absoluteString, range: r) }
            return
        }

        storage.setAttributes([.font: font, .foregroundColor: dimmed(color), .paragraphStyle: p], range: full)
        if level == 1 { storage.addAttribute(.kern, value: -0.012 * size, range: r) }
        if let deco { storage.addAttribute(.twainDeco, value: Deco(deco, contentX: contentX), range: full) }
        guard r.length > 0 else { return }
        let abs = { (x: NSRange) in NSRange(location: r.location + x.location, length: x.length) }

        if type == .hr {
            if sig.active { storage.addAttribute(.foregroundColor, value: dimmed(mark), range: r) }
            else { storage.addAttribute(.twainHidden, value: true, range: r) }
            return
        }
        if type == .table {
            for (k, c) in text.utf16.enumerated() where c == 0x7C {   // |
                storage.addAttribute(.foregroundColor, value: dimmed(mark), range: NSRange(location: r.location + k, length: 1))
            }
        }
        if type == .task, Markdown.isTaskDone(text) {
            let bodyR = NSRange(location: r.location + m.prefix.length, length: r.length - m.prefix.length)
            storage.addAttributes([.foregroundColor: dimmed(Theme.NS.doneText), .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .strikethroughColor: Theme.NS.strike], range: bodyR)
        }
        let accent = Theme.NS.accent
        for span in m.spans {
            let x = abs(span.content)
            switch span.kind {
            case .bold:
                storage.addAttribute(.font, value: typo.font(size: size, weight: level != nil ? .heavy : .semibold), range: x)
            case .italic:
                storage.addAttribute(.font, value: typo.font(size: size, weight: weight, italic: true), range: x)
            case .code:
                storage.addAttributes([.font: typo.mono(size: (size * 0.86).rounded()), .backgroundColor: Theme.NS.codeBg], range: x)
            case .strike:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: dimmed(Theme.NS.doneText)], range: x)
            case .highlight:
                storage.addAttribute(.backgroundColor, value: Theme.NS.highlight.withAlphaComponent(0.4 * alpha), range: x)
            case let .wikilink(title):
                storage.addAttributes([.foregroundColor: dimmed(accent), .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .underlineColor: accent.withAlphaComponent(0.3 * alpha), .twainWikiLink: title], range: x)
            case let .link(url):
                storage.addAttributes([.foregroundColor: dimmed(accent), .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .underlineColor: accent.withAlphaComponent(0.3 * alpha), .twainURL: url], range: x)
            case let .embed(target), let .image(target):
                storage.addAttributes([.foregroundColor: dimmed(accent)], range: x)
                if let u = resolveEmbed(target) { storage.addAttribute(.twainURL, value: u.absoluteString, range: x) }
                else if case .embed = span.kind { storage.addAttribute(.twainWikiLink, value: target, range: x) }
            case let .tag(name):
                storage.addAttributes([.foregroundColor: dimmed(Theme.NS.tag), .twainTag: name], range: x)
            }
        }
        // Syntax: shown dimmed where the caret is, hidden elsewhere. List markers hang in the margin.
        let indentRange = NSRange(location: r.location, length: type.isList ? ws : 0)
        if indentRange.length > 0 { storage.addAttribute(.twainHidden, value: true, range: indentRange) }
        if markerRange.length > 0 {
            if revealPrefix { storage.addAttributes([.foregroundColor: dimmed(mark), .font: markFont], range: markerRange) }
            else { storage.addAttribute(.twainHidden, value: true, range: markerRange) }
        }
        for mk in m.spans.flatMap(\.marks) {
            let x = abs(mk)
            if sig.active {
                storage.addAttribute(.foregroundColor, value: mark, range: x)
                storage.removeAttribute(.backgroundColor, range: x)
            } else {
                storage.addAttribute(.twainHidden, value: true, range: x)
            }
        }
        typo.applyCJK(storage, in: r)
    }

    static func calloutColor(_ kind: String) -> NSColor {
        switch kind {
        case "warning", "caution", "attention": .systemOrange
        case "danger", "error", "bug", "failure": .systemRed
        case "tip", "hint", "important", "success", "check", "done": .systemGreen
        case "question", "help", "faq": .systemPurple
        case "quote", "cite": .secondaryLabelColor
        default: .systemBlue
        }
    }
}
