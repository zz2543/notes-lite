import SwiftUI

/// The app's few curves. Things that move together use the same one, so a panel sliding in,
/// the cards settling beside it and a page fading between notes read as one gesture.
enum Motion {
    /// Panels and pages: a quick start, a soft landing, no overshoot.
    static let standard = Animation.snappy(duration: 0.3)
    /// Small controls: toggles, badges, hover states.
    static let quick = Animation.snappy(duration: 0.18)
    /// New numbers in a chart or a card: slower, so the change can be followed.
    static let content = Animation.smooth(duration: 0.4)
    /// Things that appear from a point (a card, a menu): a slight settle.
    static let pop = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Honors “Reduce motion”: animations become cross-fades or nothing.
    static func adapted(_ a: Animation, reduce: Bool) -> Animation? { reduce ? .easeInOut(duration: 0.15) : a }
}
