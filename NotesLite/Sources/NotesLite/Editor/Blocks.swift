import AppKit
import NotesCore

extension NSAttributedString.Key {
    /// A `BlockDeco`: a table, formula, diagram or embedded note drawn for a block of lines.
    static let notesliteBlock = NSAttributedString.Key("notesliteBlock")
    /// An `InlinePicture` on the one character that stands in for `$…$` on its line.
    static let notesliteInline = NSAttributedString.Key("notesliteInline")
    /// A footnote reference's label.
    static let notesliteFootnote = NSAttributedString.Key("notesliteFootnote")
}

/// What the layout manager draws for a block whose source is hidden (or, when `revealed`,
/// below its source while the caret is inside).
final class BlockDeco: NSObject {
    enum Content {
        case table(TableLayout)
        case picture(Rendered?, kind: RenderKind)
        case note(NoteEmbed)
    }
    let content: Content
    /// Height of the drawing, without the spacing around it.
    let height: CGFloat
    let revealed: Bool
    let alpha: CGFloat

    init(_ content: Content, height: CGFloat, revealed: Bool, alpha: CGFloat) {
        self.content = content
        self.height = height
        self.revealed = revealed
        self.alpha = alpha
    }

    static func pictureHeight(_ r: Rendered?, kind: RenderKind, width: CGFloat) -> CGFloat {
        guard let r else {
            return switch kind {
            case .diagram: 160
            default: 40
            }
        }
        if r.image == nil { return r.error == nil ? 24 : 40 }
        let scale = min(1, width / max(1, r.size.width))
        return (r.size.height * scale).rounded(.up)
    }

    /// Draws the block into `frame` (the column, at the block's top), returning the rect it used.
    @discardableResult
    func draw(in frame: CGRect) -> CGRect {
        let ctx = NSGraphicsContext.current?.cgContext
        if alpha < 1 { ctx?.setAlpha(alpha); ctx?.beginTransparencyLayer(auxiliaryInfo: nil) }
        defer { if alpha < 1 { ctx?.endTransparencyLayer(); ctx?.setAlpha(1) } }
        switch content {
        case let .table(t):
            let r = rect(in: frame)
            t.draw(in: r)
            return r
        case let .note(n):
            let r = rect(in: frame)
            n.draw(in: r)
            return r
        case let .picture(r, kind):
            return Self.drawPicture(r, kind: kind, in: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height))
        }
    }

    /// The rect `draw(in:)` uses for this block, without drawing it.
    func rect(in frame: CGRect) -> CGRect {
        let column = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
        switch content {
        case let .table(t): return CGRect(x: frame.minX, y: frame.minY, width: t.width, height: t.height)
        case .note: return column
        case let .picture(r, kind): return Self.pictureRect(r, kind: kind, in: column)
        }
    }

    private static func pictureRect(_ r: Rendered?, kind: RenderKind, in frame: CGRect) -> CGRect {
        guard let r, r.image != nil else { return frame }
        let scale = min(1, frame.width / max(1, r.size.width))
        let size = CGSize(width: r.size.width * scale, height: r.size.height * scale)
        // Formulas and diagrams sit in the middle of the column, as they do when published.
        let x = kind == .block || kind == .diagram ? frame.minX + (frame.width - size.width) / 2 : frame.minX
        return CGRect(x: x.rounded(), y: frame.minY, width: size.width, height: size.height)
    }

    private static func drawPicture(_ r: Rendered?, kind: RenderKind, in frame: CGRect) -> CGRect {
        guard let r, let img = r.image else {
            let text = r?.error ?? "正在渲染…"
            let color: NSColor = r?.error != nil ? .systemRed : Theme.NS.mark
            let s = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: color])
            let box = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
            Theme.NS.codeBlock.setFill()
            NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
            s.draw(with: box.insetBy(dx: 12, dy: 6), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return box
        }
        let rect = pictureRect(r, kind: kind, in: frame)
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        return rect
    }
}

/// Inline math shown as a picture. The character carrying it becomes a control glyph as wide as
/// the picture, so the line still wraps and hit-tests like text.
final class InlinePicture: NSObject {
    let rendered: Rendered
    init(_ r: Rendered) { rendered = r }
}

// MARK: - Inline Markdown as attributed text

