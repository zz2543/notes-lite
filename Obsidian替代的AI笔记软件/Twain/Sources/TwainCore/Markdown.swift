import Foundation

/// What a line is. Most lines are one block on their own; fenced code and front matter span
/// several and need the line's `BlockContext` (see `Markdown.roles`).
public enum BlockType: String, Sendable {
    case h1, h2, h3, h4, h5, h6, task, li, ol, quote, hr, empty, p, table
    /// A ``` or ~~~ line that opens or closes a code block.
    case fence
    /// A line inside a fenced code block or a `$$` math block.
    case code
    /// A line of YAML front matter, delimiters included.
    case frontmatter

    public var isHeading: Bool { headingLevel != nil }
    public var isList: Bool { self == .li || self == .task || self == .ol }
    public var headingLevel: Int? {
        switch self {
        case .h1: 1
        case .h2: 2
        case .h3: 3
        case .h4: 4
        case .h5: 5
        case .h6: 6
        default: nil
        }
    }
    /// Lines whose content is literal: no inline markup applies.
    public var isLiteral: Bool { self == .fence || self == .code || self == .frontmatter }
}

public struct InlineSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bold, italic, code, strike, highlight
        case wikilink(String)
        case link(String)
        /// `![[target]]`: an attachment or another note shown in place.
        case embed(String)
        /// `![alt](url)`.
        case image(String)
        case tag(String)
        /// `$x^2$`: inline math, the TeX source.
        case math(String)
        /// `[^1]`: a footnote reference, by label.
        case footnote(String)
    }
    public var kind: Kind
    /// Visible content, UTF-16 range within the line.
    public var content: NSRange
    /// Syntax characters that are dimmed while editing and hidden otherwise.
    public var marks: [NSRange]
}

public struct LineMarkup: Equatable, Sendable {
    public var type: BlockType
    /// Block prefix such as `# `, `\t- [ ] `, `1. `, `> ` (length 0 when absent), indentation included.
    public var prefix: NSRange
    public var spans: [InlineSpan]
    /// Nesting of a list item (0 for top level) or of a quote (`> > ` is 1).
    public var depth: Int = 0
    /// `> [!note] Title`: the callout kind, lowercased.
    public var callout: String?
    /// `> [!note]-` starts folded (true), `> [!note]+` open (false); nil when it can't fold.
    public var calloutFolded: Bool?
    /// `[^1]: text` defines footnote `1`; the prefix covers `[^1]: `.
    public var footnoteLabel: String?

    public var allMarks: [NSRange] {
        var r = prefix.length > 0 ? [prefix] : []
        for s in spans { r.append(contentsOf: s.marks) }
        return r
    }

    /// The line is nothing but one embed (`![[a.png]]` or `![](a.png)`), so it can be shown as a block.
    public var blockEmbed: String? {
        guard spans.count == 1, prefix.length == 0 else { return nil }
        switch spans[0].kind {
        case let .embed(t), let .image(t): return t
        default: return nil
        }
    }
}

/// Multi-line state carried from one line to the next.
public enum BlockContext: Equatable, Sendable {
    case none
    /// Inside a fenced block opened by `fence` (e.g. "```" or "~~~~").
    case code(fence: String)
    case math
    case frontmatter
}

/// The ASCII characters present in part of a string, as a bitmap.
struct ASCIISet {
    private var lo: UInt64 = 0, hi: UInt64 = 0

    init(_ ns: NSString, _ r: NSRange) {
        var buf = [unichar](repeating: 0, count: r.length)
        ns.getCharacters(&buf, range: r)
        for c in buf where c < 0x80 {
            if c < 64 { lo |= 1 << UInt64(c) } else { hi |= 1 << UInt64(c - 64) }
        }
    }

    func contains(_ c: unichar) -> Bool {
        c < 64 ? lo & (1 << UInt64(c)) != 0 : c < 128 ? hi & (1 << UInt64(c - 64)) != 0 : false
    }
}

