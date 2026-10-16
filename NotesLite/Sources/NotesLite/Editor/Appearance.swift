import AppKit
import NotesCore
import SwiftUI
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
enum Theme {
    enum NS {
        static var ink: NSColor { .textColor }
        static var quote: NSColor { .secondaryLabelColor }
        static var mark: NSColor { .tertiaryLabelColor }
        static var deco: NSColor { .secondaryLabelColor }
        static var taskBorder: NSColor { .tertiaryLabelColor }
        static var doneText: NSColor { .secondaryLabelColor }
        static var strike: NSColor { .tertiaryLabelColor }
        static var quoteBar: NSColor { .quaternaryLabelColor }
        static var hr: NSColor { .separatorColor }
        static var codeBg: NSColor { .quaternarySystemFill }
        static var ghost: NSColor { .placeholderTextColor }
        static var ghostPill: NSColor { .separatorColor }
        static var ghostPillText: NSColor { .tertiaryLabelColor }
        static var accent: NSColor { .controlAccentColor }
        static var paper: NSColor { .textBackgroundColor }
        static let codeBlock = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.04) }
        static var highlight: NSColor { .systemYellow }
        static var tag: NSColor { .systemPurple }
        static var tableLine: NSColor { .separatorColor }
        static let tableHeader = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.045) }
        static let tableStripe = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.025) : NSColor(white: 0, alpha: 0.018) }

        /// Code colours, after Xcode's default themes.
        private static func pair(_ light: UInt32, _ dark: UInt32) -> NSColor {
            NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light) }
        }
        static let codeKeyword = pair(0x9B2393, 0xFF7AB2)
        static let codeString = pair(0xC41A16, 0xFF8170)
        static let codeComment = pair(0x707F8C, 0x7F8C98)
        static let codeNumber = pair(0x1C00CF, 0xD9C97C)
        static let codeType = pair(0x0B4F79, 0x5DD8FF)
        static let codeLiteral = pair(0x9B2393, 0xFF7AB2)
        static let codeTag = pair(0x0B4F79, 0x5DD8FF)
        static let codeAttribute = pair(0x815F03, 0xFD8F3F)

        static func code(_ t: CodeHighlight.Token) -> NSColor {
            switch t {
            case .keyword: codeKeyword
            case .string: codeString
            case .comment: codeComment
            case .number: codeNumber
            case .type: codeType
            case .literal: codeLiteral
            case .tag: codeTag
            case .attribute: codeAttribute
            }
        }
    }
}

enum EditorFont: String, CaseIterable, Identifiable {
    case serif, sans, mono
    var id: String { rawValue }

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

