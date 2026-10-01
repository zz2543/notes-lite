import TwainCore
import SwiftUI

extension AppModel {
    /// The note quick captures go to: the vault's 收件箱 / Inbox, made at the top level if there is none.
    var inboxRel: String? {
        guard let v = vault else { return nil }
        return (v.note(titled: "收件箱") ?? v.note(titled: "Inbox"))?.rel
    }

    /// Appends a captured task to the inbox: through the editor when the inbox is open (so it
    /// can be undone there), else on disk. The inbox's automation, if any, picks it up from there.
    func capture(_ c: QuickCapture) {
        guard let v = vault, !c.isEmpty else { return }
        let rel = inboxRel ?? withMotion { v.create(title: "收件箱", content: "# 收件箱\n") }
        if agents.pending[rel] != nil || agents.writing.contains(rel) {
            showToast("收件箱正在等待审阅，稍后再记")
            return
        }
        func appended(_ text: String) -> String {
            text.isEmpty || text.hasSuffix("\n") ? text + c.markdown + "\n" : text + "\n" + c.markdown + "\n"
        }
        if rel == editor.activeRel {
            editorDidChange(appended(editor.editorText))
            editor.editorVersion += 1
        } else {
            // Read just now, so writing over it loses nothing.
            v.forceWrite(rel, appended(v.diskContent(rel) ?? ""))
        }
        emit("note.captured", source: "user", ["path": .string(rel), "line": .string(c.markdown)])
        Motion.feedback(.done)
        showToast("已记到 " + NoteRef(rel: rel).title + (c.due.map { " · " + Self.dueLabel($0) } ?? ""))
    }

    private static func dueLabel(_ day: String) -> String {
        let p = day.split(separator: "-")
        return p.count == 3 ? "\(Int(p[1]) ?? 0)月\(Int(p[2]) ?? 0)日" : day
    }
}

/// The palette's capture mode: the typed line with what was recognised picked out, and the
/// task it becomes. Each piece pops in as it is recognised, so you see the date was understood
/// before you press ↩, not after.
struct CapturePreview: View {
    let capture: QuickCapture
    let destination: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(highlighted)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "square")
                    .foregroundStyle(.tertiary)
                Text(capture.title.isEmpty ? "写下要做的事…" : capture.title)
                    .fontWeight(.medium)
                    .foregroundStyle(capture.title.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .font(.title3)
            FlowChips(chips: chips)
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                Text("↩ 记到「\(destination)」")
                Spacer()
                Text("日期、时间、#标签、[[链接]]、@人 会被认出来")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chips: [Chip] {
        var out: [Chip] = []
        if let due = capture.due, let t = capture.tokens.first(where: { $0.kind == .date }) {
            out.append(Chip(id: "d" + due, icon: "calendar", text: t.label, color: .blue))
        } else if let due = capture.due, capture.time != nil {
            out.append(Chip(id: "d" + due, icon: "calendar", text: Self.dayLabel(due), color: .blue))
        }
        if let time = capture.time {
            out.append(Chip(id: "t" + time, icon: "clock", text: time, color: .blue))
        }
        for t in capture.tokens {
            switch t.kind {
            case .tag: out.append(Chip(id: "g" + t.label, icon: "number", text: String(t.label.dropFirst()), color: Color(nsColor: Theme.NS.tag)))
            case .link: out.append(Chip(id: "l" + t.label, icon: "link", text: t.label, color: .green))
            case .person: out.append(Chip(id: "p" + t.label, icon: "person", text: String(t.label.dropFirst()), color: .orange))
            case .date, .time: break
            }
        }
        return out
    }

    private static func dayLabel(_ day: String) -> String {
        let p = day.split(separator: "-")
        return p.count == 3 ? "\(Int(p[1]) ?? 0)月\(Int(p[2]) ?? 0)日" : day
    }

    /// The typed line with each recognised piece tinted the colour of its chip.
    private var highlighted: AttributedString {
        let ns = capture.input as NSString
        var out = AttributedString()
        var at = 0
        for t in capture.tokens {
            guard t.range.location >= at else { continue }
            out += AttributedString(ns.substring(with: NSRange(location: at, length: t.range.location - at)))
            var piece = AttributedString(ns.substring(with: t.range))
            let color: Color = switch t.kind {
            case .date, .time: .blue
            case .tag: Color(nsColor: Theme.NS.tag)
            case .link: .green
            case .person: .orange
            }
            piece.foregroundColor = color
            piece.backgroundColor = color.opacity(0.14)
            out += piece
            at = t.range.location + t.range.length
        }
        out += AttributedString(ns.substring(from: min(at, ns.length)))
        return out
    }

    struct Chip: Identifiable, Equatable {
        let id: String
        let icon: String
        let text: String
        let color: Color
    }

    /// The recognised pieces as small pills; a new one pops in where it will stay.
    private struct FlowChips: View {
        let chips: [Chip]

        var body: some View {
            HStack(spacing: 6) {
                ForEach(chips) { c in
                    Label(c.text, systemImage: c.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(c.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(c.color.opacity(0.13), in: .capsule)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                if chips.isEmpty {
                    Text("没有日期，就是一条普通待办").font(.caption).foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .frame(height: 22)
            .motion(Motion.quick, value: chips.map(\.id))
        }
    }
}
