import AppKit
import SwiftUI

/// What the agent of the open conversation is doing, as the orb shows it.
enum OrbState: Equatable {
    case idle, think, search, read, write, run, wait, error

    var label: String {
        switch self {
        case .idle: "待命"
        case .think: "正在思考"
        case .search: "正在搜索"
        case .read: "正在读取"
        case .write: "正在写入"
        case .run: "正在运行命令"
        case .wait: "轮到你了"
        case .error: "出错了"
        }
    }

    /// From a conversation: a question it asked or a pipeline gate waiting for you comes first,
    /// then what its running step is doing, then how its last run ended.
    @MainActor static func of(_ s: AgentSession?, in model: AppModel) -> OrbState {
        guard let s else { return .idle }
        for item in s.items.reversed() {
            switch item.kind {
            case let .question(id) where model.agents.questions[id]?.answer == nil: return .wait
            case let .pipeline(id):
                if let st = model.agents.pipelineRuns[id]?.status, st == .waitingUser || st == .waitingReview { return .wait }
            default: break
            }
        }
        if s.running {
            return switch AgentInspector.activity(s) {
            case .think: .think
            case .search: .search
            case .read: .read
            case .write: .write
            case .run: .run
            }
        }
        if case .error = s.items.last?.kind { return .error }
        return .idle
    }
}

/// One dotted sphere that changes how it moves instead of swapping icons: at rest it is a small
/// filled dot; thinking, a slow shimmer turns across it; reading, a band sweeps up and down;
/// writing, bright arcs spin round; when it waits for you a ring breathes around it; an error
/// turns it red and still.
///
/// Each state's motion is a seamless loop, drawn once in the background into a strip of frames
/// that Core Animation then plays by itself: while the orb turns, the app does no work per frame.
struct AgentOrb: NSViewRepresentable {
    let state: OrbState
    let tint: NSColor

    func makeNSView(context: Context) -> OrbView { OrbView() }
    func updateNSView(_ view: OrbView, context: Context) { view.set(state: state, tint: tint) }
}

final class OrbView: NSView {
    private var state: OrbState = .idle
    private var tint: NSColor = .controlAccentColor
    /// Bumped on every change, so a strip finished for an older state is dropped.
    private var generation = 0
    @MainActor private static var cache: [String: [CGImage]] = [:]
    private static let queue = DispatchQueue(label: "twain.orb", qos: .userInitiated)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}

    func set(state: OrbState, tint: NSColor) {
        guard state != self.state || tint != self.tint else { return }
        let from = self.state
        self.state = state
        self.tint = tint
        apply(from: from)
    }

    override func viewDidMoveToWindow() { if window != nil { apply(from: state) } }
    override func viewDidChangeBackingProperties() { apply(from: state) }
    override func viewDidChangeEffectiveAppearance() { apply(from: state) }

    private func apply(from old: OrbState) {
        guard let layer, let window else { return }
        generation += 1
        let gen = generation
        let moving = Motion.style != .minimal && !Motion.reduce
        var spec = OrbSpec(state: state, still: !moving, lively: Motion.style == .lively,
                           scale: window.backingScaleFactor, side: 26, ink: .clear, accent: .clear, danger: .clear)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            spec.ink = NSColor.tertiaryLabelColor.cgColor
            spec.accent = tint.cgColor
            spec.danger = NSColor.systemRed.cgColor
        }
        // A change of state cross-fades; leaving or reaching rest also grows or gathers the sphere.
        if old != state, moving {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.25
            layer.add(fade, forKey: "fade")
            if (old == .idle) != (state == .idle) {
                let grow = CASpringAnimation(keyPath: "transform.scale")
                grow.fromValue = state == .idle ? 1.3 : 0.5
                grow.toValue = 1
                grow.damping = Motion.style == .lively ? 9 : 16
                grow.stiffness = 180
                grow.duration = grow.settlingDuration
                layer.add(grow, forKey: "grow")
            }
        }
        if let frames = Self.cache[spec.key] {
            play(frames, spec)
            return
        }
        // The first frame now, the loop as soon as it is drawn.
        layer.removeAnimation(forKey: "loop")
        let first = spec.frame(0)
        layer.contents = first
        guard spec.frameCount > 1 else {
            if let first { Self.cache[spec.key] = [first] }
            return
        }
        Self.queue.async {
            let frames = (0..<spec.frameCount).compactMap { spec.frame($0) }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    // A strip is up to ~3 MB (the slow waiting loop); a handful covers the states in use.
                    if Self.cache.count >= 6 { Self.cache.removeAll() }
                    Self.cache[spec.key] = frames
                    guard let self, self.generation == gen else { return }
                    self.play(frames, spec)
                }
            }
        }
    }

    private func play(_ frames: [CGImage], _ spec: OrbSpec) {
        guard let layer else { return }
        layer.contentsScale = spec.scale
        layer.removeAnimation(forKey: "loop")
        layer.contents = frames.first
        guard frames.count > 1 else { return }
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = frames
        a.calculationMode = .discrete
        a.duration = spec.loop
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        let now = CACurrentMediaTime()
        a.beginTime = layer.convertTime(now - now.truncatingRemainder(dividingBy: spec.loop), from: nil)
        layer.add(a, forKey: "loop")
    }
}

