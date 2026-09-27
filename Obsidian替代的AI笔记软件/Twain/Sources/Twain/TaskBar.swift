import TwainCore
import SwiftUI

/// ⌘L: hand an agent something to do, from anywhere. The scope starts at what the user is
/// looking at — the selection, else the note, else the vault — and can be widened. Return runs
/// it in the background; ⌘Return opens it as a conversation instead.
struct TaskBar: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    @State private var picking = false

    private var threadFirst: Bool { model.taskThreadFirst }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { model.taskBar = false }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.agentColor(model.agentPick))
                    TextField(model.taskScope == .selection ? "对选中的这段做什么？" : "交给 agent 一件事…", text: $model.taskText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .lineLimit(1...6)
                        .focused($focused)
                        .onKeyPress(.return, phases: .down) { press in
                            if imeComposing() || press.modifiers.contains(.shift) { return .ignored }
                            let command = press.modifiers.contains(.command)
                            model.startTask(asThread: command != threadFirst)
                            return .handled
                        }
                        .onExitCommand { model.taskBar = false }
                }
                scopeRow
                pinsRow
                Divider()
                HStack(spacing: 10) {
                    AgentBar(model: model).frame(minWidth: 300, maxWidth: 380)
                    Spacer(minLength: 8)
                    Button {
                        model.startTask(asThread: !threadFirst)
                    } label: {
                        Label(threadFirst ? "后台运行" : "作为对话打开", systemImage: threadFirst ? "tray.and.arrow.down" : "bubble.left.and.text.bubble.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glass)
                    .help(threadFirst ? "在后台运行，结果进入「待处理」 ⌘⏎" : "在中间打开对话，右侧是它的草稿 ⌘⏎")
                    Button {
                        model.startTask(asThread: threadFirst)
                    } label: {
                        Label(threadFirst ? "开始对话" : "后台运行", systemImage: threadFirst ? "bubble.left.and.text.bubble.right" : "arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glassProminent)
                    .help(threadFirst ? "在中间打开对话 ⏎" : "在后台运行，你可以继续写；需要你时出现在「待处理」 ⏎")
                }
                .buttonBorderShape(.capsule)
                .disabled(model.taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
            .frame(width: 660)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.55),
                        in: .rect(cornerRadius: Metrics.panelRadius, style: .continuous))
            .floatingGlass(radius: Metrics.panelRadius)
            .padding(.top, 96)
        }
        .onAppear { focused = true }
    }

    private var scopeRow: some View {
        HStack(spacing: 6) {
            Text("范围").font(.caption).foregroundStyle(.secondary)
            ForEach(TaskScope.allCases) { sc in
                let available = sc == .selection ? model.selectionPreview != nil : sc == .note ? model.activeRel != nil : true
                let on = model.taskScope == sc
                Button { model.taskScope = sc } label: {
                    Label(scopeTitle(sc), systemImage: sc.icon)
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(on ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.fill.quaternary), in: .capsule)
                        .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .opacity(available ? 1 : 0.4)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private func scopeTitle(_ sc: TaskScope) -> String {
        switch sc {
        case .selection:
            if let q = model.selectionPreview {
                let t = q.text.replacingOccurrences(of: "\n", with: " ")
                return "选区「" + (t.count > 14 ? String(t.prefix(14)) + "…" : t) + "」"
            }
            return sc.title
        case .note:
            return model.activeNote?.displayName ?? sc.title
        case .vault:
            return model.vault.map { "整个库 · " + $0.name } ?? sc.title
        }
    }

    private var pinsRow: some View {
        HStack(spacing: 6) {
            Text("参考").font(.caption).foregroundStyle(.secondary)
            ForEach(model.contextPins, id: \.self) { rel in
                Button { model.unpin(rel) } label: {
                    Label {
                        HStack(spacing: 3) {
                            Text(InboxView.name(rel)).lineLimit(1)
                            Image(systemName: "xmark").imageScale(.small).foregroundStyle(.tertiary)
                        }
                    } icon: {
                        Image(systemName: "pin.fill")
                    }
                }
                .buttonStyle(.plain)
                .help(rel + "（点按移除）")
            }
            Button { picking = true } label: { Label("参考笔记", systemImage: "plus") }
                .buttonStyle(.plain)
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    NotePicker(model: model) { rel in
                        model.pin(rel)
                        picking = false
                    }
                }
            Spacer(minLength: 0)
            Text(threadFirst ? "⏎ 开始对话 · ⌘⏎ 后台运行 · ⎋ 取消" : "⏎ 后台运行 · ⌘⏎ 作为对话打开 · ⎋ 取消")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(TagLabelStyle())
    }
}
