import PlumeCore
import SwiftUI

/// The trailing inspector: one conversation with an agent, and the composer that starts the next turn.
struct AgentInspector: View {
    @Bindable var model: AppModel
    @FocusState private var inputFocused: Bool

    private static let suggestions: [(String, String)] = [
        ("text.append", "总结这篇笔记，在开头加一段摘要"),
        ("checklist", "整理这篇笔记的待办，合并重复项"),
        ("list.bullet.indent", "把这篇笔记改写成清晰的层级结构"),
    ]

    var body: some View {
        let sess = model.activeSession
        VStack(spacing: 0) {
            if let sess, !sess.items.isEmpty {
                transcript(sess)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) {
            if !model.sessions.isEmpty { sessionBar(sess) }
        }
        .safeAreaBar(edge: .bottom) { composer }
    }

    // MARK: session bar

    private func sessionBar(_ sess: AgentSession?) -> some View {
        HStack(spacing: 8) {
            Menu {
                Picker("会话", selection: Binding(get: { sess?.id }, set: { model.activeSessionID = $0 })) {
                    ForEach(model.sessions) { s in
                        Label(sessionTitle(s), systemImage: s.source == .terminal ? "apple.terminal" : Theme.agentSymbol(s.agent))
                            .tag(Optional(s.id))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 8) {
                    if let sess {
                        Image(systemName: Theme.agentSymbol(sess.agent)).foregroundStyle(Theme.agentColor(sess.agent))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(sess.title).font(.callout.weight(.medium)).lineLimit(1)
                            Text(meta(sess)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.visible)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .glassCapsule(interactive: true)
            .help("工作目录：" + (model.vault?.rootPath ?? ""))

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    if let sess, sess.source == .app, sess.running {
                        Button("停止", systemImage: "stop.fill") { model.stopAgent(sess) }
                            .help("停止")
                    }
                    Button("新会话", systemImage: "square.and.pencil", action: model.newSession)
                        .help("新会话")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, Metrics.floatInset).padding(.top, 8)
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
            parts.append(s.agent.displayName)
            if let id = s.cliSessionID { parts.append("会话 " + String(id.prefix(8))) }
        }
        if s.running { parts.append("运行中") }
        return parts.joined(separator: " · ")
    }

    // MARK: transcript

    private func transcript(_ sess: AgentSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sess.items) { ItemView(model: model, item: $0).id($0.id) }
                    if sess.running && sess.source == .app {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("\(sess.agent.displayName) 正在工作…").font(.caption).foregroundStyle(.secondary)
                        }
                        .id("running")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onChange(of: sess.items.count) { _, _ in
                withAnimation { proxy.scrollTo(sess.running ? AnyHashable("running") : AnyHashable(sess.items.last?.id), anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(.accentColor.opacity(0.12)), in: .circle)
            VStack(spacing: 6) {
                Text("描述一个任务").font(.title3.weight(.semibold))
                Text("Claude Code 或 Codex 会直接读写库里的 Markdown 文件。每次改动都进入审阅，可以逐段接受或还原。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if model.activeRel != nil {
                GlassEffectContainer(spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Self.suggestions, id: \.1) { icon, prompt in
                            Button {
                                model.runAgent(prompt: prompt, agent: model.agentPick)
                            } label: {
                                Label(prompt, systemImage: icon)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .font(.body)
                .lineLimit(2...8)
                .focused($inputFocused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    send()
                    return .handled
                }

            HStack(spacing: 8) {
                Picker("Agent", selection: $model.agentPick) {
                    ForEach(AgentKind.allCases, id: \.self) { k in
                        Label(k.displayName, systemImage: Theme.agentSymbol(k)).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                Spacer()
                Button("发送", systemImage: "arrow.up", action: send)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(model.agentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("发送 ↩ · 换行 ⇧↩")
            }
        }
        .padding(14)
        .floatingGlass(radius: Metrics.cardRadius + 4)
        .contentShape(.rect)
        .onTapGesture { inputFocused = true }
        .padding(Metrics.floatInset)
    }

    private func send() {
        model.runAgent(prompt: model.agentInput, agent: model.agentPick)
    }
}

// MARK: - Items

struct ItemView: View {
    @Bindable var model: AppModel
    let item: SessionItem

    var body: some View {
        switch item.kind {
        case let .user(t):
            HStack {
                Spacer(minLength: 36)
                Text(t)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.16), in: .rect(cornerRadius: 16, style: .continuous))
            }
        case let .step(_, text, running):
            HStack(spacing: 8) {
                Group {
                    if running {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: Self.icon(text)).foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 16)
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
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: Metrics.rowRadius + 2, style: .continuous))
        case let .change(rel, plus, minus):
            let pendingNow = model.pending[rel] != nil
            HStack(spacing: 10) {
                Image(systemName: pendingNow ? "doc.badge.clock" : "doc.text")
                    .font(.title3)
                    .foregroundStyle(pendingNow ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text((rel as NSString).lastPathComponent).fontWeight(.medium).lineLimit(1)
                    HStack(spacing: 6) {
                        CountBadge(plus: plus, minus: minus)
                        Text(pendingNow ? "待审阅" : "已处理").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if pendingNow {
                    Button("审阅") {
                        model.open(rel)
                        model.showDiff = true
                    }
                    .buttonStyle(.glassProminent)
                } else if model.vault?.note(rel) != nil {
                    Button("打开") { model.open(rel) }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .padding(10)
            .contentCard()
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
