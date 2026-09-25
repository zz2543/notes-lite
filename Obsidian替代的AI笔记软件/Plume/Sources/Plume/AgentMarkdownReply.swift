import SwiftUI

/// Displays CLI output as readable Markdown without treating its content as app commands.
struct AgentMarkdownReply: View {
    let source: String

    var body: some View {
        let blocks = Self.blocks(source)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .paragraph(value):
                    inline(value).lineSpacing(3)
                case let .heading(level, value):
                    inline(value)
                        .font(.system(size: level == 1 ? 19 : level == 2 ? 16 : 14,
                                      weight: .semibold))
                        .padding(.top, level <= 2 ? 5 : 2)
                case let .list(marker, value, depth):
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(marker).foregroundStyle(.secondary)
                        inline(value).lineSpacing(2)
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                case let .quote(value):
                    inline(value)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) { Rectangle().fill(.tint).frame(width: 2) }
                case let .code(language, value):
                    VStack(alignment: .leading, spacing: 4) {
                        if !language.isEmpty {
                            Text(language).font(.caption2).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal) {
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                case .rule:
                    Divider().padding(.vertical, 3)
                }
            }
        }
    }

    private func inline(_ value: String) -> some View {
        let formatted = (try? AttributedString(markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
        return Text(formatted).textSelection(.enabled)
    }

    private enum Block {
        case paragraph(String)
        case heading(Int, String)
        case list(String, String, Int)
        case quote(String)
        case code(String, String)
        case rule
    }

    private static func blocks(_ source: String) -> [Block] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [Block] = []
        var paragraph: [String] = []
        var i = 0
        func flush() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); i += 1; continue }

            let fence = trimmed.hasPrefix("```") ? "`" : trimmed.hasPrefix("~~~") ? "~" : ""
            if !fence.isEmpty {
                flush()
                let count = trimmed.prefix(while: { String($0) == fence }).count
                let language = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let end = lines[i].trimmingCharacters(in: .whitespaces)
                    if end.prefix(while: { String($0) == fence }).count >= count,
                       end.drop(while: { String($0) == fence }).trimmingCharacters(in: .whitespaces).isEmpty { break }
                    code.append(lines[i]); i += 1
                }
                result.append(.code(language, code.joined(separator: "\n")))
                i += 1
                continue
            }

            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).hasPrefix(" ") {
                flush()
                result.append(.heading(hashes, String(trimmed.dropFirst(hashes + 1))))
            } else if ["---", "***", "___"].contains(trimmed) {
                flush(); result.append(.rule)
            } else if trimmed.hasPrefix("> ") {
                flush(); result.append(.quote(String(trimmed.dropFirst(2))))
            } else if let item = listItem(line) {
                flush(); result.append(.list(item.marker, item.value, item.depth))
            } else {
                paragraph.append(trimmed)
            }
            i += 1
        }
        flush()
        return result
    }

    private static func listItem(_ line: String) -> (marker: String, value: String, depth: Int)? {
        let indentation = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let value = String(line.dropFirst(indentation))
        if value.count >= 2, ["- ", "+ ", "* "].contains(String(value.prefix(2))) {
            return ("•", String(value.dropFirst(2)), indentation / 2)
        }
        let digits = value.prefix(while: { $0.isNumber })
        let rest = value.dropFirst(digits.count)
        if !digits.isEmpty && (rest.hasPrefix(". ") || rest.hasPrefix(") ")) {
            return (String(digits) + ".", String(rest.dropFirst(2)), indentation / 2)
        }
        return nil
    }
}
