import Foundation

/// One line of a note is one block, exactly like the prototype.
public enum BlockType: String, Sendable {
    case h1, h2, h3, task, li, ol, quote, hr, empty, p

    public var isHeading: Bool { self == .h1 || self == .h2 || self == .h3 }
    public var isList: Bool { self == .li || self == .task || self == .ol }
}

public struct InlineSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bold, italic, code
        case wikilink(String)
        case link(String)
    }
    public var kind: Kind
    /// Visible content, UTF-16 range within the line.
    public var content: NSRange
    /// Syntax characters that are dimmed while editing and hidden otherwise.
    public var marks: [NSRange]
}

public struct LineMarkup: Equatable, Sendable {
    public var type: BlockType
    /// Block prefix such as `# `, `- [ ] `, `1. `, `> ` (length 0 when absent).
    public var prefix: NSRange
    public var spans: [InlineSpan]

    public var allMarks: [NSRange] {
        var r = prefix.length > 0 ? [prefix] : []
        for s in spans { r.append(contentsOf: s.marks) }
        return r
    }
}

public enum Markdown {
    static let prefixPattern = try! NSRegularExpression(pattern: #"^(#{1,3} |- \[[ xX]\] |[-*] |\d+\. |> )"#)
    static let codeRe = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    static let boldRe = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    static let italicRe = try! NSRegularExpression(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#)
    static let wikiRe = try! NSRegularExpression(pattern: #"\[\[(.+?)\]\]"#)
    static let linkRe = try! NSRegularExpression(pattern: #"\[([^\]\[]+)\]\(([^)]+)\)"#)

    public static func prefixLength(_ t: String) -> Int {
        let ns = t as NSString
        return prefixPattern.firstMatch(in: t, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
    }

    public static func blockType(_ t: String) -> BlockType {
        if t.hasPrefix("### ") { return .h3 }
        if t.hasPrefix("## ") { return .h2 }
        if t.hasPrefix("# ") { return .h1 }
        if t.range(of: #"^- \[[ xX]\] "#, options: .regularExpression) != nil { return .task }
        if t.hasPrefix("- ") || t.hasPrefix("* ") { return .li }
        if t.range(of: #"^\d+\. "#, options: .regularExpression) != nil { return .ol }
        if t.hasPrefix("> ") { return .quote }
        if t.range(of: #"^-{3,}$"#, options: .regularExpression) != nil { return .hr }
        if t.isEmpty { return .empty }
        return .p
    }

    public static func isTaskDone(_ t: String) -> Bool {
        t.range(of: #"^- \[[xX]\] "#, options: .regularExpression) != nil
    }

    public static func orderedNumber(_ t: String) -> Int? {
        guard let r = t.range(of: #"^\d+"#, options: .regularExpression) else { return nil }
        return Int(t[r])
    }

    public static func toggleTask(_ t: String) -> String {
        if isTaskDone(t) { return "- [ ] " + t.dropFirst(6) }
        if t.hasPrefix("- [ ] ") { return "- [x] " + t.dropFirst(6) }
        return t
    }

    /// What pressing Enter at the end of `line` should put on the next line.
    /// Returns nil when the line is not a list item. `exit` is true for an empty item,
    /// which the prototype turns into a plain empty line instead.
    public static func continuation(for line: String) -> (prefix: String, exit: Bool)? {
        let type = blockType(line)
        guard type.isList else { return nil }
        let pl = prefixLength(line)
        let pre = (line as NSString).substring(to: pl)
        if line == pre { return ("", true) }
        switch type {
        case .task: return ("- [ ] ", false)
        case .ol: return ("\((orderedNumber(line) ?? 0) + 1). ", false)
        default: return (pre, false)
        }
    }

    public static func parseLine(_ t: String) -> LineMarkup {
        let type = blockType(t)
        let ns = t as NSString
        let pl = type == .hr ? 0 : prefixLength(t)
        var markup = LineMarkup(type: type, prefix: NSRange(location: 0, length: pl), spans: [])
        if type == .hr || type == .empty { return markup }

        let body = NSRange(location: pl, length: ns.length - pl)
        var taken: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }

        for m in codeRe.matches(in: t, range: body) {
            taken.append(m.range)
            markup.spans.append(InlineSpan(kind: .code, content: m.range(at: 1),
                                           marks: [NSRange(location: m.range.location, length: 1),
                                                   NSRange(location: NSMaxRange(m.range) - 1, length: 1)]))
        }
        for m in wikiRe.matches(in: t, range: body) where free(m.range) {
            taken.append(m.range)
            let title = ns.substring(with: m.range(at: 1))
            markup.spans.append(InlineSpan(kind: .wikilink(title), content: m.range(at: 1),
                                           marks: [NSRange(location: m.range.location, length: 2),
                                                   NSRange(location: NSMaxRange(m.range) - 2, length: 2)]))
        }
        for m in linkRe.matches(in: t, range: body) where free(m.range) {
            taken.append(m.range)
            let text = m.range(at: 1)
            markup.spans.append(InlineSpan(kind: .link(ns.substring(with: m.range(at: 2))), content: text,
                                           marks: [NSRange(location: m.range.location, length: 1),
                                                   NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text))]))
        }
        var boldRanges: [NSRange] = []
        for m in boldRe.matches(in: t, range: body) where free(m.range) {
            boldRanges.append(m.range)
            markup.spans.append(InlineSpan(kind: .bold, content: m.range(at: 1),
                                           marks: [NSRange(location: m.range.location, length: 2),
                                                   NSRange(location: NSMaxRange(m.range) - 2, length: 2)]))
        }
        taken.append(contentsOf: boldRanges.flatMap { [NSRange(location: $0.location, length: 2), NSRange(location: NSMaxRange($0) - 2, length: 2)] })
        for m in italicRe.matches(in: t, range: body) where free(m.range) {
            markup.spans.append(InlineSpan(kind: .italic, content: m.range(at: 1),
                                           marks: [NSRange(location: m.range.location, length: 1),
                                                   NSRange(location: NSMaxRange(m.range) - 1, length: 1)]))
        }
        return markup
    }

    /// CJK characters count one each, Latin words count one each (prototype's rule).
    public static func countWords(_ lines: [String]) -> Int {
        let text = lines.map { line -> String in
            let pl = prefixLength(line)
            let rest = (line as NSString).substring(from: pl)
            return rest.replacingOccurrences(of: #"[*`\[\]#>]"#, with: "", options: .regularExpression)
        }.joined(separator: " ")
        var cjk = 0
        var latinSource = ""
        latinSource.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                cjk += 1
                latinSource.append(" ")
            } else {
                latinSource.unicodeScalars.append(scalar)
            }
        }
        let latinRe = try! NSRegularExpression(pattern: #"[A-Za-z0-9][A-Za-z0-9.,%]*"#)
        let latin = latinRe.numberOfMatches(in: latinSource, range: NSRange(location: 0, length: (latinSource as NSString).length))
        return cjk + latin
    }

    public static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }
}
