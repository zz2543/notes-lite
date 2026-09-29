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
        /// Bars for each quote level; `tint` colors callouts, `head` marks a callout's first line.
        case quote(depth: Int, tint: NSColor?, head: CalloutHead?)
        case hr
        /// A code block line; `top`/`bottom` round the block's ends.
        case code(top: Bool, bottom: Bool)
        /// A footnote definition's label, hung in the margin.
        case footnote(String)
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
    /// Source code (an HTML note): monospaced, no Markdown rendering.
    var plain = false
    /// Width kept free on the right for annotation cards.
    var rail: CGFloat = 0
}

/// Styles the note line by line and, after an edit, restyles only the lines whose text or
/// rendering state changed. A line's rendering depends on its own text, the block it sits in
/// (code, front matter, a table, a formula, a callout), whether it holds the caret, and the
/// dimming of other paragraphs.
///
/// Blocks that render as a picture — tables, `$$` math, Mermaid and plugin code blocks — are
/// drawn on their first line while the caret is elsewhere; their other lines collapse to
/// nothing. With the caret inside, the source comes back (formulas keep a preview below).
///
/// Big restyles (opening a long note, changing the font) are done in slices of `budget`
/// lines, nearest to what is on screen first; `pending` says more slices are due.
final class MarkdownStyler {
    /// Room left of the text column for syntax that hangs out of it (`## `, `- [ ] `).
    static let gutter: CGFloat = 40
    static let listUnit: CGFloat = 28
    static let quoteUnit: CGFloat = 18
    static let budget = 260
    static let calloutIcon: CGFloat = 26
    /// `TWAIN_PROFILE=1` logs each restyle's phases.
    static let profile = ProcessInfo.processInfo.environment["TWAIN_PROFILE"] != nil

    private(set) var typo: Typography
    private(set) var style: EditorStyle
    /// Resolves `![[name]]` / `![](path)` to a file.
    var resolveEmbed: (String) -> URL? = { _ in nil }
    /// Resolves `![[another note]]` to that note and its text.
    var resolveNote: (String) -> (rel: String, title: String, text: String)? = { _ in nil }
    /// The plugin page (vault-relative) that renders a fence language, if any.
    var pluginPage: (String) -> String? = { _ in nil }
    /// Called when an embed or picture finished loading and its line needs restyling.
    var needsRestyle: () -> Void = {}
    /// Pictures are rendered for the light or the dark appearance.
    var dark = false { didSet { if dark != oldValue { everything = true } } }
    /// 0 for the editor; an embedded note is styled at depth 1 and doesn't embed notes again.
    var depth = 0
    /// The line to style first when there is more to do than one slice (the top of the view).
    var priorityLine = 0
    /// Lines are still waiting for a slice.
    private(set) var pending = false

    private enum Mode: Equatable { case normal, head, collapsed, tail }

    private struct Sig: Equatable {
        var forced: BlockType?
        var codeTop = false
        var codeBottom = false
        var lang = 0
        var active = false
        var reveal = false
        var first = false
        var embedStamp = 0
        var mode = Mode.normal
        /// Lines in the block, for its head (and tail): the picture changes with it.
        var blockLen = 0
        var layout = 0
        var folded = false
        /// Styled with a picture that was still being rendered; `stamp` moves when one arrives.
        var waiting = false
        var stamp = 0
        /// Left for a later slice.
        var unstyled = false
    }

    private struct Role {
        var forced: BlockType?
        var codeTop = false
        var codeBottom = false
        var lang = 0
    }

    private struct Block {
        enum Kind: Equatable { case table, math, diagram, plugin(String), callout }
        var kind: Kind
        var first: Int
        var last: Int
        /// Callouts: the head line's text, which names the fold state.
        var key = ""
        var foldable = false
        var folded = false
    }

    /// Line starts and heads of the text as of the last restyle (TwainCore's LineTable).
    private var lines = LineTable()
    var lineStarts: [Int] { lines.starts }
    /// The one edit since the last restyle, when there was exactly one: lines are then scanned
    /// again only where it happened.
    private var singleEdit: (range: NSRange, delta: Int)?
    private var editCount = 0
    private var sigs: [Sig] = []
    private var blocks: [Block] = []
    private var blockOf: [Int32] = []
    /// Characters edited since the last restyle, in current coordinates; nil when none.
    private var dirtyChars: NSRange?
    private var everything = true
    /// Lines showing an embed, by target, and a stamp bumped when one of them finishes loading.
    private var embedStamps: [String: Int] = [:]
    private var markWidths: [String: CGFloat] = [:]
    private var langs: [String] = [""]
    private var langIDs: [String: Int] = ["": 0]
    private var renderStamp = 0
    private var layoutStamp = 0
    private var readyScheduled = false
    /// Callouts the user folded or opened, by their head line.
    private var foldOverrides: [String: Bool] = [:]
    private(set) var containerWidth: CGFloat = 600
    /// Bumped by anything besides text and caret that changes how lines render.
    private var generation = 0
    private var lastGeneration = -1
    private var lastLength = -1
    private var lastState: (Int?, Bool?) = (nil, nil)

