import Foundation

/// List summaries show prose, rather than Markdown delimiters and attachment paths.
enum NotePreview {
    static func text(_ body: String) -> String {
        let lines = Markdown.lines(String(body.prefix(8192)))
        let types = Markdown.types(lines)
        var parts: [String] = []
        for (line, type) in zip(lines, types) {
            guard !type.isLiteral, !type.isHeading, type != .empty, type != .hr, type != .table else { continue }
            let markup = Markdown.parseLine(line)
            guard markup.blockEmbed == nil else { continue }
            let result = NSMutableString(string: line)
            for range in markup.allMarks.sorted(by: { $0.location > $1.location }) where NSMaxRange(range) <= result.length {
                result.deleteCharacters(in: range)
            }
            let clean = (result as String).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { parts.append(clean) }
            if parts.joined(separator: " ").count >= 100 { break }
        }
        return String(parts.joined(separator: " ").prefix(110))
    }
}
