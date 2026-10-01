import TwainCore
import SwiftUI

/// The note's headings in the page's left margin, with a thin line whose end hooks towards
/// the section you are reading. Scrolling slides the hook along; hovering a heading points it
/// there (dashed) and clicking slides the page to it. Where the margin is narrow the outline
/// is a column of short dashes, and hovering grows the same spot into a glass panel with the
/// titles. Shown only for notes with a few headings, never in focus mode.
struct OutlineRail: View {
    static let minimumEntries = 3
    private static let row: CGFloat = 24

    @Bindable var model: AppModel
    @State private var hovered: Int?
    @State private var expanded = false

    var body: some View {
        GeometryReader { geo in
            let entries = model.editor.outline
            let rail = model.visibleAnnotations.isEmpty ? 0 : AnnotationRail.width
            let margin = (geo.size.width - rail - model.prefs.editorWidth) / 2
            if entries.count >= Self.minimumEntries, !model.chrome.zen, margin >= 44 {
                let wide = margin >= 210
                let showTitles = wide || expanded
                let width = wide ? min(margin - 48, 220) : expanded ? 220 : 28
                list(entries, titles: showTitles, height: min(CGFloat(entries.count) * Self.row, geo.size.height - 220))
                    .frame(width: width, alignment: .leading)
                    .padding(.vertical, expanded && !wide ? 8 : 0)
                    .padding(.horizontal, expanded && !wide ? 6 : 0)
                    .background {
                        if expanded && !wide {
                            Color.clear.surface(radius: Metrics.cardRadius)
                                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                        }
                    }
                    .contentShape(.rect)
                    .onHover { inside in
                        guard !wide else { return }
                        withMotion(Motion.morph) { expanded = inside }
                    }
                    .padding(.leading, 18).padding(.top, 100)
                    .transition(.opacity)
            }
        }
        .motion(Motion.standard, value: model.editor.outline.count >= Self.minimumEntries)
    }

    private func list(_ entries: [OutlineEntry], titles: Bool, height: CGFloat) -> some View {
        let minLevel = entries.map(\.level).min() ?? 1
        let current = min(model.editor.outlineCurrent, entries.count - 1)
        let target = hovered ?? current
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { i, e in
                        row(e, index: i, current: i == current, titles: titles, depth: e.level - minLevel)
                            .id(i)
                    }
                }
                .padding(.leading, 18)
                .background(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(.separator).frame(width: 1)
                            .padding(.leading, 4)
                        Hook(y: CGFloat(target) * Self.row + Self.row / 2)
                            .stroke(.tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round,
                                                              dash: hovered != nil && hovered != current ? [3, 3] : []))
                            .frame(width: 18)
                            .padding(.leading, 4)
                    }
                    .motion(hookAnimation, value: target)
                }
            }
            .frame(height: max(height, Self.row * 3))
            .scrollDisabled(height >= CGFloat(entries.count) * Self.row)
            .onChange(of: current) { _, c in withMotion(Motion.quick) { proxy.scrollTo(c, anchor: .center) } }
        }
    }

    private var hookAnimation: Animation? {
        Motion.style == .lively ? Motion.reduce ? Motion.reduced : .spring(response: 0.38, dampingFraction: 0.6) : Motion.content
    }

    private func row(_ e: OutlineEntry, index: Int, current: Bool, titles: Bool, depth: Int) -> some View {
        Button {
            model.editor.outlineCurrent = index
            model.scrollEditorTo?(e.offset)
        } label: {
            Group {
                if titles {
                    Text(e.title)
                        .font(.caption.weight(current ? .semibold : .regular))
                        .foregroundStyle(current ? AnyShapeStyle(.primary) : hovered == index ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.leading, CGFloat(depth) * 10)
                        .transition(.opacity)
                } else {
                    Capsule()
                        .fill(current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: max(6, 14 - CGFloat(depth) * 3), height: 2.5)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.row, maxHeight: Self.row, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(e.title)
        .onHover { inside in hovered = inside ? index : (hovered == index ? nil : hovered) }
        .motion(Motion.quick, value: current)
    }

    /// The guide line from the top down to `y`, bending right into a short tick.
    private struct Hook: Shape {
        var y: CGFloat
        var animatableData: CGFloat {
            get { y }
            set { y = newValue }
        }

        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: max(0, y - 7)))
            p.addQuadCurve(to: CGPoint(x: 7, y: y), control: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: 11, y: y))
            return p
        }
    }
}
