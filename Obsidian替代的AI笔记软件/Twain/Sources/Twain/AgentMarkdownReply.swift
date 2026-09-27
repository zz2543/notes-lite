import AppKit
import SwiftUI

/// An agent's reply as one read-only text view, so a selection can run across paragraphs,
/// lists and code blocks like in any document. CLI output is only ever displayed, never
/// treated as app commands.
struct AgentMarkdownReply: NSViewRepresentable {
    let source: String

    func makeNSView(context: Context) -> NSTextView {
        let tv = ReplyTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand]
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        guard (tv as? ReplyTextView)?.source != source else { return }
        (tv as? ReplyTextView)?.source = source
        tv.textStorage?.setAttributedString(ReplyRenderer.render(source))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: NSTextView, context: Context) -> CGSize? {
        let width = max(40, proposal.width ?? 320)
        guard let tc = tv.textContainer, let lm = tv.layoutManager else { return nil }
        if tc.size.width != width { tc.size = NSSize(width: width, height: .greatestFiniteMagnitude) }
        lm.ensureLayout(for: tc)
        let h = ceil(lm.usedRect(for: tc).height)
        return CGSize(width: width, height: h)
    }
}

private final class ReplyTextView: NSTextView {
    var source: String?
    // Scrolling belongs to the transcript, not to each reply.
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
}

/// Markdown → attributed text for replies: headings, lists, quotes, fenced code, rules,
/// and inline emphasis, code and links. Rendered once per reply text.
enum ReplyRenderer {
    private static let cache = NSCache<NSString, NSAttributedString>()

    static func render(_ source: String) -> NSAttributedString {
        if let hit = cache.object(forKey: source as NSString) { return hit }
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: NSFont.systemFontSize + 0.5)
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var paragraph: [String] = []
        var i = 0
        func para(spacingBefore: CGFloat = 0, after: CGFloat = 7, indent: CGFloat = 0, head: CGFloat? = nil) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = 3
            p.paragraphSpacingBefore = spacingBefore
            p.paragraphSpacing = after
            p.firstLineHeadIndent = indent
            p.headIndent = head ?? indent
            return p
        }
        func append(_ s: NSAttributedString) {
            if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(s)
        }
        func flush() {
            guard !paragraph.isEmpty else { return }
            append(inline(paragraph.joined(separator: " "), font: body, style: para()))
            paragraph.removeAll()
        }
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); i += 1; continue }
            let fence = trimmed.hasPrefix("```") ? "`" : trimmed.hasPrefix("~~~") ? "~" : ""
            if !fence.isEmpty {
                flush()
                let count = trimmed.prefix { String($0) == fence }.count
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let end = lines[i].trimmingCharacters(in: .whitespaces)
                    if end.prefix(while: { String($0) == fence }).count >= count,
                       end.drop(while: { String($0) == fence }).trimmingCharacters(in: .whitespaces).isEmpty { break }
                    code.append(lines[i]); i += 1
                }
                i += 1
                let block = NSTextBlock()
                block.backgroundColor = Theme.NS.codeBlock
                block.setContentWidth(100, type: .percentageValueType)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                block.setWidth(4, type: .absoluteValueType, for: .margin, edge: .minY)
                block.setWidth(8, type: .absoluteValueType, for: .margin, edge: .maxY)
                let p = para(after: 8)
                p.textBlocks = [block]
                p.lineSpacing = 1
                p.lineBreakMode = .byCharWrapping
                // One paragraph (line separators), so the block keeps one box and one spacing.
                append(NSAttributedString(string: code.joined(separator: "\u{2028}"), attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                    .foregroundColor: NSColor.labelColor, .paragraphStyle: p,
                ]))
                continue
            }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).hasPrefix(" ") {
                flush()
                let size: CGFloat = hashes == 1 ? 18 : hashes == 2 ? 15.5 : 14
                append(inline(String(trimmed.dropFirst(hashes + 1)), font: .systemFont(ofSize: size, weight: .semibold),
                              style: para(spacingBefore: 4, after: 5)))
            } else if ["---", "***", "___"].contains(trimmed) {
                flush()
                append(NSAttributedString(string: "\u{00A0}", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                                                             .strikethroughColor: NSColor.separatorColor,
                                                                             .paragraphStyle: para()]))
            } else if trimmed.hasPrefix(">") {
                flush()
                let s = inline(String(trimmed.drop { $0 == ">" || $0 == " " }), font: body, style: para(indent: 12))
                let m = NSMutableAttributedString(attributedString: s)
                m.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 0, length: m.length))
                append(m)
            } else if let item = listItem(line) {
                flush()
                let indent = CGFloat(item.depth) * 14
                let marker = item.marker + "\t"
                let p = para(after: 3, indent: indent, head: indent + 16)
                p.tabStops = [NSTextTab(textAlignment: .left, location: indent + 16)]
                let m = NSMutableAttributedString(string: marker, attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor,
                                                                                .paragraphStyle: p])
                m.append(inline(item.value, font: body, style: p))
                append(m)
            } else {
                paragraph.append(trimmed)
            }
            i += 1
        }
        flush()
        cache.setObject(out, forKey: source as NSString)
        return out
    }

    /// Bold, italic, inline code, strikethrough and links on one run of text.
    static func inline(_ text: String, font: NSFont, style: NSParagraphStyle) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let s = String(parsed[run.range].characters)
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
            if let intent = run.inlinePresentationIntent {
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                if !traits.isEmpty {
                    attrs[.font] = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
                }
                if intent.contains(.code) {
                    attrs[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
                    attrs[.backgroundColor] = Theme.NS.codeBlock
                }
                if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            if let link = run.link { attrs[.link] = link }
            out.append(NSAttributedString(string: s, attributes: attrs))
        }
        return out
    }

    private static func listItem(_ line: String) -> (marker: String, value: String, depth: Int)? {
        let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
        let value = String(line.dropFirst(indentation))
        if value.count >= 2, ["- ", "+ ", "* "].contains(String(value.prefix(2))) {
            var rest = String(value.dropFirst(2))
            if rest.hasPrefix("[ ] ") { return ("☐", String(rest.dropFirst(4)), indentation / 2) }
            if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") { rest.removeFirst(4); return ("☑", rest, indentation / 2) }
            return ("•", rest, indentation / 2)
        }
        let digits = value.prefix { $0.isNumber }
        let rest = value.dropFirst(digits.count)
        if !digits.isEmpty && (rest.hasPrefix(". ") || rest.hasPrefix(") ")) {
            return (String(digits) + ".", String(rest.dropFirst(2)), indentation / 2)
        }
        return nil
    }
}
