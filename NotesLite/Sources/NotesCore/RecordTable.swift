import Foundation

/// A record table: a Markdown pipe table whose header names the fields and whose rows are records.
public struct RecordTable: Equatable, Sendable {
    public enum FieldType: String, Codable, Sendable { case number, date, text }

    /// The nearest heading above the table, without its `#` marks.
    public var heading: String?
    public var header: [String]
    public var rows: [[String]]
    /// Line indices of the header row through the last body row.
    public var lines: Range<Int>

    /// Every record table in a note, skipping code blocks and front matter.
    public static func all(in text: String) -> [RecordTable] {
        let lines = Markdown.lines(text)
        let types = Markdown.types(lines)
        var tables: [RecordTable] = []
        var heading: String?
        var i = 0
        while i < lines.count {
            if let level = types[i].headingLevel {
                heading = String(lines[i].dropFirst(level)).trimmingCharacters(in: .whitespaces)
                heading = heading?.replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
                i += 1; continue
            }
            guard types[i] == .table else { i += 1; continue }
            var end = i
            while end < lines.count, types[end] == .table { end += 1 }
            if let table = MarkdownTable.parse(Array(lines[i..<end])) {
                tables.append(RecordTable(heading: heading, header: table.header.map(\.text),
                                          rows: table.rows.map { $0.map(\.text) }, lines: i..<end))
            }
            i = end
        }
        return tables
    }

    /// The table under `heading`, or the note's first table when no heading is given.
    public static func find(in text: String, heading: String?) -> RecordTable? {
        let tables = all(in: text)
        guard let heading, !heading.isEmpty else { return tables.first }
        return tables.first { $0.heading == heading }
    }

    /// Whole column numeric → number, whole column `YYYY-MM-DD` → date, otherwise text. Empty cells don't vote.
    public static func infer(_ column: [String]) -> FieldType {
        let values = column.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !values.isEmpty else { return .text }
        if values.allSatisfy({ number($0) != nil }) { return .number }
        if values.allSatisfy(isDate) { return .date }
        return .text
    }

    public var types: [FieldType] {
        header.indices.map { c in Self.infer(rows.map { c < $0.count ? $0[c] : "" }) }
    }

    static func number(_ value: String) -> Double? {
        let t = value.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.range(of: #"^[-+]?(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Double(t)
    }

    static func isDate(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// One table row; pipes are escaped and line breaks folded so a value can't break the table.
    static func render(_ cells: [String]) -> String {
        "| " + cells.map { $0.replacingOccurrences(of: "\\|", with: "|").replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | ") + " |"
    }

    static func newTable(_ header: [String]) -> [String] {
        [render(header), "|" + header.map { _ in "---" }.joined(separator: "|") + "|"]
    }
}
