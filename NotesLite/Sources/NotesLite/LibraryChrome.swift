import AppKit
import NotesCore
import SwiftUI

extension Color {
    static let paper = Color(nsColor: .textBackgroundColor)
    static let navigationAccent = Color.primary
    static let library = adaptive(light: 0.956, dark: 0.115)
    static let listPaper = adaptive(light: 0.985, dark: 0.14)
    static let selectionPaper = adaptive(light: 1, dark: 0.24)
    static let hairline = Color.primary.opacity(0.065)
    private static func adaptive(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: appearance.bestMatch(from: [.darkAqua]) == .darkAqua ? dark : light, alpha: 1)
        })
    }
}

enum Motion {
    static let panel = Animation.spring(duration: 0.5, bounce: 0.20)
    static let selection = Animation.spring(duration: 0.32, bounce: 0.18)
    static let feedback = Animation.spring(duration: 0.24, bounce: 0.16)
    static let hover = Animation.easeOut(duration: 0.16)
    static let row = AnyTransition.opacity.combined(with: .offset(y: 7)).combined(with: .scale(scale: 0.985))
}

struct SoftButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftButtonBody(label: configuration.label, pressed: configuration.isPressed)
    }
    private struct SoftButtonBody<Label: View>: View {
        let label: Label
        let pressed: Bool
        @State private var hovered = false
        var body: some View {
            label.padding(7)
                .background(Color.primary.opacity(pressed ? 0.10 : hovered ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(hovered ? 0.035 : 0)))
                .scaleEffect(pressed ? 0.93 : 1)
                .offset(y: hovered && !pressed ? -1 : 0)
                .onHover { hovered = $0 }
                .animation(Motion.feedback, value: pressed)
                .animation(Motion.hover, value: hovered)
        }
    }
}

/// Presentation sizing, independent of the document and of animation state.
struct ColumnWidths: Equatable {
    var sidebar: Double
    var list: Double
    static func fitting(total: Double, sidebar: Double, list: Double) -> ColumnWidths {
        let available = max(400, total - 322)
        let side = min(max(sidebar.isFinite ? sidebar : 208, 180), min(280, available - 220))
        let middle = min(max(list.isFinite ? list : 280, 220), min(380, available - side))
        return ColumnWidths(sidebar: side, list: middle)
    }
}

struct ColumnDivider: View {
    @Binding var width: Double
    let limits: ClosedRange<Double>
    let label: String
    @State private var hovered = false
    @State private var dragStart: Double?
    var body: some View {
        Color.hairline.frame(width: 1)
            .overlay {
                Capsule().fill(Color.primary.opacity(hovered || dragStart != nil ? 0.25 : 0))
                    .frame(width: 3, height: 28)
            }
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { hovered = $0; (hovered ? NSCursor.resizeLeftRight : NSCursor.arrow).set() }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { event in
                            if dragStart == nil { dragStart = width }
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            withTransaction(transaction) { width = min(limits.upperBound, max(limits.lowerBound, (dragStart ?? width) + event.translation.width)) }
                        }
                        .onEnded { _ in dragStart = nil })
            }
            .animation(Motion.hover, value: hovered)
            .accessibilityElement().accessibilityLabel(label)
            .accessibilityValue("\(Int(width)) 点")
            .accessibilityAdjustableAction { direction in
                width = min(limits.upperBound, max(limits.lowerBound, width + (direction == .increment ? 16 : -16)))
            }
            .onDisappear { if hovered { NSCursor.arrow.set() } }
    }
}

struct FolderEntry: Identifiable, Equatable {
    let path: String
    let depth: Int
    let hasChildren: Bool
    var id: String { path }
    var title: String { (path as NSString).lastPathComponent }
    static func visible(paths: [String], expanded: Set<String>) -> [FolderEntry] {
        let parents = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        let sorted = paths.sorted { left, right in
            let a = left.split(separator: "/"), b = right.split(separator: "/")
            for (x, y) in zip(a, b) where x != y {
                return String(x).localizedStandardCompare(String(y)) == .orderedAscending
            }
            return a.count < b.count
        }
        return sorted.compactMap { path in
            let parts = path.split(separator: "/")
            for level in 1..<max(1, parts.count) {
                if !expanded.contains(parts.prefix(level).joined(separator: "/")) { return nil }
            }
            return FolderEntry(path: path, depth: parts.count - 1, hasChildren: parents.contains(path))
        }
    }
    static func ancestors(of path: String) -> Set<String> {
        let parts = path.split(separator: "/")
        return Set((1..<max(1, parts.count)).map { parts.prefix($0).joined(separator: "/") })
    }
}

struct NavigationRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let namespace: Namespace.ID
    var count: Int? = nil
    var depth = 0
    var expanded: Bool? = nil
    var toggle: (() -> Void)? = nil
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 0) {
            if let expanded {
                Button(action: { toggle?() }) {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 18, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel((expanded ? "收起" : "展开") + title)
            } else if icon.hasPrefix("folder") { Color.clear.frame(width: 18) }
            Button(action: action) {
                HStack(spacing: 9) {
                    Image(systemName: icon).font(.system(size: 13, weight: .regular)).frame(width: 18)
                        .foregroundStyle(selected ? Color.primary : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(title).font(.system(size: 12, weight: selected ? .medium : .regular)).lineLimit(1)
                    Spacer(minLength: 3)
                    if let count { Text("\(count)").font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.tertiary) }
                }.padding(.leading, icon.hasPrefix("folder") ? 1 : 10).padding(.trailing, 10)
                    .frame(height: 34).contentShape(Rectangle())
            }.buttonStyle(NotePressStyle())
        }
        .padding(.leading, CGFloat(depth) * 14)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8).fill(Color.selectionPaper)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.055)))
                    .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
                    .matchedGeometryEffect(id: "navigation-selection", in: namespace)
            }
        }
        .background(Color.primary.opacity(hovered && !selected ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
        .offset(y: hovered && !selected ? -1 : 0)
        .onHover { hovered = $0 }
        .animation(Motion.hover, value: hovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title)
    }
}

struct NoteRow<Actions: View>: View {
    let note: Note
    let selected: Bool
    let showFolder: Bool
    let namespace: Namespace.ID
    let select: () -> Void
    @ViewBuilder let actions: () -> Actions
    @State private var hovered = false
    private var menuVisible: Bool { hovered || selected }
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(note.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(note.modified, format: .dateTime.month(.twoDigits).day(.twoDigits))
                        .font(.system(size: 9.5)).monospacedDigit().foregroundStyle(.tertiary)
                        .padding(.trailing, 18)
                }
                if !note.preview.isEmpty {
                    Text(note.preview).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                if showFolder && !note.folder.isEmpty {
                    Label(note.folder, systemImage: "folder").font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(NotePressStyle())
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10).fill(Color.selectionPaper)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
                    .shadow(color: .black.opacity(0.045), radius: 5, y: 2)
                    .matchedGeometryEffect(id: "note-selection", in: namespace)
            }
        }
        .background(Color.primary.opacity(hovered && !selected ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            Menu(content: actions) { Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18, height: 18).padding(.top, 9).padding(.trailing, 9)
                .opacity(menuVisible ? 1 : 0).allowsHitTesting(menuVisible).accessibilityHidden(!menuVisible)
                .accessibilityLabel("整理「\(note.title)」")
        }
        .contextMenu(menuItems: actions)
        .offset(y: hovered && !selected ? -1 : 0)
        .onHover { hovered = $0 }
        .animation(Motion.hover, value: hovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(note.title)
    }
}

private struct NotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.feedback, value: configuration.isPressed)
    }
}
