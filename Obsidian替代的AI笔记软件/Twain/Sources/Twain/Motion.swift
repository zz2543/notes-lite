import AppKit
import SwiftUI

/// How much the app moves, chosen in Settings → 编辑器 → 动效.
enum MotionStyle: String, CaseIterable, Identifiable {
    /// Almost nothing moves: changes appear at once, as before motion was added.
    case minimal
    /// Every change has a transition that starts quickly and settles without bouncing.
    case calm
    /// Things wind up, overshoot and settle; finishing something gets a small celebration.
    case lively

    var id: String { rawValue }
    var label: String { ["minimal": "简洁", "calm": "克制", "lively": "活泼"][rawValue]! }
    var detail: String {
        switch self {
        case .minimal: "几乎不动：变化直接出现，只保留提示条和命令面板的淡入。"
        case .calm: "每个变化都有过渡，快起慢停、不回弹，像系统自带的动画。"
        case .lively: "先蓄力再弹出、冲过头再落回；完成待办、打卡、接受改动时有一点庆祝。"
        }
    }
}

/// The app's curves, by role, for the chosen style. Things that move together use the same
/// role, so a panel sliding in, the cards settling beside it and a page fading between notes
/// read as one gesture. Under “Reduce motion” every role becomes a 0.15 s fade.
@MainActor
enum Motion {
    /// Set from Preferences when the app starts and whenever the setting changes.
    static var style: MotionStyle = .calm
    /// Short sounds when something is finished (off unless the user turns them on).
    static var sound = false

    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static let reduced = Animation.easeInOut(duration: 0.15)

    /// Panels and pages.
    static var standard: Animation? { pick(nil, .snappy(duration: 0.3), .spring(response: 0.42, dampingFraction: 0.62)) }
    /// Small controls: toggles, badges, menus, counters.
    static var quick: Animation? { pick(nil, .snappy(duration: 0.2), .spring(response: 0.34, dampingFraction: 0.52)) }
    /// New numbers in a chart or a card: slower, so the change can be followed.
    static var content: Animation? { pick(nil, .smooth(duration: 0.4), .spring(response: 0.5, dampingFraction: 0.7)) }
    /// Things that appear from a point (a card, a menu, a check mark).
    static var pop: Animation? { pick(nil, .snappy(duration: 0.25), .spring(response: 0.32, dampingFraction: 0.45)) }
    /// Toasts and the command palette, which moved even before there was a setting.
    static var overlay: Animation? { pick(.snappy(duration: 0.22), .snappy(duration: 0.25), .spring(response: 0.4, dampingFraction: 0.55)) }

    /// A shape changing size or form in place: a capsule widening into a message, a card
    /// folding down to one line. The same object stays on screen, so the eye can follow it.
    static var morph: Animation? { pick(nil, .smooth(duration: 0.36), .spring(response: 0.44, dampingFraction: 0.7)) }

    /// The `i`th of several things arriving together, a beat after the one before it.
    static func stagger(_ i: Int, _ base: Animation?) -> Animation? {
        guard let base, style != .minimal, !reduce else { return base }
        return base.delay(Double(min(i, 8)) * 0.04)
    }

    /// Whether ambient motion (spinners, rotating hints) runs at all.
    static var ambient: Bool { style != .minimal && !reduce }

    /// Whether finishing something (a task, a check-in, an accepted change) gets confetti.
    static var celebrates: Bool { style == .lively && !reduce }

    private static func pick(_ minimal: Animation?, _ calm: Animation?, _ lively: Animation?) -> Animation? {
        if reduce { return style == .minimal && minimal == nil ? nil : reduced }
        switch style {
        case .minimal: return minimal
        case .calm: return calm
        case .lively: return lively
        }
    }

    // MARK: AppKit

    /// Seconds for AppKit animations in the `standard` and `quick` roles; 0 means don't animate.
    static var standardDuration: TimeInterval { style == .minimal ? 0 : reduce ? 0.15 : 0.3 }
    static var quickDuration: TimeInterval { style == .minimal ? 0 : reduce ? 0.15 : 0.2 }

    /// A Core Animation spring for `keyPath` matching the style's `role`, or a plain ease-out
    /// under the calm style; nil when the style (or Reduce motion) says not to move.
    static func spring(_ keyPath: String, from: Any, to: Any, bouncy: Bool = true) -> CABasicAnimation? {
        if style == .minimal || reduce { return nil }
        if style == .calm || !bouncy {
            let a = CABasicAnimation(keyPath: keyPath)
            a.fromValue = from
            a.toValue = to
            a.duration = 0.25
            a.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            return a
        }
        // SwiftUI's response 0.36 / damping 0.45 in Core Animation's terms.
        let response = 0.36, damping = 0.45
        let a = CASpringAnimation(keyPath: keyPath)
        a.mass = 1
        a.stiffness = pow(2 * .pi / response, 2)
        a.damping = 4 * .pi * damping / response
        a.fromValue = from
        a.toValue = to
        a.duration = a.settlingDuration
        return a
    }

    /// Scale keyframes: a quick press down to `down`, then a spring back to `from` that
    /// overshoots (SwiftUI's response / dampingFraction). For the lively style's pops.
    static func windUpAndSpring(from: Double, down: Double, response: Double, damping: Double) -> CAKeyframeAnimation {
        let press = 0.09
        let k = pow(2 * .pi / response, 2), c = 4 * .pi * damping / response, dt = 1.0 / 120
        var x = down, v = 0.0, values = [from, down], times = [0, press]
        var t = press
        for i in 0..<360 {
            let a = -k * (x - from) - c * v
            v += a * dt
            x += v * dt
            t += dt
            if i % 2 == 1 { values.append(x); times.append(t) }
            if i > 10, abs(x - from) < 0.001, abs(v) < 0.01 { break }
        }
        values.append(from); times.append(t + dt)
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values = values
        anim.keyTimes = times.map { NSNumber(value: $0 / (t + dt)) }
        anim.duration = t + dt
        anim.calculationMode = .linear
        return anim
    }

    // MARK: feedback

    enum Moment { case done, celebrate, notice }

    /// A short system sound and, on a Force Touch trackpad, a tap — for finishing things in the
    /// lively style. The sound only plays when the user turned sounds on.
    static func feedback(_ m: Moment) {
        guard style != .minimal else { return }
        if sound {
            let name: NSSound.Name = switch m {
            case .done: "Pop"
            case .celebrate: "Glass"
            case .notice: "Tink"
            }
            NSSound(named: name)?.play()
        }
        if style == .lively, m != .notice {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
}

/// `withAnimation` with one of the app's roles; runs without animation when the style says so.
@MainActor @discardableResult
func withMotion<Result>(_ animation: Animation?, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(animation, body)
}

/// `withMotion` in the `standard` role.
@MainActor @discardableResult
func withMotion<Result>(_ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.standard, body)
}

extension View {
    /// `animation(_:value:)` with one of the app's roles.
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        self.animation(animation, value: value)
    }
}
