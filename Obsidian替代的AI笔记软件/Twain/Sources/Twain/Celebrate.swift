import SwiftUI

/// A short burst of confetti over its container when `trigger` changes (the lively style's
/// reward for finishing something). Draws with Canvas and only runs for the burst itself.
struct ConfettiBurst: View {
    let trigger: Int
    /// Where the pieces start, as a fraction of the container.
    var origin = UnitPoint(x: 0.5, y: 0.4)
    var count = 26

    @State private var start: Date?
    @State private var pieces: [Piece] = []

    struct Piece {
        var vx: Double, vy: Double, spin: Double, size: Double, color: Color, round: Bool
    }

    private static let duration = 0.95
    private static let colors: [Color] = [.green, .yellow, .accentColor, .orange, .purple, .pink]

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            Canvas { ctx, size in
                guard let start else { return }
                let t = tl.date.timeIntervalSince(start)
                guard t < Self.duration else { return }
                let o = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
                let fade = t < Self.duration * 0.6 ? 1 : 1 - (t - Self.duration * 0.6) / (Self.duration * 0.4)
                for p in pieces {
                    let x = o.x + p.vx * t, y = o.y + p.vy * t + 0.5 * 900 * t * t
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(p.spin * t))
                    let r = CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * (p.round ? 1 : 0.6))
                    c.fill(p.round ? Path(ellipseIn: r) : Path(r), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard Motion.celebrates else { return }
            pieces = (0..<count).map { i in
                let a = Double(i) / Double(count) * 2 * .pi + .random(in: 0...0.5)
                let v = Double.random(in: 160...340)
                return Piece(vx: cos(a) * v, vy: sin(a) * v - 260, spin: .random(in: -540...540), size: .random(in: 5...8),
                             color: Self.colors[i % Self.colors.count], round: i % 3 == 0)
            }
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { start = nil }
        }
    }
}