public enum Markdown {
    static let listRe = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+] \[[ xX]\] |[-*+] |\d{1,9}[.)] )"#)
    static let headingRe = try! NSRegularExpression(pattern: #"^(#{1,6}) "#)
    static let quoteRe = try! NSRegularExpression(pattern: #"^((?:> ?)+)"#)
    static let calloutRe = try! NSRegularExpression(pattern: #"^\[!([A-Za-z-]+)\]([+-]?)"#)
    /// `$…$` as Obsidian and Pandoc read it: no space inside either `$`, and no digit right
    /// after the closing one, so prices ("$5 and $6") stay text.
    static let mathRe = try! NSRegularExpression(pattern: #"(?<![\\$0-9A-Za-z])\$(?![\s$])((?:\\.|[^$\\])+?)(?<![\s\\])\$(?![0-9$])"#)
    static let footnoteRe = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\]"#)
    static let footnoteDefRe = try! NSRegularExpression(pattern: #"^\[\^([^\]\s]+)\]:[ \t]?"#)
    static let codeRe = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    static let boldRe = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*|__(.+?)__"#)
    static let italicRe = try! NSRegularExpression(pattern: #"(?<!\*)\*([^*\s](?:[^*]*[^*\s])?)\*(?!\*)|(?<![_\p{L}\p{N}])_([^_\s](?:[^_]*[^_\s])?)_(?![_\p{L}\p{N}])"#)
    static let strikeRe = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    static let highlightRe = try! NSRegularExpression(pattern: #"==(.+?)=="#)
    static let wikiRe = try! NSRegularExpression(pattern: #"\[\[(.+?)\]\]"#)
    static let embedRe = try! NSRegularExpression(pattern: #"!\[\[(.+?)\]\]"#)
    static let imageRe = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)
    static let linkRe = try! NSRegularExpression(pattern: #"\[([^\]\[]+)\]\(([^)]+)\)"#)
    static let urlRe = try! NSRegularExpression(pattern: #"https?://[^\s<>()（）\[\]，。、；：“”]+"#)
    static let tagRe = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&#/\-])#([\p{L}\p{N}_/\-]*[\p{L}_][\p{L}\p{N}_/\-]*)"#)

    // MARK: blocks

    /// Length of the block prefix (indentation, list marker, heading hashes, quote marks).
    public static func prefixLength(_ t: String) -> Int {
        parsePrefix(t).length
    }

    private static func parsePrefix(_ t: String) -> (type: BlockType, length: Int, depth: Int) {
        let ns = t as NSString
        let all = NSRange(location: 0, length: ns.length)
        guard ns.length > 0 else { return (.empty, 0, 0) }
        let first = ns.character(at: 0)
        if first == 0x23, let m = headingRe.firstMatch(in: t, range: all) { // #
            let level = m.range(at: 1).length
            return ([.h1, .h2, .h3, .h4, .h5, .h6][level - 1], m.range.length, 0)
        }
        if first == 0x3E, let m = quoteRe.firstMatch(in: t, range: all) { // >
            let depth = ns.substring(with: m.range).filter { $0 == ">" }.count - 1
            return (.quote, m.range.length, depth)
        }
        // Lists start with indentation, a bullet or a digit; everything else skips the regex.
        let listy = first == 0x20 || first == 0x09 || first == 0x2D || first == 0x2A || first == 0x2B || (first >= 0x30 && first <= 0x39)
        if listy, let m = listRe.firstMatch(in: t, range: all) {
            let marker = ns.substring(with: m.range(at: 2))
            let type: BlockType = marker.contains("[") ? .task : marker.first!.isNumber ? .ol : .li
            return (type, m.range.length, indentLevel(ns.substring(with: m.range(at: 1))))
        }
        return (.p, 0, 0)
    }

    /// Tabs count one level each; spaces count one level per two (four-space indents read as two).
    public static func indentLevel(_ ws: String) -> Int {
        var tabs = 0, spaces = 0
        for c in ws { if c == "\t" { tabs += 1 } else { spaces += 1 } }
        return tabs + spaces / 2
    }

    /// The type of a line on its own, as if it were outside any code block.
    public static func blockType(_ t: String) -> BlockType {
        if t.isEmpty { return .empty }
        if isFence(t) != nil { return .fence }
        if isRule(t) { return .hr }
        let p = parsePrefix(t)
        if p.type != .p { return p.type }
        if t.hasPrefix("|") { return .table }
        return t.allSatisfy(\.isWhitespace) ? .empty : .p
    }

    static func isRule(_ t: String) -> Bool {
        guard let f = t.utf16.first(where: { $0 != 0x20 && $0 != 0x09 }), f == 0x2D || f == 0x2A || f == 0x5F else { return false }
        let s = t.trimmingCharacters(in: .whitespaces)
        guard s.count >= 3, let c = s.first, c == "-" || c == "*" || c == "_" else { return false }
        return s.allSatisfy { $0 == c || $0 == " " } && s.filter { $0 == c }.count >= 3
    }

    /// The fence a line opens or closes with (```` ``` ````, `~~~~`…), nil if it is not a fence.
    public static func isFence(_ t: String) -> String? {
        guard let f = t.utf16.first(where: { $0 != 0x20 }), f == 0x60 || f == 0x7E else { return nil }
        let s = t.drop { $0 == " " }
        guard t.count - s.count <= 3, let c = s.first, c == "`" || c == "~" else { return nil }
        let run = s.prefix { $0 == c }
        guard run.count >= 3 else { return nil }
        // A backtick fence's info string may not contain backticks.
        if c == "`", s.dropFirst(run.count).contains("`") { return nil }
        return String(run)
    }

    /// The language named after an opening fence (```` ```mermaid ```` → "mermaid"), lowercased; "" when none.
    public static func fenceInfo(_ t: String) -> String {
        guard let f = isFence(t) else { return "" }
        let s = t.drop { $0 == " " }.dropFirst(f.count)
        let word = s.trimmingCharacters(in: .whitespaces).prefix { !$0.isWhitespace }
        return word.trimmingCharacters(in: CharacterSet(charactersIn: "{}.")).lowercased()
    }

    /// `$$E = mc^2$$` on a line of its own: display math in one line. Returns the TeX.
    public static func displayMath(_ t: String) -> String? {
        let s = t.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("$$"), s.hasSuffix("$$"), s.utf16.count > 4 else { return nil }
        let inner = s.dropFirst(2).dropLast(2)
        guard !inner.contains("$$"), !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return String(inner)
    }

    /// Role of each line given the lines before it: fences, code, front matter, math.
    /// `context` is the state before the line; the returned one is the state after it.
    public static func role(of line: String, index: Int, context: BlockContext) -> (type: BlockType?, next: BlockContext) {
        switch context {
        case .none:
            if index == 0, line == "---" { return (.frontmatter, .frontmatter) }
            if let f = isFence(line) { return (.fence, .code(fence: f)) }
            if line.trimmingCharacters(in: .whitespaces) == "$$" { return (.fence, .math) }
            return (nil, .none)
        case let .code(fence):
            if let f = isFence(line), f.first == fence.first, f.count >= fence.count,
               line.trimmingCharacters(in: .whitespaces).count == f.count {
                return (.fence, .none)
            }
            return (.code, context)
        case .math:
            if line.trimmingCharacters(in: .whitespaces) == "$$" { return (.fence, .none) }
            return (.code, context)
        case .frontmatter:
            if line == "---" || line == "..." { return (.frontmatter, .none) }
            return (.frontmatter, context)
        }
    }

    /// Block type of every line, with code blocks and front matter taken into account.
    public static func types(_ lines: [String]) -> [BlockType] {
        var ctx = BlockContext.none
        return lines.enumerated().map { i, l in
            let (forced, next) = role(of: l, index: i, context: ctx)
            ctx = next
            return forced ?? blockType(l)
        }
    }

    public static func isTaskDone(_ t: String) -> Bool {
        t.range(of: #"^[ \t]*[-*+] \[[xX]\] "#, options: .regularExpression) != nil
    }

    public static func orderedNumber(_ t: String) -> Int? {
        guard let r = t.range(of: #"^[ \t]*\d+"#, options: .regularExpression) else { return nil }
        return Int(t[r].trimmingCharacters(in: .whitespaces))
    }

    public static func toggleTask(_ t: String) -> String {
        guard let r = t.range(of: #"^[ \t]*[-*+] \[[ xX]\] "#, options: .regularExpression) else { return t }
        let marker = t[r]
        let box = marker.firstIndex(of: "[")!
        let state = marker[marker.index(after: box)]
        var out = t
        let at = t.index(after: box)
        out.replaceSubrange(at...at, with: state == " " ? "x" : " ")
        return out
    }

    /// What pressing Enter at the end of `line` should put on the next line.
    /// Returns nil when the line is not a list item. `exit` is true for an empty item: the
    /// item is removed (or outdented one level when nested) instead of continuing the list.
    public static func continuation(for line: String) -> (prefix: String, exit: Bool)? {
        let p = parsePrefix(line)
        guard p.type.isList else { return nil }
        let ns = line as NSString
        let pre = ns.substring(to: p.length)
        if ns.substring(from: p.length).allSatisfy(\.isWhitespace) { return ("", true) }
        let indent = String(pre.prefix { $0 == " " || $0 == "\t" })
        switch p.type {
        case .task:
            let bullet = pre.dropFirst(indent.count).first.map(String.init) ?? "-"
            return (indent + bullet + " [ ] ", false)
        case .ol:
            let delim = pre.contains(")") ? ")" : "."
            return (indent + "\((orderedNumber(line) ?? 0) + 1)" + delim + " ", false)
        default: return (pre, false)
        }
    }

    // MARK: inline

    /// Parses one line outside any multi-line block.
    public static func parseLine(_ t: String) -> LineMarkup {
        parseLine(t, type: blockType(t))
    }

    /// Parses one line whose block type is already known (from `types`/`role`).
    public static func parseLine(_ t: String, type: BlockType) -> LineMarkup {
        let ns = t as NSString
        if type.isLiteral || type == .hr || type == .empty || type == .table {
            return LineMarkup(type: type, prefix: NSRange(location: 0, length: 0), spans: [])
        }
        let pre = parsePrefix(t)
        let pl = pre.type == type ? pre.length : 0
        var markup = LineMarkup(type: type, prefix: NSRange(location: 0, length: pl), spans: [], depth: pre.depth)
        var bodyStart = pl
        if type == .quote, pl < ns.length, ns.character(at: pl) == 0x5B,
           let m = calloutRe.firstMatch(in: t, range: NSRange(location: pl, length: ns.length - pl)) {
            markup.callout = ns.substring(with: m.range(at: 1)).lowercased()
            let fold = m.range(at: 2)
            if fold.length > 0 { markup.calloutFolded = ns.character(at: fold.location) == 0x2D }
            markup.prefix.length = NSMaxRange(m.range)
            // Keep one space after the marker hidden with it.
            if markup.prefix.length < ns.length, ns.character(at: markup.prefix.length) == 0x20 { markup.prefix.length += 1 }
            bodyStart = markup.prefix.length
        }
        if type == .p, pl == 0, ns.length > 3, ns.character(at: 0) == 0x5B, ns.character(at: 1) == 0x5E,
           let m = footnoteDefRe.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) {
            markup.footnoteLabel = ns.substring(with: m.range(at: 1))
            markup.prefix = NSRange(location: 0, length: m.range.length)
            bodyStart = m.range.length
        }
        let body = NSRange(location: bodyStart, length: ns.length - bodyStart)
        guard body.length > 0 else { return markup }
        // Which syntax characters the line has at all: most lines skip most expressions.
        let has = ASCIISet(ns, body)
        let hasURL = has.contains(0x3A) && (t.contains("http://") || t.contains("https://"))
        var taken: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }
        func add(_ kind: InlineSpan.Kind, _ content: NSRange, _ marks: [NSRange], take: NSRange) {
            taken.append(take)
            markup.spans.append(InlineSpan(kind: kind, content: content, marks: marks))
        }
        func edges(_ m: NSTextCheckingResult, _ open: Int, _ close: Int) -> [NSRange] {
            [NSRange(location: m.range.location, length: open), NSRange(location: NSMaxRange(m.range) - close, length: close)]
        }
        func group(_ m: NSTextCheckingResult) -> NSRange {
            (1..<m.numberOfRanges).map { m.range(at: $0) }.first { $0.location != NSNotFound } ?? m.range
        }

        if has.contains(0x60) {   // `
            for m in codeRe.matches(in: t, range: body) {
                add(.code, m.range(at: 1), edges(m, 1, 1), take: m.range)
            }
        }
        // Math before links and emphasis: `_` and `*` inside TeX are not Markdown.
        if has.contains(0x24) {   // $
            for m in mathRe.matches(in: t, range: body) where free(m.range) {
                add(.math(ns.substring(with: m.range(at: 1))), m.range(at: 1), edges(m, 1, 1), take: m.range)
            }
        }
        let bracket = has.contains(0x5B)   // [
        if bracket, has.contains(0x5E) {   // ^
            for m in footnoteRe.matches(in: t, range: body) where free(m.range) {
                add(.footnote(ns.substring(with: m.range(at: 1))), m.range(at: 1), edges(m, 2, 1), take: m.range)
            }
        }
        for m in (bracket && has.contains(0x21) ? embedRe.matches(in: t, range: body) : []) where free(m.range) {
            add(.embed(ns.substring(with: m.range(at: 1))), m.range(at: 1), edges(m, 3, 2), take: m.range)
        }
        for m in (bracket && has.contains(0x21) ? imageRe.matches(in: t, range: body) : []) where free(m.range) {
            let alt = m.range(at: 1)
            let url = ns.substring(with: m.range(at: 2))
            // The alt text stays visible; everything else is syntax.
            add(.image(url), alt, [NSRange(location: m.range.location, length: 2),
                                   NSRange(location: NSMaxRange(alt), length: NSMaxRange(m.range) - NSMaxRange(alt))], take: m.range)
        }
        for m in (bracket ? wikiRe.matches(in: t, range: body) : []) where free(m.range) {
            add(.wikilink(ns.substring(with: m.range(at: 1))), m.range(at: 1), edges(m, 2, 2), take: m.range)
        }
        for m in (bracket && has.contains(0x28) ? linkRe.matches(in: t, range: body) : []) where free(m.range) {
            let text = m.range(at: 1)
            add(.link(ns.substring(with: m.range(at: 2))), text,
                [NSRange(location: m.range.location, length: 1),
                 NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text))], take: m.range)
        }
        for m in (hasURL ? urlRe.matches(in: t, range: body) : []) where free(m.range) {
            add(.link(ns.substring(with: m.range)), m.range, [], take: m.range)
        }
        // Emphasis may nest inside each other but not inside the spans above.
        let locked = taken
        func open(_ r: NSRange) -> Bool { !locked.contains { NSIntersectionRange($0, r).length > 0 } }
        var markerRanges: [NSRange] = []
        func emphasis(_ re: NSRegularExpression, _ kind: InlineSpan.Kind, _ width: Int, _ triggers: [unichar]) {
            guard triggers.contains(where: { has.contains($0) }) else { return }
            for m in re.matches(in: t, range: body) where open(m.range) {
                let marks = edges(m, width, width)
                if marks.contains(where: { mk in markerRanges.contains { NSIntersectionRange($0, mk).length > 0 } }) { continue }
                markerRanges += marks
                markup.spans.append(InlineSpan(kind: kind, content: group(m), marks: marks))
            }
        }
        emphasis(boldRe, .bold, 2, [0x2A, 0x5F])
        emphasis(strikeRe, .strike, 2, [0x7E])
        emphasis(highlightRe, .highlight, 2, [0x3D])
        emphasis(italicRe, .italic, 1, [0x2A, 0x5F])
        taken += markerRanges
        for m in (has.contains(0x23) ? tagRe.matches(in: t, range: body) : []) where free(m.range) {
            markup.spans.append(InlineSpan(kind: .tag(ns.substring(with: m.range(at: 1))), content: m.range, marks: []))
        }
        return markup
    }

    // MARK: text utilities

    /// CJK characters count one each, Latin words count one each (prototype's rule).
    public static func countWords(_ lines: [String]) -> Int {
        var cjk = 0, latin = 0
        var inWord = false
        for line in lines {
            let pl = prefixLength(line)
            for (i, scalar) in line.unicodeScalars.enumerated() {
                if i < pl { continue }
                let v = scalar.value
                if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) {
                    cjk += 1
                    inWord = false
                } else if (0x30...0x39).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) {
                    if !inWord { latin += 1; inWord = true }
                } else if inWord, v == 0x2E || v == 0x2C || v == 0x25 {
                    continue   // 2.0, 3,200, 50%
                } else {
                    inWord = false
                }
            }
            inWord = false
        }
        return cjk + latin
    }

    public static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    /// `[[旧名]]`, `[[旧名#小节]]`, `[[旧名|别名]]` → the same links to `new`; the count is how many changed.
    /// Titles match case-insensitively, as links resolve.
    public static func renamingWikiLinks(in text: String, from old: String, to new: String) -> (text: String, count: Int) {
        let ns = text as NSString
        var out = "", last = 0, count = 0
        for m in wikiRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: m.range(at: 1))
            let target = NoteOutline.linkTarget(inner)
            guard target.localizedCaseInsensitiveCompare(old) == .orderedSame,
                  let r = inner.range(of: target) else { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range(at: 1).location - last))
            out += inner.replacingCharacters(in: r, with: new)
            last = NSMaxRange(m.range(at: 1))
            count += 1
        }
        guard count > 0 else { return (text, 0) }
        return (out + ns.substring(from: last), count)
    }

    /// `[[旧/笔记]]` → `[[新/笔记]]` after the folder `old` became `new`.
    public static func movingWikiLinks(in text: String, from old: String, to new: String) -> (text: String, count: Int) {
        let ns = text as NSString
        var out = "", last = 0, count = 0
        let prefix = old.lowercased() + "/"
        for m in wikiRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let inner = m.range(at: 1)
            let target = ns.substring(with: inner)
            guard target.lowercased().hasPrefix(prefix) else { continue }
            out += ns.substring(with: NSRange(location: last, length: inner.location - last))
            out += new + "/" + target.dropFirst(prefix.count)
            last = NSMaxRange(inner)
            count += 1
        }
        guard count > 0 else { return (text, 0) }
        return (out + ns.substring(from: last), count)
    }

    /// The text of the first line when it is a `# ` heading.
    public static func titleHeading(_ text: String) -> String? {
        let first = text.prefix { $0 != "\n" }
        guard first.hasPrefix("# ") else { return nil }
        let t = first.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
