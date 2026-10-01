import AppKit
import SwiftUI

/// One character that animates while an agent works. Each activity has its own braille
/// pattern, so a glance tells thinking from searching, reading, writing or running a command,
/// and it fits inside a line of text where a spinner would push the words apart.
/// All spinners on screen step on the same clock and move in time with each other.
struct GlyphSpinner: View {
    enum Activity {
        case think, search, read, write, run

        /// The activity a step's description names (“读取 …”, “写入 …”, “$ …”).
        init(step: String) {
            if step.hasPrefix("读取") { self = .read }
            else if step.hasPrefix("写入") { self = .write }
            else if step.hasPrefix("搜索") || step.hasPrefix("查找") || step.hasPrefix("网页搜索") { self = .search }
            else if step.hasPrefix("$") { self = .run }
            else { self = .think }
        }

        var frames: [Character] {
            switch self {
            case .think: Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
            case .search: Array("⣾⣽⣻⢿⡿⣟⣯⣷")
            case .read: Array("⠁⠂⠄⡀⢀⠠⠐⠈")
            case .write: Array("⣀⣄⣤⣦⣶⣷⣿⣷⣶⣦⣤⣄")
            case .run: Array("⠋⠙⠚⠞⠖⠦⠴⠲⠳⠓")
            }
        }

        /// What the agent is doing, for a status line.
        var verb: String {
            switch self {
            case .think: "正在思考"
            case .search: "正在搜索"
            case .read: "正在读取"
            case .write: "正在写入"
            case .run: "正在运行命令"
            }
        }
    }

    var activity: Activity = .think
    var tint: Color = .accentColor

    var body: some View {
        Group {
            if Motion.ambient {
                // The frames step in Core Animation, not in SwiftUI: a Text changing ten times a
                // second made the whole window lay out again on every tick (~17% CPU with three
                // spinners in the Agent panel).
                LayerGlyphs(frames: activity.frames, tint: NSColor(tint))
            } else {
                Text("•")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 16, height: 14)
        .accessibilityElement()
        .accessibilityLabel(activity.verb)
    }
}

/// The spinner's frames drawn once into images that a layer cycles through on its own.
private struct LayerGlyphs: NSViewRepresentable {
    let frames: [Character]
    let tint: NSColor

    func makeNSView(context: Context) -> GlyphLayerView { GlyphLayerView() }
    func updateNSView(_ view: GlyphLayerView, context: Context) { view.configure(frames: frames, tint: tint) }
}

final class GlyphLayerView: NSView {
    static let step = 0.09
    private var frames: [Character] = []
    private var tint: NSColor = .controlAccentColor
    /// Rendered frames by glyphs, colour and scale; spinners of one kind share them.
    @MainActor private static var cache: [String: [CGImage]] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .center
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 14) }

    func configure(frames: [Character], tint: NSColor) {
        guard frames != self.frames || tint != self.tint else { return }
        self.frames = frames
        self.tint = tint
        restart()
    }

    override func viewDidMoveToWindow() { restart() }
    override func viewDidChangeBackingProperties() { restart() }
    override func viewDidChangeEffectiveAppearance() { restart() }

    private func restart() {
        guard let layer, let window, !frames.isEmpty else { return }
        let scale = window.backingScaleFactor
        var images: [CGImage] = []
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = tint.usingColorSpace(.sRGB) ?? tint
            let key = "\(String(frames))|\(color.redComponent),\(color.greenComponent),\(color.blueComponent),\(color.alphaComponent)|\(scale)"
            if let hit = Self.cache[key] { images = hit; return }
            images = frames.compactMap { Self.render($0, color: color, scale: scale) }
            if Self.cache.count > 64 { Self.cache.removeAll() }
            Self.cache[key] = images
        }
        guard !images.isEmpty else { return }
        layer.contentsScale = scale
        layer.contents = images[0]
        layer.removeAnimation(forKey: "glyphs")
        let period = Self.step * Double(images.count)
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = images
        a.calculationMode = .discrete
        a.duration = period
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        // One clock for all spinners: each starts at the frame the others are on.
        let now = CACurrentMediaTime()
        a.beginTime = layer.convertTime(now - now.truncatingRemainder(dividingBy: period), from: nil)
        layer.add(a, forKey: "glyphs")
    }

    private static func render(_ glyph: Character, color: NSColor, scale: CGFloat) -> CGImage? {
        let size = CGSize(width: 20, height: 22)
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let font = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        func line(_ c: Character) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: String(c), attributes: [.font: font, .foregroundColor: color]))
        }
        // Centred on the full braille cell, the same for every frame, so the dots don't hop
        // as the pattern changes and the cell sits on the middle of the line beside it.
        let cell = CTLineGetBoundsWithOptions(line("⣿"), .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: (size.width - cell.width) / 2 - cell.minX, y: size.height / 2 - cell.midY)
        CTLineDraw(line(glyph), ctx)
        return ctx.makeImage()
    }
}