/// Everything one strip of orb frames depends on, and how to draw any frame of it. Pure, so the
/// strip can be drawn off the main thread.
private struct OrbSpec: @unchecked Sendable {
    let state: OrbState
    let still: Bool
    let lively: Bool
    let scale: CGFloat
    let side: CGFloat
    var ink: CGColor
    var accent: CGColor
    var danger: CGColor

    static let fps = 24.0
    static let points: [SIMD3<Double>] = {
        let n = 150
        return (0..<n).map { i in
            let y = 1 - Double(i) / Double(n - 1) * 2
            let r = (1 - y * y).squareRoot()
            let th = Double(i) * 2.399963
            return SIMD3(cos(th) * r, y, sin(th) * r)
        }
    }()

    var key: String {
        func c(_ x: CGColor) -> String { (x.components ?? []).map { String(format: "%.3f", $0) }.joined(separator: ",") }
        return "\(state)|\(still)|\(lively)|\(scale)|\(c(ink))|\(c(accent))"
    }

    /// Seconds per loop: the sphere turns once and every shimmer repeats a whole number of times.
    var loop: Double {
        let base: Double = switch state {
        case .think, .read: 6
        case .search, .run: 4
        case .write: 3
        case .wait: 8
        case .idle, .error: 1
        }
        return lively ? base : base * 1.4
    }

    var frameCount: Int { still || state == .idle || state == .error ? 1 : Int((loop * Self.fps).rounded()) }

    func frame(_ i: Int) -> CGImage? {
        let px = Int((side * scale).rounded())
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(px))
        ctx.scaleBy(x: scale, y: -scale)
        draw(ctx, phase: Double(i) / Double(max(frameCount, 1)))
        return ctx.makeImage()
    }

    private func rgb(_ c: CGColor) -> (Double, Double, Double) {
        let s = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
        return (Double(s[0]), Double(s.count > 2 ? s[1] : s[0]), Double(s.count > 2 ? s[2] : s[0]))
    }

    /// `phase` 0..<1 through the loop.
    private func draw(_ ctx: CGContext, phase: Double) {
        let c = CGPoint(x: side / 2, y: side / 2)
        let tau = 2 * Double.pi
        if state == .idle {
            // At rest the sphere has gathered into one solid dot.
            ctx.setFillColor(accent)
            let d = side * 0.22
            ctx.fillEllipse(in: CGRect(x: c.x - d, y: c.y - d, width: d * 2, height: d * 2))
            return
        }
        let wait = state == .wait
        let R = side / 2 * (wait ? 0.66 : 0.86)
        let ink = rgb(ink), acc = rgb(accent), dan = rgb(danger)
        let base = state == .error ? dan : ink
        // One turn per loop; each shimmer runs a whole number of times per loop.
        let rot = tau * phase
        let w = { (k: Double) in tau * k * phase }
        let tilt = 0.35, ct = cos(tilt), st = sin(tilt), ca = cos(rot), sa = sin(rot)
        // Dots are gathered into a few shades (heat × depth), each filled as one path.
        let heatSteps = 4, depthSteps = 4
        var paths = (0..<(heatSteps * depthSteps)).map { _ in CGMutablePath() }
        for p in Self.points {
            let x1 = p.x * ca + p.z * sa, z1 = -p.x * sa + p.z * ca
            let y1 = p.y * ct - z1 * st, z2 = p.y * st + z1 * ct
            let depth = (z2 + 1) / 2
            var hot: Double = switch state {
            case .think: pow(max(0, sin(p.x * 3 + p.y * 4 + w(2))), 3)
            case .search: pow(max(0, sin(p.x * 5 - w(2))), 4)
            case .read: max(0, 1 - abs(p.y - sin(w(2)) * 0.9) * 4)
            case .write: pow(max(0, sin(atan2(p.z, p.x) * 2 - w(2))), 4)
            case .run: pow(max(0, sin(p.y * 6 + w(3))), 6)
            case .wait: 0.15
            case .idle, .error: 0
            }
            if still, state != .error { hot = 0.25 }
            let h = min(heatSteps - 1, Int(hot * Double(heatSteps)))
            let d = min(depthSteps - 1, Int(depth * Double(depthSteps)))
            let dot = (0.35 + depth * 0.75) * (lively ? 1.1 : 1) * side / 26
            paths[h * depthSteps + d].addEllipse(in: CGRect(x: c.x + x1 * R - dot, y: c.y + y1 * R - dot, width: dot * 2, height: dot * 2))
        }
        for h in 0..<heatSteps {
            let f = h == 0 ? 0 : (Double(h) + 0.5) / Double(heatSteps)
            let col = (base.0 + (acc.0 - base.0) * f, base.1 + (acc.1 - base.1) * f, base.2 + (acc.2 - base.2) * f)
            for d in 0..<depthSteps where !paths[h * depthSteps + d].isEmpty {
                let depth = (Double(d) + 0.5) / Double(depthSteps)
                ctx.setFillColor(CGColor(srgbRed: col.0, green: col.1, blue: col.2, alpha: 0.18 + depth * 0.82))
                ctx.addPath(paths[h * depthSteps + d])
                ctx.fillPath()
            }
        }
        if wait {
            // The ring breathes four times a loop: it's your turn.
            let k = still ? 0.5 : (sin(w(4)) + 1) / 2
            ctx.setStrokeColor(CGColor(srgbRed: acc.0, green: acc.1, blue: acc.2, alpha: 0.25 + k * 0.5))
            ctx.setLineWidth(1.4)
            let rr = R + side * 0.1 + k * side * 0.05
            ctx.strokeEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
        }
    }
}
