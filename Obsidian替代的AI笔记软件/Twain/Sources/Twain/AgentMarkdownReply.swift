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
        // The frame SwiftUI gives the view decides the wrap width; sizing never touches this view.
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.size = NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand]
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        guard (tv as? ReplyTextView)?.source != source else { return }
        (tv as? ReplyTextView)?.source = source
        let text = ReplyRenderer.render(source)
        tv.textStorage?.setAttributedString(text)
        context.coordinator.measure.setText(text)
    }

    func makeCoordinator() -> Measure.Holder { Measure.Holder() }

    /// Measured on a separate layout stack. Laying out the displayed view here would change its
    /// size mid-measurement, SwiftUI would measure again at another width, and at some window
    /// widths that never settles: AppKit aborts after too many constraint passes.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: NSTextView, context: Context) -> CGSize? {
        let m = context.coordinator.measure
        if m.source != source { m.setText(ReplyRenderer.render(source)); m.source = source }
        guard let w = proposal.width, w.isFinite else {
            // Unbounded or unspecified: the text's natural width, capped like a reading column.
            let natural = min(ceil(m.naturalWidth()), 520)
            return CGSize(width: max(40, natural), height: m.height(for: max(40, natural)))
        }
        let width = max(40, w)
        return CGSize(width: width, height: m.height(for: width))
    }
}

/// A private text stack for measuring a reply at any width, with the answers cached.
final class Measure {
    final class Holder { let measure = Measure() }

    var source: String?
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
    private var heights: [CGFloat: CGFloat] = [:]
    private var natural: CGFloat?

    init() {
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
    }

    func setText(_ text: NSAttributedString) {
        storage.setAttributedString(text)
        heights = [:]
        natural = nil
    }

    func height(for width: CGFloat) -> CGFloat {
        let key = width.rounded()
        if let h = heights[key] { return h }
        container.size = NSSize(width: key, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let h = ceil(layout.usedRect(for: container).height)
        heights[key] = h
        return h
    }

    func naturalWidth() -> CGFloat {
        if let n = natural { return n }
        container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let n = layout.usedRect(for: container).width
        natural = n
        return n
    }
}

private final class ReplyTextView: NSTextView {
    var source: String?
    // Scrolling belongs to the transcript, not to each reply.
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    // Its size comes from sizeThatFits alone; an intrinsic size would ask SwiftUI to lay out again.
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
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