    init(style: EditorStyle) {
        self.style = style
        typo = Typography(style.font)
    }

    func setStyle(_ s: EditorStyle) {
        guard s != style else { return }
        if s.font != style.font { typo = Typography(s.font); markWidths = [:] }
        style = s
        everything = true
        generation += 1
    }

    func setContainerWidth(_ w: CGFloat) {
        guard abs(w - containerWidth) > 0.5 else { return }
        containerWidth = w
        // Embeds, tables and pictures scale with the column.
        for k in embedStamps.keys { embedStamps[k, default: 0] += 1 }
        layoutStamp += 1
        generation += 1
    }

    /// Everything changed (new note, new style).
    func reset() { everything = true; dirtyChars = nil; editCount = 0; singleEdit = nil }

    /// A new note: folds the user toggled belong to the old one.
    func newDocument() { reset(); foldOverrides = [:] }

    /// Notes shown embedded changed on disk.
    func notesChanged() {
        for k in embedStamps.keys { embedStamps[k, default: 0] += 1 }
        generation += 1
    }

    /// Records a text edit reported by the text storage (new coordinates).
    func noteEdit(_ range: NSRange, delta: Int) {
        editCount += 1
        singleEdit = editCount == 1 ? (range, delta) : nil
        guard var d = dirtyChars else { dirtyChars = range; return }
        if NSMaxRange(d) >= range.location - max(0, -delta) { d.length = max(0, d.length + delta) }
        dirtyChars = NSUnionRange(d, range)
    }

    /// Opens or folds the callout whose head line reads `key`.
    func toggleFold(_ key: String) {
        guard let b = blocks.first(where: { $0.kind == .callout && $0.key == key }) else { return }
        foldOverrides[key] = !b.folded
        generation += 1
        needsRestyle()
    }

    // MARK: lines

    func lineIndex(at loc: Int) -> Int { lines.line(at: loc) }

    /// Whether line `i` sits inside a fenced code or math block, as of the last restyle.
    func isCode(line i: Int) -> Bool { i < sigs.count && sigs[i].forced == .code }

