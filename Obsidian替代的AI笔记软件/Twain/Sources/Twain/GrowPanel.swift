import AppKit
import SwiftUI

/// When a grow panel last closed because of a click outside it. The button that opened it sits
/// outside it too: the same click must not reopen what it just closed.
@MainActor enum GrowPanelClock {
    static var closedByClick = Date.distantPast
    static var justClosed: Bool { Date().timeIntervalSince(closedByClick) < 0.4 }
}

/// A click: where it landed, in the coordinates of the window it landed in.
struct WindowPoint: Equatable {
    let point: CGPoint
    let window: Int
}

/// Where the pointer was when something was clicked — the place a panel opened by that click
/// grows out of. Nil when it was opened from the keyboard.
@MainActor func clickPoint() -> WindowPoint? {
    // Only clicks in a document window: a menu bar item's window is not where anything grows from.
    guard let e = NSApp.currentEvent, let w = e.window, w.styleMask.contains(.titled),
          [.leftMouseUp, .leftMouseDown, .rightMouseUp, .otherMouseUp].contains(e.type) else { return nil }
    return WindowPoint(point: e.locationInWindow, window: w.windowNumber)
}

/// A panel that grows out of the control that opened it and shrinks back into it, instead of
/// a popover with an arrow: the same object getting bigger, so the eye never loses where it
/// came from. A solid surface lifted a level above the page. A click outside or ⎋ closes it.
///
/// Put it on the view the panel may cover (`.growPanel(...)`); `origin` is the click point in
/// window coordinates, `fallback` where it grows from when there was no click (unit point of
/// the host), `width` the panel's width.
struct GrowPanelHost<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let origin: WindowPoint?
    var fallback: UnitPoint = .topTrailing
    var width: CGFloat = 320
    /// Dim what's behind: for a panel that asks you to choose before going on.
    var dims = false
    @ViewBuilder let panel: () -> Panel

    /// The host's AppKit view, asked for its place in the window only when the panel opens —
    /// never tracked, so resizing the host (the Agent panel sliding) costs nothing extra.
    @State private var probe = ProbeBox()
    @State private var panelSize: CGSize = .zero
    @State private var escape: Any?
    @State private var outside: Any?

    func body(content: Content) -> some View {
        content
            .background(WindowProbe(box: probe))
            .overlay {
                GeometryReader { geo in
                    let size = geo.size
                    // Never wider than the area it floats over (a narrow Agent panel).
                    let w = min(width, max(160, size.width - 24))
                    let at = localOrigin(in: size)
                    let place = placement(of: panelSize == .zero ? CGSize(width: w, height: 200) : panelSize, at: at, in: size)
                    ZStack(alignment: .topLeading) {
                        if isPresented {
                            Color.black.opacity(dims ? 0.12 : 0)
                                .contentShape(.rect)
                                .onTapGesture { close() }
                                .transition(.opacity)
                            panel()
                                .frame(width: w)
                                // Its own height: a flexible frame here would stretch to the window.
                                .fixedSize(horizontal: false, vertical: true)
                                .background { SurfaceFill(shape: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous), shadow: false, raised: true) }
                                .clipShape(.rect(cornerRadius: Metrics.cardRadius, style: .continuous))
                                .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
                                .onGeometryChange(for: CGSize.self, of: \.size) { panelSize = $0 }
                                .offset(x: place.origin.x, y: place.origin.y)
                                .transition(.grow(from: place.anchor))
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                }
            }
            .motion(Motion.morph ?? Motion.overlay, value: isPresented)
            .onChange(of: isPresented) { _, open in open ? watchEscape() : stopWatching() }
            .onDisappear { stopWatching() }
    }

    private func close() { isPresented = false }

    private func localOrigin(in size: CGSize) -> CGPoint {
        // A click in another window (Settings) has no place here: grow from the fallback.
        if let origin, let view = probe.view, view.window?.windowNumber == origin.window {
            // A click outside the host (a toolbar button above it) is moved onto its edge, so the
            // panel still grows from right under the button.
            let host = view.convert(view.bounds, to: nil)
            let p = origin.point
            return CGPoint(x: min(max(p.x - host.minX, 0), host.width), y: min(max(host.maxY - p.y, 0), host.height))
        }
        return CGPoint(x: fallback.x * size.width, y: fallback.y * size.height)
    }

    /// Below the click when it fits, else above; centred on it, kept 12 pt inside the host.
    private func placement(of p: CGSize, at o: CGPoint, in host: CGSize) -> (origin: CGPoint, anchor: UnitPoint) {
        // Right under the top edge when the click was above the host: nothing peeks out above it.
        let gap: CGFloat = o.y <= 0 ? 6 : 14
        let below = o.y + gap + p.height <= host.height - 12 || o.y < host.height / 2
        // Kept inside the host top to bottom, even if that means covering the click.
        let y = min(below ? o.y + gap : o.y - gap - p.height, host.height - 12 - p.height)
        let x = min(max(12, o.x - p.width / 2), max(12, host.width - 12 - p.width))
        let anchor = UnitPoint(x: min(max((o.x - x) / max(p.width, 1), 0), 1), y: below ? 0 : 1)
        return (CGPoint(x: x, y: max(o.y <= 0 ? 6 : 12, y)), anchor)
    }

    private func watchEscape() {
        stopWatching()
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            // ⎋ closes the panel unless an input method is composing (it cancels the composition).
            guard e.keyCode == 53, !imeComposing() else { return e }
            MainActor.assumeIsolated { isPresented = false }
            return nil
        }
        // A click anywhere outside the host (elsewhere in the window, or another window) closes
        // it too, as a popover would; clicks inside the host are handled by its dimmer. The click
        // still goes where it was aimed.
        let box = probe
        outside = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { e in
            MainActor.assumeIsolated {
                guard let view = box.view else { return }
                let inHost = e.window === view.window && view.convert(view.bounds, to: nil).contains(e.locationInWindow)
                if !inHost, isPresented {
                    isPresented = false
                    GrowPanelClock.closedByClick = Date()
                }
            }
            return e
        }
    }

    private func stopWatching() {
        if let escape { NSEvent.removeMonitor(escape) }
        if let outside { NSEvent.removeMonitor(outside) }
        escape = nil
        outside = nil
    }
}