/// Renders one line's worth of Markdown (a table cell, a callout title) to attributed text with
/// the syntax removed, for drawing outside the editor's own text.
enum InlineMarkdown {
    static func attributed(_ text: String, font: NSFont, typo: Typography, color: NSColor, bold: Bool = false,
                           picture: (String, CGFloat) -> Rendered?) -> (NSAttributedString, waiting: Bool) {
        let base = bold ? typo.font(size: font.pointSize, weight: .semibold) : font
        let out = NSMutableAttributedString(string: text, attributes: [.font: base, .foregroundColor: color])
        guard !text.isEmpty else { return (out, false) }
        let m = Markdown.parseLine(text, type: .p)
        var waiting = false
        var marks: [NSRange] = []
        var attachments: [(NSRange, NSTextAttachment)] = []
        let size = font.pointSize
        for span in m.spans {
            let x = span.content
            switch span.kind {
            case .bold: out.addAttribute(.font, value: typo.font(size: size, weight: .bold), range: x)
            case .italic: out.addAttribute(.font, value: typo.font(size: size, weight: bold ? .semibold : .regular, italic: true), range: x)
            case .code: out.addAttributes([.font: typo.mono(size: (size * 0.88).rounded()), .backgroundColor: Theme.NS.codeBg], range: x)
            case .strike: out.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Theme.NS.doneText], range: x)
            case .highlight: out.addAttribute(.backgroundColor, value: Theme.NS.highlight.withAlphaComponent(0.4), range: x)
            case let .wikilink(t):
                // `[[target|alias]]` shows the alias.
                if let bar = (t as NSString).range(of: "|").nilIfNotFound {
                    marks.append(NSRange(location: x.location, length: bar.location + 1))
                }
                out.addAttribute(.foregroundColor, value: Theme.NS.accent, range: x)
            case .link, .embed, .image: out.addAttribute(.foregroundColor, value: Theme.NS.accent, range: x)
            case .tag: out.addAttribute(.foregroundColor, value: Theme.NS.tag, range: x)
            case .footnote: out.addAttributes([.foregroundColor: Theme.NS.accent, .font: typo.font(size: (size * 0.72).rounded()),
                                               .baselineOffset: size * 0.36], range: x)
            case let .math(src):
                let r = picture(src, size)
                if let r, let img = r.image {
                    let a = NSTextAttachment()
                    a.image = img
                    a.bounds = CGRect(x: 0, y: -(r.size.height - r.baseline), width: r.size.width, height: r.size.height)
                    attachments.append((NSRange(location: span.marks[0].location, length: NSMaxRange(span.marks[1]) - span.marks[0].location), a))
                } else {
                    if r == nil { waiting = true }
                    out.addAttributes([.font: typo.mono(size: (size * 0.88).rounded()), .foregroundColor: Theme.NS.quote], range: x)
                }
            }
            marks += span.marks
        }
        typo.applyCJK(out, in: NSRange(location: 0, length: out.length))
        // Attachments replace their whole `$…$`; then the remaining syntax goes, last first.
        var cuts: [(NSRange, NSAttributedString?)] = marks.map { ($0, nil) }
        for (r, a) in attachments {
            cuts.removeAll { NSIntersectionRange($0.0, r).length > 0 }
            cuts.append((r, NSAttributedString(attachment: a)))
        }
        for (r, rep) in cuts.sorted(by: { $0.0.location > $1.0.location }) where NSMaxRange(r) <= out.length {
            if let rep { out.replaceCharacters(in: r, with: rep) } else { out.deleteCharacters(in: r) }
        }
        return (out, waiting)
    }
}

extension NSRange {
    var nilIfNotFound: NSRange? { location == NSNotFound ? nil : self }
}

// MARK: - Tables

/// A pipe table measured for a column width: cell text, column widths and row heights.
final class TableLayout {
    static let padX: CGFloat = 10
    static let padY: CGFloat = 6

    let table: MarkdownTable
    let cells: [[NSAttributedString]]
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
    let width: CGFloat
    let height: CGFloat
    /// Source position of each shown row relative to the table's first character (the
    /// separator line has none), so a click can put the caret in the right cell.
    let rowOffsets: [Int]
    let waiting: Bool

