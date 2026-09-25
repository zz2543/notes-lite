import AppKit
import PlumeCore
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Colors from the prototype (oklch values converted to sRGB).
enum Theme {
    static let paper = Color(hex: 0xFDFCFA)
    static let ink = Color(hex: 0x26241F)
    static let sidebar = Color(hex: 0xEFEDEA)
    static let sidebarLine = Color(hex: 0xE2DFDA)
    static let panel = Color(hex: 0xF7F6F3)
    static let panelLine = Color(hex: 0xEBE8E3)
    static let hairline = Color(hex: 0xF0EDE9)
    static let card = Color.white
    static let cardLine = Color(hex: 0xE6E3DE)
    static let chip = Color(hex: 0xF0EDE8)
    static let muted = Color(hex: 0x9D988F)
    static let muted2 = Color(hex: 0x8E897F)
    static let muted3 = Color(hex: 0x6F6B64)
    static let text2 = Color(hex: 0x4A4740)
    static let text3 = Color(hex: 0x5D5953)
    static let icon = Color(hex: 0x77736B)
    static let faint = Color(hex: 0xA5A097)
    static let slash = Color(hex: 0xC9C4BB)

    static let accent = Color(hex: 0x3475C4)
    static let claude = Color(hex: 0xC56A3E)
    static let claudeText = Color(hex: 0x994920)
    static let codex = Color(hex: 0x2D333D)
    static let writingBg = Color(hex: 0xFFF1EA)
    static let writingLine = Color(hex: 0xF7DFD5)
    static let writingText = Color(hex: 0x783818)
    static let delBg = Color(hex: 0xFFE9E6)
    static let delText = Color(hex: 0x963633)
    static let addBg = Color(hex: 0xDEF8E2)
    static let addText = Color(hex: 0x085023)
    static let plus = Color(hex: 0x196632)
    static let minus = Color(hex: 0xA03F3C)
    static let pillBg = Color(hex: 0xDEEDFF)
    static let pillText = Color(hex: 0x17559B)
    static let dark = Color(hex: 0x26241F)
    static let toast = Color(hex: 0x2B2926)

    static func agentColor(_ a: AgentKind) -> Color { a == .claude ? claude : codex }

    enum NS {
        static let ink = NSColor(hex: 0x26241F)
        static let quote = NSColor(hex: 0x5D5953)
        static let mark = NSColor(hex: 0xBDB8B0)
        static let deco = NSColor(hex: 0xA8A39B)
        static let taskBorder = NSColor(hex: 0xC4BFB7)
        static let doneText = NSColor(hex: 0xA39E96)
        static let strike = NSColor(hex: 0xCFCAC2)
        static let quoteBar = NSColor(hex: 0xE3DFD8)
        static let hr = NSColor(hex: 0xE4E0DA)
        static let codeBg = NSColor(hex: 0xF0EEEA)
        static let ghost = NSColor(hex: 0xB3AEA6)
        static let ghostPill = NSColor(hex: 0xDCD8D1)
        static let ghostPillText = NSColor(hex: 0x9A958D)
        static let accent = NSColor(hex: 0x3475C4)
        static let selection = NSColor(hex: 0xB7D4F9)
        static let paper = NSColor(hex: 0xFDFCFA)
    }
}

enum EditorFont: String, CaseIterable, Identifiable {
    case serif, sans, mono
    var id: String { rawValue }

    var shortLabel: String { ["serif": "衬线", "sans": "无衬线", "mono": "等宽"][rawValue]! }
    var cardLabel: String { ["serif": "衬线 · New York", "sans": "无衬线 · SF Pro", "mono": "等宽 · SF Mono"][rawValue]! }
    var next: EditorFont { self == .serif ? .sans : self == .sans ? .mono : .serif }

    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        var base: NSFont
        var cjkFamily: String
        switch self {
        case .serif:
            let sys = NSFont.systemFont(ofSize: size, weight: weight)
            base = sys.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? sys
            cjkFamily = "Songti SC"
        case .sans:
            base = NSFont.systemFont(ofSize: size, weight: weight)
            cjkFamily = "PingFang SC"
        case .mono:
            base = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            cjkFamily = "PingFang SC"
        }
        var desc = base.fontDescriptor
        if italic { desc = desc.withSymbolicTraits(.italic) }
        let cjkWeight: NSFont.Weight = weight.rawValue >= NSFont.Weight.semibold.rawValue ? .bold : .regular
        let cjk = NSFontDescriptor(fontAttributes: [.family: cjkFamily, .traits: [NSFontDescriptor.TraitKey.weight: cjkWeight]])
        desc = desc.addingAttributes([.cascadeList: [cjk]])
        return NSFont(descriptor: desc, size: size) ?? base
    }

    func swiftUIFont(size: CGFloat) -> Font { Font(nsFont(size: size)) }
}
