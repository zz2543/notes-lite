import AppKit
import NotesCore

/// `![[另一篇笔记]]` or `![[笔记#小节]]`: the other note's text, typeset by a second styler and
/// layout manager and drawn in a card where the link is. Read-only; a double click opens it.
final class NoteEmbed {
    static let header: CGFloat = 30
    static let pad: CGFloat = 14
    static let maxBody: CGFloat = 560

    let rel: String
    let title: String
    let section: String?
    private let storage = NSTextStorage()
    private let lm = NotesLayoutManager()
    private let container: NSTextContainer
    private let styler: MarkdownStyler
    private(set) var height: CGFloat = 80
    private(set) var clipped = false
    /// Called when a picture inside finished and the card changed size.
    var changed: () -> Void = {}

    init(rel: String, title: String, section: String?, text: String, style: EditorStyle, width: CGFloat, dark: Bool,
         resolveEmbed: @escaping (String) -> URL?) {
        self.rel = rel
        self.title = title
        self.section = section
        var s = style
        s.dim = false
        s.typewriter = false
        s.rail = 0
        styler = MarkdownStyler(style: s)
        styler.depth = 1
        styler.dark = dark
        styler.resolveEmbed = resolveEmbed
        container = NSTextContainer(size: NSSize(width: max(120, width - 2 * Self.pad + 2 * MarkdownStyler.gutter), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        lm.addTextContainer(container)
        storage.addLayoutManager(lm)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: Self.excerpt(text, section: section))
        styler.setContainerWidth(container.size.width)
        styler.needsRestyle = { [weak self] in
            guard let self else { return }
            self.restyle()
            self.changed()
        }
        restyle()
    }

    private func restyle() {
        while true {
            let ranges = styler.restyle(storage, caret: nil, force: true)
            for r in ranges {
                lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
                lm.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil)
            }
            if !styler.pending { break }
        }
        lm.ensureLayout(for: container)
        let used = lm.usedRect(for: container).height
        clipped = used > Self.maxBody
        height = Self.header + min(used, Self.maxBody) + Self.pad
    }

    /// The note's text, or one section of it (the heading line and everything under it).
    static func excerpt(_ text: String, section: String?) -> String {
        var lines = Markdown.lines(text)
        // Front matter is metadata, not content.
        if lines.first == "---", let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) {
            lines.removeSubrange(0...end)
        }
        guard let section, !section.isEmpty else {
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let want = section.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased()
        let types = Markdown.types(lines)
        func heading(_ i: Int) -> (level: Int, text: String)? {
            guard let level = types[i].headingLevel else { return nil }
            return (level, lines[i].drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
        }
        guard let start = lines.indices.first(where: { heading($0)?.text.lowercased() == want })
                ?? lines.indices.first(where: { heading($0)?.text.lowercased().contains(want) == true }),
              let level = heading(start)?.level else {
            return "找不到小节：\(section)"
        }
        let end = lines.indices.first { $0 > start && (heading($0)?.level ?? 99) <= level } ?? lines.count
        return lines[start..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func draw(in rect: CGRect) {
        let card = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        Theme.NS.codeBlock.setFill()
        card.fill()
        Theme.NS.accent.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height), xRadius: 1.5, yRadius: 1.5).fill()
        // Header: the note's name (and section), with a hint on how to open it.
        let icon = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        let name = section.map { "\(title) › \($0)" } ?? title
        let label = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: Theme.NS.quote])
        var x = rect.minX + Self.pad
        if let icon {
            let tinted = icon.tinted(Theme.NS.quote)
            tinted.draw(in: CGRect(x: x, y: rect.minY + 9, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += 20
        }
        label.draw(with: CGRect(x: x, y: rect.minY + 8, width: rect.width - x + rect.minX - 90, height: 18), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        let hint = NSAttributedString(string: "双击打开", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.NS.mark])
        hint.draw(at: NSPoint(x: rect.maxX - Self.pad - hint.size().width, y: rect.minY + 9))

        // Body: the other text system, clipped to the card.
        let body = CGRect(x: rect.minX, y: rect.minY + Self.header, width: rect.width, height: rect.height - Self.header - Self.pad / 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: body).addClip()
        let origin = NSPoint(x: rect.minX + Self.pad - MarkdownStyler.gutter, y: body.minY)
        let glyphs = lm.glyphRange(for: container)
        lm.drawBackground(forGlyphRange: glyphs, at: origin)
        lm.drawGlyphs(forGlyphRange: glyphs, at: origin)
        NSGraphicsContext.restoreGraphicsState()
        if clipped {
            // Fade the cut-off end into the card.
            let fade = CGRect(x: rect.minX + 3, y: rect.maxY - 44, width: rect.width - 3, height: 36)
            NSGradient(starting: Theme.NS.paper.withAlphaComponent(0), ending: Theme.NS.paper.withAlphaComponent(0.9))?.draw(in: fade, angle: 90)
        }
    }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { r in
            self.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
        return img
    }
}

/// Embedded notes by content and width, so restyling the host line is free.
final class NoteEmbedCache {
    static let shared = NoteEmbedCache()
    private var cache: [String: NoteEmbed] = [:]
    private var order: [String] = []

    func embed(rel: String, title: String, section: String?, text: String, style: EditorStyle, width: CGFloat, dark: Bool,
               resolveEmbed: @escaping (String) -> URL?, changed: @escaping () -> Void) -> NoteEmbed {
        let key = "\(rel)#\(section ?? "")|\(text.hashValue)|\(Int(width))|\(style.font.rawValue)|\(dark)"
        if let e = cache[key] { e.changed = changed; return e }
        let e = NoteEmbed(rel: rel, title: title, section: section, text: text, style: style, width: width, dark: dark, resolveEmbed: resolveEmbed)
        e.changed = changed
        cache[key] = e
        order.append(key)
        if order.count > 40 { cache[order.removeFirst()] = nil }
        return e
    }
}
