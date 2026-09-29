import AppKit
import SwiftUI

/// The app's few curves. Things that move together use the same one, so a panel sliding in,
/// the cards settling beside it and a page fading between notes read as one gesture.
/// Under “Reduce motion” every one of them becomes a short cross-fade.
enum Motion {
    /// Panels and pages: a quick start, a soft landing, no overshoot.
    static let standard = Animation.snappy(duration: 0.3)
    /// Small controls: toggles, badges, menus, counters.
    static let quick = Animation.snappy(duration: 0.2)
    /// New numbers in a chart or a card: slower, so the change can be followed.
    static let content = Animation.smooth(duration: 0.4)
    /// Things that appear from a point (a card, a menu): a slight settle.
    static let pop = Animation.spring(response: 0.32, dampingFraction: 0.84)
    /// What every curve becomes under Reduce motion.
    static let reduced = Animation.easeInOut(duration: 0.15)

    /// Seconds, for AppKit animations that should match `standard` and `quick`.
    static let standardDuration: TimeInterval = 0.3
    static let quickDuration: TimeInterval = 0.2

    @MainActor static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// `animation`, or the short fade when the user asked for less motion.
    @MainActor static func resolved(_ animation: Animation) -> Animation { reduce ? reduced : animation }
}

/// `withAnimation` with one of the app's curves, honoring Reduce motion.
@MainActor @discardableResult
func withMotion<Result>(_ animation: Animation = Motion.standard, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.resolved(animation), body)
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content.animation(reduce ? Motion.reduced : animation, value: value)
    }
}

extension View {
    /// `animation(_:value:)` with one of the app's curves, honoring Reduce motion.
    func motion<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}
