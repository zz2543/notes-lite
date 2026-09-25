import PlumeCore
import SwiftUI

/// Plain button with the prototype's hover background.
struct HoverButtonStyle: ButtonStyle {
    var hover: Color = .black.opacity(0.05)
    var base: Color = .clear
    var radius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, hover: hover, base: base, radius: radius)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let hover: Color
        let base: Color
        let radius: CGFloat
        @State private var over = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: radius).fill(over || configuration.isPressed ? hover : base))
                .onHover { over = $0 }
        }
    }
}

extension ButtonStyle where Self == HoverButtonStyle {
    static var hover: HoverButtonStyle { HoverButtonStyle() }
    static func hover(_ hover: Color, base: Color = .clear, radius: CGFloat = 6) -> HoverButtonStyle {
        HoverButtonStyle(hover: hover, base: base, radius: radius)
    }
}

struct DarkButton: View {
    let title: String
    var height: CGFloat = 24
    var horizontal: CGFloat = 11
    var fill: Color = Theme.dark
    var weight: Font.Weight = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: weight))
                .foregroundStyle(.white)
                .padding(.horizontal, horizontal)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 6).fill(fill))
        }
        .buttonStyle(.plain)
    }
}

struct OutlineButton: View {
    let title: String
    var height: CGFloat = 24
    var horizontal: CGFloat = 10
    var size: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, horizontal)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xE0DCD6)))
        }
        .buttonStyle(.plain)
    }
}

struct PlumeSwitch: View {
    let on: Bool
    var enabled = true
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Theme.accent : Color(hex: 0xDCD9D4)).frame(width: 32, height: 19)
                Circle().fill(.white).frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.2), value: on)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// White "raised" segment inside a tinted track.
struct SegmentButton: View {
    let label: String
    let on: Bool
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: small ? 11.5 : 12, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Theme.ink : Theme.muted2)
                .lineLimit(1)
                .padding(.horizontal, small ? 8 : 12)
                .frame(height: small ? 22 : 24)
                .background(
                    RoundedRectangle(cornerRadius: small ? 5 : 6)
                        .fill(on ? Color.white : .clear)
                        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PillToggle: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(on ? Theme.pillText : Theme.muted2)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Theme.pillBg : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

struct FileGlyph: View {
    var color: Color = Color(hex: 0xA9A49B)
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(color, lineWidth: 1.2)
            .frame(width: 10, height: 12)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
    }
}

struct ToggleRow: View {
    let label: String
    let desc: String
    let on: Bool
    var enabled = true
    var first = false
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium))
                Text(desc).font(.system(size: 11.5)).foregroundStyle(Theme.muted2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PlumeSwitch(on: on, enabled: enabled, toggle: toggle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.hairline).frame(height: 1) } }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardLine))
    }
}

struct SidebarIcon: View {
    var body: some View {
        Canvas { ctx, _ in
            var p = Path(roundedRect: CGRect(x: 1.5, y: 2.5, width: 13, height: 11), cornerRadius: 2)
            p.move(to: CGPoint(x: 6, y: 2.5))
            p.addLine(to: CGPoint(x: 6, y: 13.5))
            ctx.stroke(p, with: .color(Theme.icon), lineWidth: 1.3)
        }
        .frame(width: 16, height: 16)
    }
}

struct SearchIcon: View {
    var size: CGFloat = 14
    var color: Color = Theme.icon
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 16
            var p = Path(ellipseIn: CGRect(x: 2.2 * s, y: 2.2 * s, width: 9.6 * s, height: 9.6 * s))
            p.move(to: CGPoint(x: 10.5 * s, y: 10.5 * s))
            p.addLine(to: CGPoint(x: 14 * s, y: 14 * s))
            ctx.stroke(p, with: .color(color), lineWidth: 1.5)
        }
        .frame(width: size, height: size)
    }
}

extension AgentKind {
    var color: Color { Theme.agentColor(self) }
}

func agentLabel(_ a: AgentKind?) -> String { a?.displayName ?? "外部程序" }
