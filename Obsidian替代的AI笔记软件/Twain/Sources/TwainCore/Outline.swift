import Foundation

/// One heading of a note, for the outline beside the page.
public struct OutlineEntry: Equatable, Sendable {
    public let level: Int
    public let title: String
    /// UTF-16 offset of the heading's line in the text.
    public let offset: Int

    public init(level: Int, title: String, offset: Int) {
        self.level = level
        self.title = title
        self.offset = offset
    }
}

extension Markdown {
    /// The note's headings in order. Lines inside fenced code and the front matter are not headings.
    public static func outline(_ text: String) -> [OutlineEntry] {
        var out: [OutlineEntry] = []
        var offset = 0
        var fence: String?
        var inFront = false
        for (i, line) in lines(text).enumerated() {
            defer { offset += line.utf16.count + 1 }
            if i == 0, line == "---" { inFront = true; continue }
            if inFront {
                if line == "---" || line == "..." { inFront = false }
                continue
            }
            if let f = isFence(line) {
                if let open = fence {
                    if f.first == open.first, f.count >= open.count { fence = nil }
                } else {
                    fence = f
                }
                continue
            }
            guard fence == nil, let level = blockType(line).headingLevel else { continue }
            // Notes written on Windows end lines in "\r\n"; the "\r" is not part of the title.
            var title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespacesAndNewlines)
            // A closing run of #s is decoration (`## Title ##`).
            if let r = title.range(of: #"\s+#+$"#, options: .regularExpression) { title.removeSubrange(r) }
            if !title.isEmpty { out.append(OutlineEntry(level: level, title: title, offset: offset)) }
        }
        return out
    }
}
