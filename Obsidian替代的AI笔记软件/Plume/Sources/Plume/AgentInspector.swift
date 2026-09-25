import PlumeCore
import SwiftUI

struct AgentInspector: View {
    @Bindable var model: AppModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        let sess = model.activeSession
        VStack(spacing: 0) {
            if !model.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Picker("会话", selection: Binding(get: { sess?.id }, set: { model.activeSessionID = $0 })) {
                            ForEach(model.sessions) { s in
                                Text(sessionTitle(s)).tag(Optional(s.id))
                            }
                        }
                        .labelsHidden()
                        if let sess, sess.source == .app, sess.running {
                            Button { model.stopAgent(sess) } label: { Image(systemName: "stop.fill") }
                                .help("停止")
                        }
                        Button(action: model.newSession) { Image(systemName: "square.and.pencil") }
                            .help("新会话")
                    }
                    .buttonStyle(.borderless)
                    if let sess {
                        Text(meta(sess))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help("工作目录：" + (model.vault?.rootPath ?? ""))
                    }
                }
                .padding(10)
                .plumeControlGlass(in: RoundedRectangle(cornerRadius: 15))
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            }

            if let sess, !sess.items.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(sess.items) { ItemView(model: model, item: $0).id($0.id) }
                            if sess.running && sess.source == .app {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("\(sess.agent.displayName) 正在工作…").font(.caption).foregroundStyle(.secondary)
                                }
                                .id("running")
                            }
                        }
                        .padding(14)
                    }
                    .onChange(of: sess.items.count) { _, _ in
                        withAnimation { proxy.scrollTo(sess.running ? AnyHashable("running") : AnyHashable(sess.items.last?.id), anchor: .bottom) }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("描述一个任务", systemImage: "sparkles")
                } description: {
                    Text("Claude Code 或 Codex 会直接读写库里的 Markdown 文件。每次改动都进入审阅，可以逐段接受或还原。")
                }
                .frame(maxHeight: .infinity)
            }

            composer
        }
    }

    private func sessionTitle(_ s: AgentSession) -> String {
        (s.source == .terminal ? "终端 · " : "") + s.agent.displayName + " · " + s.title
    }

    private func meta(_ s: AgentSession) -> String {
        var parts: [String] = []
        if s.source == .terminal {
            parts.append("终端 pid \(s.pid.map(String.init) ?? "?")")
            parts.append(!s.alive ? "已结束" : model.watchTerminal ? "监听中" : "未监听")
        } else {
            parts.append("应用内会话")
            if let id = s.cliSessionID { parts.append("会话 " + String(id.prefix(8))) }
        }
        if s.running { parts.append("运行中") }
        parts.append("在 " + (model.vault?.name ?? "库") + " 中")
        return parts.joined(separator: " · ")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let n = model.activeNote {
                    Label((n.rel as NSString).lastPathComponent, systemImage: "doc.text")
                        .lineLimit(1).truncationMode(.middle)
                }
                Label("AGENTS.md", systemImage: "doc.badge.gearshape").lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(TagLabelStyle())

            TextField("让 agent 修改当前笔记…", text: $model.agentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...8)
                .focused($inputFocused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    send()
                    return .handled
                }

            HStack(spacing: 8) {
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 4) {
                        HStack(spacing: 4) {
                            ForEach(AgentKind.allCases, id: \.self) { kind in
                                agentChoice(kind)
                            }
                        }
                    }
                } else {
                    Picker("Agent", selection: $model.agentPick) {
                        ForEach(AgentKind.allCases, id: \.self) { k in Text(k.displayName).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
                Spacer()
                Button(action: send) { Image(systemName: "arrow.up") }
                    .plumePrimaryButton()
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .disabled(model.agentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("发送 ↩")
            }
        }
        .padding(10)
        .plumeControlGlass(in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }

    private func send() {
        model.runAgent(prompt: model.agentInput, agent: model.agentPick)
    }

    @ViewBuilder
    private func agentChoice(_ kind: AgentKind) -> some View {
        if kind == model.agentPick {
            Button(kind.displayName) { model.agentPick = kind }
                .plumePrimaryButton()
                .controlSize(.small)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(kind.displayName) { model.agentPick = kind }
                .plumeGlassButton()
                .controlSize(.small)
        }
    }
}

struct TagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct ItemView: View {
    @Bindable var model: AppModel
    let item: SessionItem

    var body: some View {
        switch item.kind {
        case let .user(t):
            HStack {
                Spacer(minLength: 32)
                Text(t)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            }
        case let .step(_, text, running):
            HStack(spacing: 6) {
                if running {
                    ProgressView().controlSize(.mini).frame(width: 14)
                } else {
                    Image(systemName: Self.icon(text)).frame(width: 14).foregroundStyle(.tertiary)
                }
                Text(text).lineLimit(2).truncationMode(.middle)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        case let .agent(t):
            AgentMarkdownReply(source: t)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .error(t):
            Label {
                Text(t).textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        case let .change(rel, plus, minus):
            let pendingNow = model.pending[rel] != nil
            HStack(spacing: 10) {
                Image(systemName: "doc.text").font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text((rel as NSString).lastPathComponent).fontWeight(.medium).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("+\(plus)").foregroundStyle(.green)
                        Text("−\(minus)").foregroundStyle(.red)
                        Text(pendingNow ? "待审阅" : "已处理").foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if pendingNow {
                    Button("审阅") {
                        model.open(rel)
                        model.showDiff = true
                    }
                    .plumePrimaryButton().controlSize(.small)
                } else if model.vault?.note(rel) != nil {
                    Button("打开") { model.open(rel) }.controlSize(.small)
                }
            }
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
    }

    static func icon(_ step: String) -> String {
        if step.hasPrefix("读取") { return "doc.text.magnifyingglass" }
        if step.hasPrefix("写入") { return "pencil" }
        if step.hasPrefix("搜索") || step.hasPrefix("查找") || step.hasPrefix("网页搜索") { return "magnifyingglass" }
        if step.hasPrefix("$") { return "terminal" }
        if step.hasPrefix("⚠︎") { return "exclamationmark.triangle" }
        return "circle.dotted"
    }
}
