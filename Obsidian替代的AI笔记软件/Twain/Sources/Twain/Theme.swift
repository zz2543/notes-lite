import AppKit
import TwainCore
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

/// Layout rules used across the app.
///
/// The system's own bars (window toolbar, sidebar) keep their material. Most of what Twain
/// draws itself — banners, the composer, menus, cards, buttons, toasts — is a quiet solid
/// surface: paper-coloured, a hairline edge, a soft shadow. These shapes are what moves (a
/// button grows into a menu, a card folds to a line), so they should read as objects, not as a
/// lens over what is behind them. Glass is kept for the thin layer that hovers over the page
/// while you keep writing — the status pill, the agent island, the palette — where seeing the
/// text through it is the point. Radii shrink as elements nest.
enum Metrics {
    /// Palette, onboarding artwork: the outermost floating surfaces.
    static let panelRadius: CGFloat = 26
    /// Composer, slash menu, hunk cards.
    static let cardRadius: CGFloat = 18
    /// Rows inside a card or panel (selection highlights, inner fills).
    static let rowRadius: CGFloat = 10
    /// Gap between floating glass and the edge of the area it floats over.
    static let floatInset: CGFloat = 12
}

/// System colors so the app follows light/dark mode and the user's accent color.
enum Theme {
    static let claude = Color(nsColor: NS.claude)
    static let codex = Color(nsColor: NS.codex)

    static func agentColor(_ a: AgentKind) -> Color { a == .claude ? claude : codex }
    static func agentSymbol(_ a: AgentKind) -> String { a == .claude ? "sparkle" : "terminal" }

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

extension View {
    /// A solid surface floating above the page: window-coloured, hairline edge, soft shadow.
    func surface(radius: CGFloat = Metrics.cardRadius, tint: Color? = nil, shadow: Bool = true) -> some View {
        modifier(SurfaceStyle(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, shadow: shadow))
    }

    /// `surface` as a capsule — banners, toasts, status.
    func capsuleSurface(tint: Color? = nil, shadow: Bool = true, hoverLift: Bool = false) -> some View {
        modifier(SurfaceStyle(shape: Capsule(), tint: tint, shadow: shadow, hoverLift: hoverLift))
    }

    /// Glass, for the few shapes that hover over the page while you write (see `Metrics`).
    func hoverGlass(radius: CGFloat = Metrics.cardRadius, tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: radius, style: .continuous))
    }

    /// `hoverGlass` as a capsule.
    func hoverGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(.regular.tint(tint).interactive(interactive), in: .capsule)
    }

    /// A quiet, non-glass container for content that sits on the page.
    func contentCard(radius: CGFloat = Metrics.rowRadius + 4) -> some View {
        background(.fill.quinary, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

/// Selection highlight used by lists drawn inside glass (palette, slash menu).
extension View {
    /// The selection highlight of a list drawn inside glass, sliding from row to row: rows of
    /// one list share `namespace`, and the list animates on its selection (`.motion(…, value:)`).
    func slidingHighlight(_ on: Bool, in namespace: Namespace.ID) -> some View {
        background {
            if on { RowHighlight(on: true).matchedGeometryEffect(id: "highlight", in: namespace) }
        }
    }
}

struct RowHighlight: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
            .fill(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
    }
}

/// Small rounded tag, e.g. the files an agent request will carry.
struct TagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.imageScale(.small); configuration.title }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.fill.tertiary, in: .capsule)
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

/// True while an input method (Pinyin, Kana…) holds uncommitted text in the focused field.
/// Keys pressed then belong to the input method, not to the view's shortcuts.
func imeComposing() -> Bool {
    ((NSApp.currentEvent?.window ?? NSApp.keyWindow)?.firstResponder as? NSTextInputClient)?.hasMarkedText() == true
}

/// The official app icon of each agent, copied from the Claude and Codex apps.
///
/// Looks up the SwiftPM resource bundle by hand: `Bundle.module` only checks beside the
/// executable and the `.app` root, while `scripts/bundle.sh` puts it in Contents/Resources.
struct AgentLogo: View {
    let agent: AgentKind
    @Environment(\.colorScheme) private var scheme

    private static let bundle: Bundle = {
        let name = "Twain_Twain.bundle"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for case let base? in bases {
            if let b = Bundle(url: base.appendingPathComponent(name)) { return b }
        }
        return .main
    }()

    private static func image(_ name: String) -> NSImage? {
        Self.bundle.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    private static let claude = image("agent-claude")
    private static let codex = image("agent-codex")
    private static let codexDark = image("agent-codex-dark")

    var body: some View {
        let img = agent == .claude ? Self.claude : (scheme == .dark ? Self.codexDark : Self.codex)
        if let img {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: Theme.agentSymbol(agent)).foregroundStyle(Theme.agentColor(agent))
        }
    }
}

/// The drawn part of a surface, separate so two views can share it as a matched shape.
struct SurfaceFill<S: InsettableShape>: View {
    let shape: S
    var tint: Color?
    var shadow = true
    /// 0 at rest, 1 lifted under the pointer: the shadow grows as if the surface rose towards you.
    var lift: CGFloat = 0
    /// A panel floating over everything (a grow panel) rather than a shape on the page.
    var raised = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        shape.fill(Color(nsColor: .windowBackgroundColor))
            // In the dark a shadow barely shows: height reads as lightness instead, as on paper
            // under a lamp — a surface a little lighter than the page, a raised panel more so.
            .overlay { if scheme == .dark { shape.fill(.white.opacity(raised ? 0.09 : 0.045)) } }
            .overlay { if let tint { shape.fill(tint) } }
            .overlay { shape.strokeBorder(.separator.opacity(0.7), lineWidth: 0.5) }
            .shadow(color: .black.opacity(shadow ? 0.10 + 0.06 * lift : 0), radius: 10 + 6 * lift, y: 3 + 3 * lift)
    }
}

private struct SurfaceStyle<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let shadow: Bool
    /// A surface you can click rises a little under the pointer.
    var hoverLift = false
    @State private var hover = false

    func body(content: Content) -> some View {
        let up = hoverLift && hover && Motion.style != .minimal
        content
            .background { SurfaceFill(shape: shape, tint: tint, shadow: shadow, lift: up ? 1 : 0) }
            .scaleEffect(up && !Motion.reduce ? 1.015 : 1)
            .onHover { if hoverLift { hover = $0 } }
            .animation(Motion.quick, value: up)
    }
}

/// A quiet capsule button: a faint fill that deepens on hover and presses in a little.
struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        let pad: (CGFloat, CGFloat) = switch size {
        case .mini, .small: (10, 4)
        case .large, .extraLarge: (18, 9)
        default: (13, 6)
        }
        configuration.label
            .font(size == .small || size == .mini ? .caption : .body)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, pad.0).padding(.vertical, pad.1)
            .background(
                prominent ? AnyShapeStyle(Color.accentColor.opacity(hover ? 0.88 : 1))
                          : AnyShapeStyle(.fill.opacity(hover ? 0.9 : 0.6)),
                in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.4)
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = $0 }
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    /// The app's secondary button.
    static var soft: SoftButtonStyle { SoftButtonStyle() }
    /// The app's primary button: accent-filled.
    static var solid: SoftButtonStyle { SoftButtonStyle(prominent: true) }
}
