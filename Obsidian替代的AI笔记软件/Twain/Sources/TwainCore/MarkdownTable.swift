import Foundation

/// A GitHub-style pipe table: a header row, a `|---|:-:|` separator, then body rows.
/// Only tables whose lines start with `|` count, as `Markdown.blockType` reads them.
public struct MarkdownTable: Equatable, Sendable {
    public enum Align: Equatable, Sendable { case left, center, right }

    public struct Cell: Equatable, Sendable {
        /// The cell's Markdown, trimmed, with `\|` unescaped.
        public var text: String
        /// Where the trimmed cell sits in its line (UTF-16), for putting the caret in it.
        public var range: NSRange
    }

    public var header: [Cell]
    public var aligns: [Align]
    public var rows: [[Cell]]

    public var columns: Int { aligns.count }

    public init(header: [Cell], aligns: [Align], rows: [[Cell]]) {
        self.header = header
        self.aligns = aligns
        self.rows = rows
    }

    /// `| --- | :---: | ---: |`, with or without the outer pipes' spaces.
    public static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|"), t.contains("-") else { return false }
        let cells = split(t).map { ($0.text as NSString).trimmingCharacters(in: .whitespaces) }
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { c in
            var body = Substring(c)
            if body.hasPrefix(":") { body = body.dropFirst() }
            if body.hasSuffix(":") { body = body.dropLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    /// The cells of one row. Pipes inside inline code, `[[links|alias]]` or escaped as `\|` don't split.
    public static func cells(_ line: String) -> [Cell] {
        split(line).map { raw in
            let ns = raw.text as NSString
            var a = 0, b = ns.length
            while a < b, ns.character(at: a) == 0x20 || ns.character(at: a) == 0x09 { a += 1 }
            while b > a, ns.character(at: b - 1) == 0x20 || ns.character(at: b - 1) == 0x09 { b -= 1 }
            let text = ns.substring(with: NSRange(location: a, length: b - a)).replacingOccurrences(of: "\\|", with: "|")
            return Cell(text: text, range: NSRange(location: raw.range.location + a, length: b - a))
        }
    }

    private static func split(_ line: String) -> [Cell] {
        let ns = line as NSString
        let n = ns.length
        var i = 0
        while i < n, ns.character(at: i) == 0x20 { i += 1 }
        guard i < n, ns.character(at: i) == 0x7C else { return [] }
        i += 1
        var out: [Cell] = []
        var start = i
        var code = false, wiki = 0
        while i < n {
            let c = ns.character(at: i)
            if c == 0x5C, i + 1 < n { i += 2; continue }                       // \x
            if c == 0x60 { code.toggle() }                                     // `
            else if !code, c == 0x5B, i + 1 < n, ns.character(at: i + 1) == 0x5B { wiki += 1; i += 2; continue }
            else if !code, wiki > 0, c == 0x5D, i + 1 < n, ns.character(at: i + 1) == 0x5D { wiki -= 1; i += 2; continue }
            else if c == 0x7C, !code, wiki == 0 {
                let r = NSRange(location: start, length: i - start)
                out.append(Cell(text: ns.substring(with: r), range: r))
                start = i + 1
            }
            i += 1
        }
        // A trailing cell only counts when the row doesn't end with a pipe.
        let rest = NSRange(location: start, length: n - start)
        if !ns.substring(with: rest).trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(Cell(text: ns.substring(with: rest), range: rest))
        }
        return out
    }

    /// Parses `lines` (header, separator, rows). Nil when the second line isn't a separator.
    public static func parse(_ lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2, isSeparator(lines[1]) else { return nil }
        let header = cells(lines[0])
        let aligns: [Align] = cells(lines[1]).map { c in
            let t = c.text
            if t.hasPrefix(":") && t.hasSuffix(":") && t.count > 1 { return .center }
            if t.hasSuffix(":") { return .right }
            return .left
        }
        let cols = max(header.count, aligns.count)
        guard cols > 0 else { return nil }
        func pad(_ row: [Cell]) -> [Cell] {
            var r = Array(row.prefix(cols))
            while r.count < cols { r.append(Cell(text: "", range: NSRange(location: NSNotFound, length: 0))) }
            return r
        }
        var a = Array(aligns.prefix(cols))
        while a.count < cols { a.append(.left) }
        return MarkdownTable(header: pad(header), aligns: a, rows: lines.dropFirst(2).map { pad(cells($0)) })
    }
}