/// A capsule whose motion runs in Core Animation — for things that move for as long as they
/// last (a step running, a step waiting), where a SwiftUI animation would rebuild the view
/// every frame for minutes.
struct LayerCapsule: NSViewRepresentable {
    enum Motion { case none, pulse, breathe }
    let color: NSColor
    var motion: Motion = .none

    func makeNSView(context: Context) -> CapsuleLayerView { CapsuleLayerView() }
    func updateNSView(_ view: CapsuleLayerView, context: Context) { view.configure(color: color, motion: motion) }
}

final class CapsuleLayerView: NSView {
    private var color: NSColor = .clear
    private var motion: LayerCapsule.Motion = .none
    /// A sublayer, so AppKit, which owns the view's own layer geometry, leaves its anchor alone.
    private let fill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(color: NSColor, motion: LayerCapsule.Motion) {
        guard color != self.color || motion != self.motion else { return }
        self.color = color
        self.motion = motion
        restart()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.bounds = CGRect(origin: .zero, size: bounds.size)
        fill.position = CGPoint(x: 0, y: bounds.midY)
        fill.cornerRadius = bounds.height / 2
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() { restart() }
    override func viewDidChangeEffectiveAppearance() { restart() }

    private func restart() {
        guard window != nil else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance { fill.backgroundColor = color.cgColor }
        fill.removeAllAnimations()
        let a: CABasicAnimation
        switch motion {
        case .none: return
        case .pulse:
            // Held still and breathing: waiting for you.
            a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1.0
            a.toValue = 0.45
            a.duration = 0.9
        case .breathe:
            // Filling and draining from the leading edge: working, for an unknown while.
            a = CABasicAnimation(keyPath: "transform.scale.x")
            a.fromValue = 0.25
            a.toValue = 0.9
            a.duration = 1.1
        }
        a.autoreverses = true
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fill.add(a, forKey: "motion")
    }
}

/// Text that rolls to its new value: the old line leaves upwards while the new one rises in
/// from below, so a changing status reads as one line updating rather than a flicker.
struct RollingText: View {
    let text: String
    var animation: Animation? = Motion.quick

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .lineLimit(1)
                .id(text)
                .transition(.push(from: .bottom).combined(with: .opacity))
        }
        .clipped()
        .motion(animation, value: text)
    }
}

/// A placeholder that cycles through example requests while the field is empty — the
/// rotating hints tell a new user what they can ask. Under 简洁 it shows the first one only.
struct RotatingPrompt: View {
    let prompts: [String]
    var period: Double = 4.5

    var body: some View {
        if Motion.ambient, prompts.count > 1 {
            TimelineView(.periodic(from: .now, by: period)) { ctx in
                RollingText(text: prompts[Int(ctx.date.timeIntervalSinceReferenceDate / period) % prompts.count],
                            animation: Motion.content)
            }
        } else {
            Text(prompts.first ?? "").lineLimit(1)
        }
    }
}

/// Things that appear together arrive one after another, each rising a few points into place.
/// The first frame already shows them at rest under 简洁 and Reduce motion.
private struct Arrive: ViewModifier {
    let index: Int
    @State private var shown: Bool

    init(index: Int) {
        self.index = index
        _shown = State(initialValue: !Motion.ambient)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.stagger(index, Motion.content)) { shown = true }
            }
    }
}

extension View {
    /// Arrive as the `index`th of a group that appears together (see `Arrive`).
    /// Not for rows of a lazy list: those appear again on every scroll.
    func arrive(_ index: Int) -> some View { modifier(Arrive(index: index)) }
}

/// A button that answers in place: after it is pressed its label turns into "已…" with a
/// check for a moment and then back, so the result shows where the eye already is.
struct ConfirmButton: View {
    let title: String
    let done: String
    let action: () -> Void
    @State private var confirmed = false
    @State private var reset: DispatchWorkItem?

    var body: some View {
        Button {
            action()
            Motion.feedback(.done)
            withMotion(Motion.morph) { confirmed = true }
            reset?.cancel()
            let w = DispatchWorkItem { withMotion(Motion.morph) { confirmed = false } }
            reset = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
        } label: {
            ZStack {
                if confirmed {
                    Label(done, systemImage: "checkmark").transition(.blurReplace)
                } else {
                    Text(title).transition(.blurReplace)
                }
            }
        }
    }
}
