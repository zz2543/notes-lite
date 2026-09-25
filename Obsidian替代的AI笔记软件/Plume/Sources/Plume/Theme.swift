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

extension View {
    /// Glass belongs to navigation and controls; content surfaces stay readable.
    @ViewBuilder
    func plumeControlGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func plumeGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func plumePrimaryButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

struct PlumeGlassControls<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

/// System colors so the app follows light/dark mode and the user's accent color.
enum Theme {
    static let claude = Color(nsColor: NS.claude)
    static let codex = Color(nsColor: NS.codex)

    static func agentColor(_ a: AgentKind) -> Color { a == .claude ? claude : codex }

    enum NS {
        static let claude = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) == .darkAqua ? NSColor(hex: 0xE08A62) : NSColor(hex: 0xC56A3E) }
        static let codex = NSColor.labelColor
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