extension View {
    func growPanel<P: View>(isPresented: Binding<Bool>, origin: WindowPoint?, fallback: UnitPoint = .topTrailing,
                            width: CGFloat = 320, dims: Bool = false, @ViewBuilder panel: @escaping () -> P) -> some View {
        modifier(GrowPanelHost(isPresented: isPresented, origin: origin, fallback: fallback, width: width, dims: dims, panel: panel))
    }
}

/// Grows from `anchor`: small, blurred and see-through at first, then itself.
private struct GrowEffect: ViewModifier {
    let progress: CGFloat
    let anchor: UnitPoint
    var from: CGFloat = 0.35
    var blurs = true

    func body(content: Content) -> some View {
        let minimal = Motion.style == .minimal || Motion.reduce
        content
            .scaleEffect(minimal ? 1 : from + (1 - from) * progress, anchor: anchor)
            .blur(radius: minimal || !blurs ? 0 : (1 - progress) * 6)
            .opacity(progress)
    }
}

extension AnyTransition {
    static func grow(from anchor: UnitPoint) -> AnyTransition {
        .modifier(active: GrowEffect(progress: 0, anchor: anchor), identity: GrowEffect(progress: 1, anchor: anchor))
    }

    /// `grow` for a glass panel: no blur (blurring glass would flatten it into a bitmap), and
    /// from a larger start, since a wide panel shrunk far reads as a different object.
    static func growGlass(from anchor: UnitPoint) -> AnyTransition {
        .modifier(active: GrowEffect(progress: 0, anchor: anchor, from: 0.6, blurs: false),
                  identity: GrowEffect(progress: 1, anchor: anchor, from: 0.6, blurs: false))
    }
}

/// A page arriving from where it lives: spaces and questions from the sidebar side, the review
/// from the banner above the note. It comes forward out of a slight blur; leaving, it goes back
/// the same way.
private struct PageEffect: ViewModifier {
    let edge: Edge
    let progress: CGFloat

    func body(content: Content) -> some View {
        let minimal = Motion.style == .minimal || Motion.reduce
        let away = 1 - progress
        content
            .scaleEffect(minimal ? 1 : 0.97 + 0.03 * progress, anchor: edge == .top ? .top : .leading)
            .offset(x: minimal || edge != .leading ? 0 : -20 * away, y: minimal || edge != .top ? 0 : -12 * away)
            .blur(radius: minimal ? 0 : 4 * away)
            .opacity(progress)
    }
}

extension AnyTransition {
    static func page(from edge: Edge) -> AnyTransition {
        .modifier(active: PageEffect(edge: edge, progress: 0), identity: PageEffect(edge: edge, progress: 1))
    }
}

final class ProbeBox {
    weak var view: NSView?
}

/// An empty AppKit view behind the host, so the host's place in the window can be asked for.
private struct WindowProbe: NSViewRepresentable {
    let box: ProbeBox

    func makeNSView(context: Context) -> Probe {
        let v = Probe()
        box.view = v
        return v
    }

    func updateNSView(_ view: Probe, context: Context) { box.view = view }

    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
