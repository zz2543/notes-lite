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

/// Line-level edits of one record table that leave the rest of the note as it was.
enum RecordEdit {
    /// Rows as cells in header order, padded to the header's width.
    static func cells(_ record: [String: String], header: [String]) throws -> [String] {
        if let unknown = record.keys.sorted().first(where: { !header.contains($0) }) { throw SpaceAPIError.unknownField(unknown) }
        return header.map { normalized(record[$0] ?? "") }
    }

    /// A value as it reads back from the table: one line, trimmed.
    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    static func padded(_ row: [String], _ count: Int) -> [String] {
        Array((row + Array(repeating: "", count: max(0, count - row.count))).prefix(count))
    }

    /// Appends rows, creating the note, the heading or the table when missing. Returns the new text and the stored cells.
    static func append(_ text: String?, title: String, heading: String?, header fallback: [String], records: [[String: String]]) throws -> (text: String, header: [String], rows: [[String]]) {
        if let text, let table = RecordTable.find(in: text, heading: heading) {
            let rows = try records.map { try cells($0, header: table.header) }
            var lines = Markdown.lines(text)
            lines.insert(contentsOf: rows.map(RecordTable.render), at: table.lines.upperBound)
            return (lines.joined(separator: "\n"), table.header, rows)
        }
        guard !fallback.isEmpty else { throw SpaceAPIError.invalid("记录表不存在，且没有可用来新建的表头。") }
        let rows = try records.map { try cells($0, header: fallback) }
        let block = (RecordTable.newTable(fallback) + rows.map(RecordTable.render)).joined(separator: "\n") + "\n"
        guard var text else {
            return ("# \(title)\n\n" + (heading.map { "## \($0)\n\n" } ?? "") + block, fallback, rows)
        }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += (heading.map { "## \($0)\n\n" } ?? "") + block
        return (text, fallback, rows)
    }

    /// Replaces or deletes body rows; `edit` returns nil to delete a row.
    static func rewrite(_ text: String, table: RecordTable, rows indices: [Int], _ edit: (Int, [String]) -> [String]?) -> String {
        var lines = Markdown.lines(text)
        for index in indices.sorted(by: >) {
            let line = table.lines.lowerBound + 2 + index
            let before = padded(table.rows[index], table.header.count)
            if let after = edit(index, before) { lines[line] = RecordTable.render(after) } else { lines.remove(at: line) }
        }
        return lines.joined(separator: "\n")
    }

    static func insert(_ text: String, table: RecordTable, row: [String], at index: Int) -> String {
        var lines = Markdown.lines(text)
        lines.insert(RecordTable.render(row), at: table.lines.lowerBound + 2 + min(max(0, index), table.rows.count))
        return lines.joined(separator: "\n")
    }
}