    init(_ t: MarkdownTable, rowOffsets: [Int], available: CGFloat, typo: Typography, fontSize: CGFloat,
         picture: (String, CGFloat) -> Rendered?) {
        table = t
        self.rowOffsets = rowOffsets
        let font = typo.font(size: fontSize)
        var waiting = false
        func render(_ c: MarkdownTable.Cell, header: Bool, col: Int) -> NSAttributedString {
            let (s, w) = InlineMarkdown.attributed(c.text, font: font, typo: typo, color: Theme.NS.ink, bold: header, picture: picture)
            if w { waiting = true }
            let m = NSMutableAttributedString(attributedString: s)
            let p = NSMutableParagraphStyle()
            p.alignment = switch t.aligns[col] {
            case .left: .left
            case .center: .center
            case .right: .right
            }
            p.lineBreakMode = .byWordWrapping
            // A fixed line height: CJK faces (bold Songti especially) are taller than Latin ones.
            p.minimumLineHeight = (fontSize * 1.5).rounded()
            p.maximumLineHeight = (fontSize * 1.5).rounded()
            m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
            return m
        }
        let rows = [t.header] + t.rows
        cells = rows.enumerated().map { r, row in row.enumerated().map { render($1, header: r == 0, col: $0) } }
        self.waiting = waiting

        // Natural widths, then shrink wide columns first until the table fits.
        let cols = t.columns
        let chrome = 2 * Self.padX
        var natural = [CGFloat](repeating: 44, count: cols)
        var minimum = [CGFloat](repeating: 44, count: cols)
        for row in cells {
            for (c, s) in row.enumerated() where c < cols {
                let w = ceil(s.boundingRect(with: NSSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin]).width) + chrome
                natural[c] = max(natural[c], w)
                // The longest unbreakable run keeps a column from getting absurdly thin.
                let longest = s.string.split(whereSeparator: { $0 == " " }).map { min(120, CGFloat($0.count) * fontSize * 0.55) }.max() ?? 0
                minimum[c] = max(minimum[c], min(natural[c], max(44, longest + chrome)))
            }
        }
        // Too wide: cap the widest columns at one level, so short ones keep their natural width.
        var widths = natural
        if natural.reduce(0, +) > available {
            var lo: CGFloat = 0, hi = natural.max() ?? available
            for _ in 0..<30 {
                let cap = (lo + hi) / 2
                let sum = natural.indices.reduce(CGFloat(0)) { $0 + max(minimum[$1], min(natural[$1], cap)) }
                if sum > available { hi = cap } else { lo = cap }
            }
            widths = natural.indices.map { max(minimum[$0], min(natural[$0], lo)) }
        }
        columnWidths = widths.map { $0.rounded(.up) }
        rowHeights = cells.map { row in
            row.enumerated().map { c, s in
                ceil(s.boundingRect(with: NSSize(width: max(10, (c < cols ? widths[c] : 44) - chrome), height: 10_000),
                                    options: [.usesLineFragmentOrigin]).height) + 2 * Self.padY
            }.max() ?? (fontSize + 2 * Self.padY)
        }
        width = columnWidths.reduce(0, +)
        height = rowHeights.reduce(0, +)
    }

    func draw(in rect: CGRect) {
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        var y = rect.minY
        for (r, h) in rowHeights.enumerated() {
            let fill: NSColor? = r == 0 ? Theme.NS.tableHeader : r % 2 == 0 ? Theme.NS.tableStripe : nil
            if let fill { fill.setFill(); CGRect(x: rect.minX, y: y, width: rect.width, height: h).fill() }
            var x = rect.minX
            for (c, w) in columnWidths.enumerated() {
                if c < cells[r].count {
                    let box = CGRect(x: x + Self.padX, y: y + Self.padY, width: w - 2 * Self.padX, height: h - 2 * Self.padY)
                    cells[r][c].draw(with: box, options: [.usesLineFragmentOrigin])
                }
                x += w
            }
            y += h
        }
        // Grid: row rules, column rules, the outline.
        Theme.NS.tableLine.setFill()
        y = rect.minY
        for h in rowHeights.dropLast() {
            y += h
            CGRect(x: rect.minX, y: y - 0.5, width: rect.width, height: 1).fill()
        }
        var x = rect.minX
        for w in columnWidths.dropLast() {
            x += w
            CGRect(x: x - 0.5, y: rect.minY, width: 1, height: rect.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        Theme.NS.tableLine.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    /// Source offset (from the table's start) of the cell under `p`, a point relative to the table.
    func sourceOffset(at p: CGPoint) -> Int? {
        var y: CGFloat = 0
        guard let row = rowHeights.indices.first(where: { r in defer { y += rowHeights[r] }; return p.y < y + rowHeights[r] }) else { return nil }
        var x: CGFloat = 0
        let col = columnWidths.indices.first { c in defer { x += columnWidths[c] }; return p.x < x + columnWidths[c] } ?? (columnWidths.count - 1)
        let cellsOfRow = row == 0 ? table.header : table.rows[row - 1]
        guard row < rowOffsets.count else { return nil }
        let cell = col < cellsOfRow.count ? cellsOfRow[col] : nil
        let inLine = cell.flatMap { $0.range.location == NSNotFound ? nil : NSMaxRange($0.range) } ?? 0
        return rowOffsets[row] + inLine
    }
}

// MARK: - Callouts

/// A callout's first line: its icon, default title and fold control.
struct CalloutHead {
    let kind: String
    /// The line has no title of its own; the kind's name is drawn instead.
    let untitled: Bool
    /// nil when the callout can't fold.
    let folded: Bool?
    let key: String

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "abstract", "summary", "tldr": "list.bullet.clipboard"
        case "info": "info.circle"
        case "todo": "checkmark.circle"
        case "tip", "hint", "important": "flame"
        case "success", "check", "done": "checkmark"
        case "question", "help", "faq": "questionmark.circle"
        case "warning", "caution", "attention": "exclamationmark.triangle"
        case "failure", "fail", "missing": "xmark"
        case "danger", "error": "bolt"
        case "bug": "ladybug"
        case "example": "list.number"
        case "quote", "cite": "quote.opening"
        default: "pencil"
        }
    }

    static func title(_ kind: String) -> String {
        kind.prefix(1).uppercased() + kind.dropFirst()
    }
}
