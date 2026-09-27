import TwainCore
import SwiftUI

// The pieces of agent work that live inside the page. The editor hosts each one as a subview of
// the text, so it scrolls with the words it belongs to.

/// Over a selection: rewrite it in place, say how, or talk it through.
struct SelectionActions: View {
    @Bindable var model: AppModel
    @State private var custom = false
    @State private var instruction = ""
    @FocusState private var fieldFocused: Bool

    private var commands: [UserCommand] { model.userCommands.filter { $0.scope == .selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(AppModel.inlineActions, id: \.label) { a in
                    Button { model.startInline(label: a.label, instruction: a.instruction) } label: {
                        Label(a.label, systemImage: a.icon)
                    }
                    .help(a.instruction)
                }
                Divider().frame(height: 16).padding(.horizontal, 3)
                Button {
                    custom.toggle()
                    fieldFocused = custom
                } label: {
                    Label("按要求改…", systemImage: "text.cursor")
                }
                .help("告诉 agent 这段怎么改")
                Button { model.discussSelection() } label: {
                    Label("讨论", systemImage: "bubble.left.and.text.bubble.right")
                }
                .help("带着这段开一段对话 ⌘L")
                if !commands.isEmpty {
                    Menu {
                        ForEach(commands, id: \.key) { c in
                            Button(c.title, systemImage: c.icon) {
                                do { try model.runUserCommand(c, input: nil) } catch let e as RPCError { model.showToast(e.message) } catch {}
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("库里的自定义命令")
                }
            }
            if custom {
                TextField("比如：改成更正式的语气", text: $instruction)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit {
                        let t = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        model.startInline(label: "按要求改写", instruction: t)
                    }
                    .onExitCommand { custom = false }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.fill.quaternary, in: .capsule)
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .floatingGlass(radius: 14)
        .fixedSize()
    }
}

/// Under the passage being rewritten: progress, then the new text and what to do with it.
struct InlineCard: View {
    @Bindable var model: AppModel
    let width: CGFloat

    var body: some View {
        if let ie = model.inline {
            let agent = model.sessions.first { $0.id == ie.sessionID }?.agent ?? model.agentPick
            let tint = Theme.agentColor(agent)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: Theme.agentSymbol(agent)).foregroundStyle(tint)
                    Text(ie.running ? "\(agent.displayName) 正在\(ie.label)…" : ie.failed != nil ? "没能\(ie.label)" : "\(ie.label)后的文字")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if ie.running { ProgressView().controlSize(.mini) }
                    Spacer(minLength: 0)
                }
                if let p = ie.proposed {
                    Text(p)
                        .font(Font(model.font.nsFont(size: 16)))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let f = ie.failed {
                    Text(f).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if ie.proposed != nil {
                        Button("接受", systemImage: "checkmark", action: model.acceptInline)
                            .buttonStyle(.glassProminent)
                            .help("用它替换原文 ⏎")
                    }
                    Button(ie.running ? "取消" : "放弃", systemImage: "xmark", action: model.rejectInline)
                        .buttonStyle(.glass)
                        .help("保留原文 ⎋")
                    if !ie.running {
                        Button("再来一次", systemImage: "arrow.clockwise", action: model.retryInline)
                            .buttonStyle(.glass)
                    }
                    Spacer(minLength: 0)
                    Button("展开对话", systemImage: "bubble.left", action: model.discussInline)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("在旁注里接着说，比如「再短一点」")
                }
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                if ie.proposed != nil {
                    Text("⏎ 接受 · ⎋ 放弃").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(width: width, alignment: .leading)
            .background(tint.opacity(0.06), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        }
    }
}

/// At the end of an open task's line while the caret is on it: hand it to an agent.
struct TaskPill: View {
    @Bindable var model: AppModel
    let rel: String
    let line: Int
    let text: String

    var body: some View {
        Group {
            if let s = model.delegation(rel: rel, line: line) {
                HStack(spacing: 5) {
                    if s.running { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark") }
                    Text(s.running ? "\(s.agent.displayName) 处理中" : "已交给 \(s.agent.displayName)")
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .contentShape(.capsule)
                .onTapGesture { model.showThread(s) }
                .help("查看这个任务")
            } else {
                Button { model.delegateTask(rel: rel, line: line, text: text) } label: {
                    Label("交给 \(model.agentPick.displayName)", systemImage: Theme.agentSymbol(model.agentPick))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.agentColor(model.agentPick))
                .help("在后台让 agent 完成这条待办，完成后勾选并交给你审阅")
            }
        }
        .font(.caption)
        .glassCapsule(interactive: true)
        .fixedSize()
    }
}
