import AppKit

/// Fonts for one editor style, cached, with a CJK face for each Latin one.
///
/// Chinese text must not reach its font through a cascade list: when CoreText falls back from
/// New York or SF to Songti/PingFang it re-spaces CJK punctuation (measured: "，" 25pt wide at
/// 17pt, "）" 3pt), which reads as huge gaps after commas and brackets overlapping each other.
/// Setting the CJK font on the characters themselves keeps every full-width mark 1em wide.
final class Typography {
    let family: EditorFont
    let bodySize: CGFloat

    private struct Key: Hashable { let size: CGFloat; let weight: CGFloat; let italic: Bool; let mono: Bool }
    private var latin: [Key: NSFont] = [:]
    private var cjk: [Key: NSFont] = [:]
    private var cjkByFont: [String: NSFont] = [:]

    init(_ family: EditorFont) {
        self.family = family
        bodySize = family == .mono ? 15.5 : 17
    }

    var body: NSFont { font(size: bodySize) }

    func font(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        let k = Key(size: size, weight: weight.rawValue, italic: italic, mono: false)
        if let f = latin[k] { return f }
        let f = family.nsFont(size: size, weight: weight, italic: italic)
        latin[k] = f
        cjk[k] = cjkFont(family: family.cjkFamily, size: size, weight: weight)
        cjkByFont[Self.key(f)] = cjk[k]
        return f
    }

    func mono(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let k = Key(size: size, weight: weight.rawValue, italic: false, mono: true)
        if let f = latin[k] { return f }
        let f = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        latin[k] = f
        cjkByFont[Self.key(f)] = cjkFont(family: "PingFang SC", size: size, weight: weight)
        return f
    }

    /// The CJK face that goes with a font this object handed out; nil for foreign fonts.
    func cjk(for f: NSFont) -> NSFont? { cjkByFont[Self.key(f)] }

    private static func key(_ f: NSFont) -> String { f.fontName + "|" + String(Double(f.pointSize)) }

    private func cjkFont(family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let bold = weight.rawValue >= NSFont.Weight.semibold.rawValue
        let d = NSFontDescriptor(fontAttributes: [.family: family])
            .withSymbolicTraits(bold ? .bold : [])
        return NSFont(descriptor: d, size: size) ?? NSFont(name: "PingFangSC-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    // MARK: CJK runs

    static func isCJK(_ u: unichar) -> Bool {
        switch u {
        case 0x2E80...0x2FFF, 0x3000...0x303F, 0x3040...0x30FF, 0x3100...0x31FF, 0x3200...0x33FF,
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFE10...0xFE1F, 0xFE30...0xFE4F,
             0xFF00...0xFFEF, 0xD840...0xD87F:
            return true
        default:
            return false
        }
    }

    /// Punctuation Chinese text shares with Latin: set in the CJK face when it sits next to CJK.
    static func isShared(_ u: unichar) -> Bool {
        u == 0x201C || u == 0x201D || u == 0x2018 || u == 0x2019 || u == 0x2026 || u == 0x2014 || u == 0x00B7
    }

    /// Gives every run of CJK characters in `range` the CJK face of the font it has now.
    func applyCJK(_ storage: NSTextStorage, in range: NSRange) {
        guard range.length > 0 else { return }
        let ns = storage.string as NSString
        var chars = [unichar](repeating: 0, count: range.length)
        ns.getCharacters(&chars, range: range)
        func cjkAt(_ i: Int) -> Bool {
            let u = chars[i]
            if Self.isCJK(u) { return true }
            // Low surrogate of an extension-B ideograph.
            if (0xDC00...0xDFFF).contains(u), i > 0, (0xD840...0xD87F).contains(chars[i - 1]) { return true }
            guard Self.isShared(u) else { return false }
            // Look past neighbouring shared marks ("……", "——") to the nearest real character.
            var p = i - 1
            while p >= 0, Self.isShared(chars[p]) { p -= 1 }
            var n = i + 1
            while n < chars.count, Self.isShared(chars[n]) { n += 1 }
            return (p >= 0 && Self.isCJK(chars[p])) || (n < chars.count && Self.isCJK(chars[n]))
        }
        var i = 0
        while i < chars.count {
            guard cjkAt(i) else { i += 1; continue }
            var j = i + 1
            while j < chars.count, cjkAt(j) { j += 1 }
            let run = NSRange(location: range.location + i, length: j - i)
            storage.enumerateAttribute(.font, in: run) { value, r, _ in
                if let f = value as? NSFont, let c = cjk(for: f) { storage.addAttribute(.font, value: c, range: r) }
            }
            i = j
        }
    }
}

extension EditorFont {
    var cjkFamily: String { self == .serif ? "Songti SC" : "PingFang SC" }
}