    /// Range of line `i` without its newline.
    func lineRange(_ i: Int, length: Int) -> NSRange {
        let start = lineStarts[i]
        let end = i + 1 < lineStarts.count ? lineStarts[i + 1] - 1 : length
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Brings the line table up to date: the lines one edit touched, or the whole text.
    private func scanLines(_ ns: NSString) {
        if let e = singleEdit, !everything { lines.update(ns, edited: e.range, delta: e.delta) } else { lines.scan(ns) }
        singleEdit = nil
        editCount = 0
    }

    /// Character `k` (0–3) of line `i`, 0 past its end.
    @inline(__always) private func char(_ i: Int, _ k: Int) -> unichar { lines.unit(i, k) }

    /// The first non-space among a line's first four characters.
    private func firstChar(_ i: Int) -> unichar? {
        for k in 0..<4 {
            let c = char(i, k)
            if c == 0 { return nil }
            if c != 0x20 { return c }
        }
        return nil
    }

    private func langID(_ lang: String) -> Int {
        if let id = langIDs[lang] { return id }
        langs.append(lang)
        langIDs[lang] = langs.count - 1
        return langs.count - 1
    }

    private func renderKind(_ lang: String) -> Block.Kind? {
        if lang == "mermaid" { return .diagram }
        if !lang.isEmpty, let page = pluginPage(lang) { return .plugin(page) }
        return nil
    }

    /// `> [!kind]` at quote depth 0: its markup (for the fold marker), nil for other quote lines.
    private static func calloutHead(_ text: String) -> LineMarkup? {
        var s = Substring(text)
        guard s.hasPrefix(">") else { return nil }
        s = s.dropFirst()
        if s.hasPrefix(" ") { s = s.dropFirst() }
        guard s.hasPrefix("[!") else { return nil }
        let m = Markdown.parseLine(text, type: .quote)
        return m.callout != nil && m.depth == 0 ? m : nil
    }

    // MARK: restyle

    /// Brings the storage's attributes up to date. `caret` is nil when the editor isn't focused.
    /// Returns the ranges it restyled, for the layout manager to redo. Unless `force`, a large
    /// restyle stops after one slice and sets `pending`.
    @discardableResult
    func restyle(_ storage: NSTextStorage, caret: Int?, force: Bool = false) -> [NSRange] {
        let ns = storage.string as NSString
        let len = ns.length
        // The caret moved within its line and nothing else changed: nothing to restyle. This is
        // the second restyle of every keystroke (text, then selection), so it matters.
        // Line positions are only valid for the text of the last restyle, so the caret's line is
        // looked up only once the text is known to be the same.
        let unchanged = !everything && !pending && dirtyChars == nil && len == lastLength && generation == lastGeneration
            && !sigs.isEmpty && sigs.count == lineStarts.count
        var state: (Int?, Bool?) = (nil, nil)
        if unchanged {
            let line = caret.map { lineIndex(at: min($0, len)) }
            state = (line, caret.flatMap { c in line.map { reveals(ns, lineRange($0, length: len), caret: min(c, len) - lineStarts[$0], forced: sigs[$0].forced) } })
            if state.0 == lastState.0, state.1 == lastState.1 { return [] }
        }
        lastLength = len
        lastGeneration = generation
        let oldCount = sigs.count
        let t0 = CACurrentMediaTime()
        scanLines(ns)
        let tScan = CACurrentMediaTime()
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

        // Pass 1: what each line is, and the blocks that span lines.
        var roles = [Role](repeating: Role(), count: n)
        var found: [Block] = []
        var ctx = BlockContext.none
        var fence: (line: Int, lang: String, id: Int, math: Bool)?
        var table: Int?
        var callout: Int?
        for i in 0..<n {
            let r = lineRange(i, length: len)
            let c = firstChar(i)
            var role = Role()
            if ctx == .none, let c {
                if c == 0x7C {   // |
                    if let t = table, found[t].last == i - 1 {
                        found[t].last = i
                    } else if i + 1 < n, firstChar(i + 1) == 0x7C,
                              MarkdownTable.isSeparator(ns.substring(with: lineRange(i + 1, length: len))) {
                        table = found.count
                        found.append(Block(kind: .table, first: i, last: i))
                    }
                } else if c == 0x3E {   // >
                    // `>[!` or `> [!` could open a callout; only those need their text.
                    let opens = char(i, 0) == 0x3E && ((char(i, 1) == 0x5B && char(i, 2) == 0x21) || (char(i, 1) == 0x20 && char(i, 2) == 0x5B && char(i, 3) == 0x21))
                    let text = opens ? ns.substring(with: r) : ""
                    if opens, let head = Self.calloutHead(text) {
                        callout = found.count
                        var b = Block(kind: .callout, first: i, last: i)
                        b.key = text
                        b.foldable = head.calloutFolded != nil
                        b.folded = b.foldable && (foldOverrides[text] ?? head.calloutFolded ?? false)
                        found.append(b)
                    } else if let k = callout, found[k].last == i - 1 {
                        found[k].last = i
                    }
                }
            }
            if needsText(i, r, ctx) {
                let text = ns.substring(with: r)
                let before = ctx
                let (forced, next) = Markdown.role(of: text, index: i, context: ctx)
                role.forced = forced
                if forced == .fence {
                    role.codeTop = next != .none
                    role.codeBottom = next == .none
                    if before == .none {
                        let lang = next == .math ? "" : Markdown.fenceInfo(text)
                        role.lang = langID(lang)
                        fence = (i, lang, role.lang, next == .math)
                    } else if let f = fence {
                        role.lang = f.id
                        if f.math { found.append(Block(kind: .math, first: f.line, last: i)) }
                        else if let kind = renderKind(f.lang) { found.append(Block(kind: kind, first: f.line, last: i)) }
                        fence = nil
                    }
                } else if before == .none, forced == nil, c == 0x24, Markdown.displayMath(text) != nil {
                    found.append(Block(kind: .math, first: i, last: i))
                }
                ctx = next
            } else if ctx != .none {
                role.forced = ctx == .frontmatter ? .frontmatter : .code
            }
            if role.forced == .code, let f = fence { role.lang = f.id }
            roles[i] = role
        }
        var owner = [Int32](repeating: -1, count: n)
        for (k, b) in found.enumerated() { for j in b.first...b.last { owner[j] = Int32(k) } }
        blocks = found
        blockOf = owner

        let tPass1 = CACurrentMediaTime()
        // Pass 2: each line's rendering state, compared with last time.
        let activeLine = caret.map { lineIndex(at: min($0, len)) }
        let activeBlock = activeLine.map { Int(owner[$0]) } ?? -1
        var dirtyBlocks = Set<Int>()
        if textB >= textA { for j in textA...min(textB, n - 1) where owner[j] >= 0 { dirtyBlocks.insert(Int(owner[j])) } }
        var newSigs = [Sig](repeating: Sig(), count: n)
        var dirty: [Int] = []
        for i in 0..<n {
            let r = lineRange(i, length: len)
            let role = roles[i]
            var sig = Sig(forced: role.forced, codeTop: role.codeTop, codeBottom: role.codeBottom, lang: role.lang)
            sig.first = i == 0
            let b = Int(owner[i])
            if b >= 0 {
                let block = found[b]
                let count = block.last - block.first + 1
                if block.kind == .callout {
                    if i == block.first { sig.folded = block.folded; sig.blockLen = block.foldable ? count : 0 }
                    else if block.folded, b != activeBlock { sig.mode = .collapsed }
                } else if b == activeBlock {
                    if block.kind != .table, i == block.last { sig.mode = .tail; sig.blockLen = count; sig.layout = layoutStamp }
                } else {
                    sig.mode = i == block.first ? .head : .collapsed
                    if i == block.first { sig.blockLen = count; sig.layout = layoutStamp }
                }
            }
            if i == activeLine {
                sig.active = true
                sig.reveal = reveals(ns, r, caret: caret! - r.location, forced: sig.forced)
            }
            if let target = embedTarget(ns, i, r, forced: sig.forced) { sig.embedStamp = embedStamps[target, default: 0] }
            let textDirty = all || (i >= textA && i <= textB) || (b >= 0 && dirtyBlocks.contains(b))
            let old = i < textA ? i : i - lineDelta
            if !textDirty, old >= 0, old < oldCount, sigs[old].waiting {
                sig.waiting = true
                sig.stamp = renderStamp
            }
            newSigs[i] = sig
            if textDirty || old < 0 || old >= oldCount || sigs[old] != sig { dirty.append(i) }
        }
        sigs = newSigs
        pending = false
        lastState = (activeLine, activeLine.map { sigs[$0].reveal })
        let tPass2 = CACurrentMediaTime()
        defer {
            if Self.profile {
                let t = CACurrentMediaTime()
                FileHandle.standardError.write(String(format: "styler scan %.2f pass1 %.2f pass2 %.2f style %.2f lines %d dirty %d\n", (tScan - t0) * 1000,
                    (tPass1 - tScan) * 1000, (tPass2 - tPass1) * 1000, (t - tPass2) * 1000, n, dirty.count).data(using: .utf8)!)
            }
        }
        guard !dirty.isEmpty else { return [] }

        var todo = dirty
        if !force, dirty.count > Self.budget {
            // Nearest to the top of the view first, below it before above it; a block's lines go together.
            let focus = min(max(0, priorityLine), n - 1)
            func distance(_ i: Int) -> Int {
                let head = owner[i] >= 0 ? found[Int(owner[i])].first : i
                return head >= focus ? head - focus : (focus - head) * 3
            }
            var chosen = Set(dirty.sorted { distance($0) < distance($1) }.prefix(Self.budget))
            let touched = Set(chosen.compactMap { owner[$0] >= 0 ? owner[$0] : nil })
            if !touched.isEmpty { for i in dirty where owner[i] >= 0 && touched.contains(owner[i]) { chosen.insert(i) } }
            todo = dirty.filter { chosen.contains($0) }
            for i in dirty where !chosen.contains(i) { sigs[i].unstyled = true }
            pending = true
        }

        var ranges: [NSRange] = []
        storage.beginEditing()
        for i in todo {
            let r = lineRange(i, length: len)
            let full = NSRange(location: r.location, length: r.length + (i + 1 < n ? 1 : 0))
            let waiting = styleLine(storage, ns, i, r, full, sigs[i])
            sigs[i].waiting = waiting
            sigs[i].stamp = waiting ? renderStamp : 0
            if let last = ranges.last, NSMaxRange(last) == full.location {
                ranges[ranges.count - 1].length += full.length
            } else {
                ranges.append(full)
            }
        }
        storage.endEditing()
        return ranges
    }

    /// What a line looks like before it is styled: new text comes in with these, so lines left for
    /// a later slice read as body text (not as whatever the old first character was).
    func baseAttributes() -> [NSAttributedString.Key: Any] {
        let body = typo.body
        let p = NSMutableParagraphStyle()
        p.lineSpacing = max(0, body.pointSize * 1.8 - (body.ascender - body.descender + body.leading))
        p.paragraphSpacing = 12
        p.firstLineHeadIndent = Self.gutter
        p.headIndent = Self.gutter
        p.tailIndent = -Self.gutter
        return [.font: style.plain ? typo.mono(size: 14) : body, .foregroundColor: Theme.NS.ink, .paragraphStyle: p]
    }

    private func needsText(_ i: Int, _ r: NSRange, _ ctx: BlockContext) -> Bool {
        guard let c = firstChar(i) else { return false }
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

    private func embedTarget(_ ns: NSString, _ i: Int, _ r: NSRange, forced: BlockType?) -> String? {
        guard forced == nil, r.length > 4, char(i, 0) == 0x21 else { return nil }   // !
        return Markdown.parseLine(ns.substring(with: r)).blockEmbed
    }

    // MARK: pictures

    private func picture(_ kind: RenderKind, _ source: String, size: CGFloat, width: CGFloat = 0) -> Rendered? {
        let key = BlockRenderer.Key(kind: kind, source: source, dark: dark, fontSize: size, width: width)
        return BlockRenderer.shared.rendered(key) { [weak self] in self?.pictureReady() }
    }

    private func pictureReady() {
        renderStamp += 1
        generation += 1
        guard !readyScheduled else { return }
        readyScheduled = true
        // Pictures of one batch arrive together; restyle once for all of them.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            readyScheduled = false
            needsRestyle()
        }
    }

    /// The drawing for a rendered block, and whether it still waits for a picture.
    private func blockDeco(_ b: Block, _ ns: NSString, revealed: Bool) -> (BlockDeco, Bool) {
        let len = ns.length
        let avail = max(120, containerWidth - 2 * Self.gutter)
        func text(_ i: Int) -> String { ns.substring(with: lineRange(i, length: len)) }
        func inner() -> String {
            b.last > b.first + 1 ? ((b.first + 1)..<b.last).map(text).joined(separator: "\n") : ""
        }
        func pictureDeco(_ kind: RenderKind, _ source: String, width: CGFloat = 0) -> (BlockDeco, Bool) {
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let r = Rendered(image: nil, size: CGSize(width: avail, height: 36), baseline: 36, error: kind == .block ? "（空公式）" : "（空代码块）")
                return (BlockDeco(.picture(r, kind: kind), height: 36, revealed: revealed), false)
            }
            let r = picture(kind, source, size: typo.bodySize, width: width)
            let h = BlockDeco.pictureHeight(r, kind: kind, width: avail)
            return (BlockDeco(.picture(r, kind: kind), height: h, revealed: revealed), r == nil)
        }
        switch b.kind {
        case .table:
            let lines = (b.first...b.last).map(text)
            let t = MarkdownTable.parse(lines) ?? MarkdownTable(header: [], aligns: [], rows: [])
            let base = lineStarts[b.first]
            let rows = [b.first] + (b.first + 2 > b.last ? [] : Array((b.first + 2)...b.last))
            let layout = TableLayout(t, rowOffsets: rows.map { lineStarts[$0] - base }, available: avail, typo: typo,
                                     fontSize: typo.bodySize - 1) { [weak self] src, size in self?.picture(.inline, src, size: size) }
            return (BlockDeco(.table(layout), height: layout.height, revealed: revealed), layout.waiting)
        case .math:
            let source = b.first == b.last ? Markdown.displayMath(text(b.first)) ?? "" : inner()
            return pictureDeco(.block, source)
        case .diagram:
            return pictureDeco(.diagram, inner())
        case let .plugin(page):
            return pictureDeco(.plugin(page: page), inner(), width: avail.rounded())
        case .callout:
            return pictureDeco(.block, "")
        }
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

    /// A line that belongs to a rendered block but isn't where it is drawn: no height at all.
    private func collapse(_ storage: NSTextStorage, _ r: NSRange, _ full: NSRange) {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = 0.01
        p.maximumLineHeight = 0.01
        p.firstLineHeadIndent = Self.gutter
        p.headIndent = Self.gutter
        p.tailIndent = -Self.gutter
        storage.setAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: p], range: full)
        if r.length > 0 { storage.addAttribute(.twainHidden, value: true, range: r) }
    }

    /// The first line of a block drawn as a picture: as tall as the picture, its text hidden.
    private func styleHead(_ storage: NSTextStorage, _ ns: NSString, _ i: Int, _ r: NSRange, _ full: NSRange, _ sig: Sig) -> Bool {
        let b = blocks[Int(blockOf[i])]
        let (deco, waiting) = blockDeco(b, ns, revealed: false)
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = deco.height
        p.maximumLineHeight = deco.height
        p.paragraphSpacingBefore = sig.first ? 0 : 10
        p.paragraphSpacing = 16
        p.firstLineHeadIndent = Self.gutter
        p.headIndent = Self.gutter
        p.tailIndent = -Self.gutter
        storage.setAttributes([.font: typo.body, .foregroundColor: NSColor.clear, .paragraphStyle: p, .twainBlock: deco], range: full)
        if r.length > 0 { storage.addAttribute(.twainHidden, value: true, range: r) }
        return waiting
    }

    /// Styles one line; returns true when it shows a picture that is still being rendered.
    private func styleLine(_ storage: NSTextStorage, _ ns: NSString, _ i: Int, _ r: NSRange, _ full: NSRange, _ sig: Sig) -> Bool {
        guard full.length > 0 else { return false }
        if style.plain {
            let font = typo.mono(size: 14)
            let p = paragraph(.code, font: font, first: false)
            storage.setAttributes([.font: font, .foregroundColor: Theme.NS.ink, .paragraphStyle: p], range: full)
            typo.applyCJK(storage, in: r)
            return false
        }
        switch sig.mode {
        case .collapsed:
            collapse(storage, r, full)
            return false
        case .head:
            return styleHead(storage, ns, i, r, full, sig)
        case .normal, .tail:
            break
        }
        let text = ns.substring(with: r)
        // A one-line `$$…$$` being edited reads as source, like a math block.
        let type = sig.forced ?? (sig.mode == .tail ? .code : Markdown.blockType(text))
        let ink = Theme.NS.ink, mark = Theme.NS.mark
        let body = typo.body
        let bodySize = typo.bodySize

        // Literal blocks: code, fences, front matter.
        if type.isLiteral {
            let size: CGFloat = type == .code ? (bodySize * 0.84).rounded() : 13
            let font = typo.mono(size: size)
            let p = paragraph(type, font: font, first: sig.first)
            let inset: CGFloat = type == .frontmatter ? 0 : 14
            p.firstLineHeadIndent += inset
            p.headIndent += inset
            p.tailIndent -= inset
            if sig.codeTop || (sig.mode == .tail && sig.forced == nil) { p.paragraphSpacingBefore = sig.first ? 0 : 8 }
            if sig.codeBottom || sig.mode == .tail { p.paragraphSpacing = 12 }
            var preview: (BlockDeco, Bool)?
            if sig.mode == .tail, blockOf[i] >= 0 {
                preview = blockDeco(blocks[Int(blockOf[i])], ns, revealed: true)
                p.paragraphSpacing += preview!.0.height + 20
            }
            let color = type == .code ? ink : mark
            storage.setAttributes([.font: font, .foregroundColor: type == .frontmatter ? Theme.NS.quote : color, .paragraphStyle: p], range: full)
            if type != .frontmatter {
                let single = sig.mode == .tail && sig.forced == nil
                storage.addAttribute(.twainDeco, value: Deco(.code(top: sig.codeTop || single, bottom: sig.codeBottom || single), contentX: p.headIndent), range: full)
            }
            if type == .code, sig.lang > 0, sig.lang < langs.count {
                for t in CodeHighlight.tokens(text, language: langs[sig.lang]) {
                    storage.addAttribute(.foregroundColor, value: Theme.NS.code(t.token),
                                         range: NSRange(location: r.location + t.range.location, length: t.range.length))
                }
            }
            if let preview { storage.addAttribute(.twainBlock, value: preview.0, range: full) }
            typo.applyCJK(storage, in: r)
            return preview?.1 ?? false
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
        default: type == .table ? bodySize - 1 : m.footnoteLabel != nil ? bodySize - 2 : bodySize
        }
        let weight: NSFont.Weight = level == 1 ? .bold : level != nil ? .semibold : .regular
        let font = typo.font(size: size, weight: weight)
        let p = paragraph(type, font: font, first: sig.first)
        var color = type == .quote || m.footnoteLabel != nil ? Theme.NS.quote : level == 6 ? Theme.NS.quote : ink

        // Where the content starts, and how the prefix hangs to its left.
        let ws = text.prefix { $0 == " " || $0 == "\t" }.utf16.count
        let markerRange = NSRange(location: r.location + (type.isList ? ws : 0),
                                  length: m.prefix.length - (type.isList ? ws : 0))
        let markFont = level != nil ? typo.mono(size: min(15, (size * 0.62).rounded())) : body
        var contentX = Self.gutter
        var deco: Deco.Kind?
        var callout: (head: CalloutHead, tint: NSColor)?
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
            let tint = m.callout.map(Self.calloutColor)
            var head: CalloutHead?
            if let kind = m.callout, blockOf.indices.contains(i), blockOf[i] >= 0 {
                let b = blocks[Int(blockOf[i])]
                if b.kind == .callout, b.first == i {
                    head = CalloutHead(kind: kind, untitled: r.length <= m.prefix.length, folded: b.foldable ? b.folded : nil, key: b.key)
                    callout = (head!, tint!)
                }
            }
            deco = .quote(depth: m.depth, tint: tint, head: head)
            if m.callout != nil { color = ink }
        case .hr where !sig.active:
            deco = .hr
        case .p where m.footnoteLabel != nil:
            contentX += Self.listUnit
            deco = .footnote(m.footnoteLabel!)
        default: break
        }
        let revealPrefix = sig.reveal && markerRange.length > 0
        let hang = revealPrefix ? markWidth(ns.substring(with: markerRange), markFont) : 0
        p.headIndent = contentX
        p.firstLineHeadIndent = max(0, contentX - hang)
        if revealPrefix, type.isList || type == .quote || m.footnoteLabel != nil {
            if case let .quote(depth, tint, _) = deco { deco = .quote(depth: depth, tint: tint, head: nil) } else { deco = nil }
            callout = nil
        }
        if callout != nil {
            // Room for the icon; a wrapped title lines up with its first line.
            p.firstLineHeadIndent = contentX + Self.calloutIcon
            p.headIndent = contentX + Self.calloutIcon
        }

        // A line that is just an image, or another note: the picture is the line.
        if let target = m.blockEmbed {
            if Embed.kind(of: target) != .other {
                let url = resolveEmbed(target)
                let embed = EmbedCache.shared.embed(target: target, url: url) { [weak self] in
                    guard let self else { return }
                    self.embedStamps[target, default: 0] += 1
                    self.generation += 1
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
                return false
            }
            if depth == 0, let note = resolveNote(target) {
                let parts = target.split(separator: "|", maxSplits: 1).first.map(String.init) ?? target
                let section = parts.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init)
                let e = NoteEmbedCache.shared.embed(rel: note.rel, title: note.title, section: section, text: note.text, style: style,
                                                    width: max(160, containerWidth - 2 * Self.gutter), dark: dark,
                                                    resolveEmbed: resolveEmbed) { [weak self] in
                    guard let self else { return }
                    self.embedStamps[target, default: 0] += 1
                    self.generation += 1
                    self.needsRestyle()
                }
                let h = e.height
                if sig.active {
                    p.paragraphSpacing = h + 16
                    storage.setAttributes([.font: typo.font(size: 13), .foregroundColor: mark, .paragraphStyle: p], range: full)
                } else {
                    p.lineSpacing = 0
                    p.minimumLineHeight = h
                    p.maximumLineHeight = h
                    p.paragraphSpacing = 12
                    storage.setAttributes([.font: body, .foregroundColor: NSColor.clear, .paragraphStyle: p], range: full)
                    if r.length > 0 { storage.addAttribute(.twainHidden, value: true, range: r) }
                }
                storage.addAttributes([.twainBlock: BlockDeco(.note(e), height: h, revealed: sig.active),
                                       .twainWikiLink: note.title], range: full)
                return false
            }
        }

        storage.setAttributes([.font: font, .foregroundColor: color, .paragraphStyle: p], range: full)
        if level == 1 { storage.addAttribute(.kern, value: -0.012 * size, range: r) }
        if let deco { storage.addAttribute(.twainDeco, value: Deco(deco, contentX: contentX), range: full) }
        guard r.length > 0 else { return false }
        let abs = { (x: NSRange) in NSRange(location: r.location + x.location, length: x.length) }

        if type == .hr {
            if sig.active { storage.addAttribute(.foregroundColor, value: mark, range: r) }
            else { storage.addAttribute(.twainHidden, value: true, range: r) }
            return false
        }
        if type == .table {
            for (k, c) in text.utf16.enumerated() where c == 0x7C {   // |
                storage.addAttribute(.foregroundColor, value: mark, range: NSRange(location: r.location + k, length: 1))
            }
        }
        if type == .task, Markdown.isTaskDone(text) {
            let bodyR = NSRange(location: r.location + m.prefix.length, length: r.length - m.prefix.length)
            storage.addAttributes([.foregroundColor: Theme.NS.doneText, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .strikethroughColor: Theme.NS.strike], range: bodyR)
        }
        if let callout, r.length > m.prefix.length {
            let title = NSRange(location: r.location + m.prefix.length, length: r.length - m.prefix.length)
            storage.addAttributes([.font: typo.font(size: size, weight: .semibold), .foregroundColor: callout.tint], range: title)
        }
        let accent = Theme.NS.accent
        var waiting = false
        var pictures: [(InlineSpan, Rendered)] = []
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
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Theme.NS.doneText], range: x)
            case .highlight:
                storage.addAttribute(.backgroundColor, value: Theme.NS.highlight.withAlphaComponent(0.4), range: x)
            case let .wikilink(title):
                storage.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .underlineColor: accent.withAlphaComponent(0.3), .twainWikiLink: title], range: x)
            case let .link(url):
                storage.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .underlineColor: accent.withAlphaComponent(0.3), .twainURL: url], range: x)
            case let .embed(target), let .image(target):
                storage.addAttributes([.foregroundColor: accent], range: x)
                if let u = resolveEmbed(target) { storage.addAttribute(.twainURL, value: u.absoluteString, range: x) }
                else if case .embed = span.kind { storage.addAttribute(.twainWikiLink, value: target, range: x) }
            case let .tag(name):
                storage.addAttributes([.foregroundColor: Theme.NS.tag, .twainTag: name], range: x)
            case let .footnote(label):
                storage.addAttributes([.font: typo.font(size: (size * 0.72).rounded()), .baselineOffset: (size * 0.36).rounded(),
                                       .foregroundColor: accent, .twainFootnote: label], range: x)
            case let .math(src):
                let rendered = sig.active ? nil : picture(.inline, src, size: size)
                if let rendered, rendered.image != nil {
                    pictures.append((span, rendered))
                } else {
                    if !sig.active, rendered == nil { waiting = true }
                    let tone: NSColor = rendered?.error != nil ? .systemRed : sig.active ? ink : Theme.NS.quote
                    storage.addAttributes([.font: typo.mono(size: (size * 0.86).rounded()), .foregroundColor: tone], range: x)
                }
            }
        }
        // Syntax: shown dimmed where the caret is, hidden elsewhere. List markers hang in the margin.
        let indentRange = NSRange(location: r.location, length: type.isList ? ws : 0)
        if indentRange.length > 0 { storage.addAttribute(.twainHidden, value: true, range: indentRange) }
        if markerRange.length > 0 {
            if revealPrefix { storage.addAttributes([.foregroundColor: mark, .font: markFont], range: markerRange) }
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
        // Inline math: the whole `$…$` hides behind its opening `$`, which becomes the picture.
        if !pictures.isEmpty {
            var ascent = font.ascender, descent = -font.descender
            for (span, pic) in pictures {
                let whole = abs(NSRange(location: span.marks[0].location, length: NSMaxRange(span.marks[1]) - span.marks[0].location))
                storage.addAttribute(.twainHidden, value: true, range: whole)
                let anchor = NSRange(location: whole.location, length: 1)
                storage.removeAttribute(.twainHidden, range: anchor)
                storage.addAttributes([.twainInline: InlinePicture(pic), .foregroundColor: ink], range: anchor)
                ascent = max(ascent, pic.baseline)
                descent = max(descent, pic.size.height - pic.baseline)
            }
            // Tall formulas (fractions, sums) get a taller line instead of overlapping the next.
            if ascent > font.ascender + 1 || descent > -font.descender + 3 {
                let q = p.mutableCopy() as! NSMutableParagraphStyle
                q.minimumLineHeight = ceil(ascent + descent + font.leading)
                storage.addAttribute(.paragraphStyle, value: q, range: full)
            }
        }
        return waiting
    }

    /// Obsidian's callout colours.
    static func calloutColor(_ kind: String) -> NSColor {
        switch kind {
        case "abstract", "summary", "tldr", "tip", "hint", "important": .systemTeal
        case "success", "check", "done": .systemGreen
        case "question", "help", "faq", "warning", "caution", "attention": .systemOrange
        case "failure", "fail", "missing", "danger", "error", "bug": .systemRed
        case "example": .systemPurple
        case "quote", "cite": .secondaryLabelColor
        default: .systemBlue
        }
    }
}
