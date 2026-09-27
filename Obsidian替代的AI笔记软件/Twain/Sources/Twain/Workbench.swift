import TwainCore
import SwiftUI

/// The desk: every agent run at once, and everything waiting on the user — questions, reviews,
/// review feedback — answerable in place. Tasks are dispatched from here and run in the
/// background, so several agents can work while the user triages what they send back.
struct Workbench: View {
    @Bindable var model: AppModel
    @State private var draft = ""
    @State private var tasks: [VaultIndex.TaskHit] = []
    /// Tasks handed out from here, by "rel:line", so they read as taken.
    @State private var delegated: Set<String> = []
    @FocusState private var draftFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                dispatchBar
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)],
                          alignment: .leading, spacing: 16) {
                    inbox
                    runs
                    openTasks
                    shortcuts
                }
            }
            .frame(maxWidth: 1120)
            .padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("工作台")
        .navigationSubtitle(model.vault?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("命令面板", systemImage: "magnifyingglass", action: model.openPalette)
                    .help("搜索笔记与命令 ⌘K")
            }
        }
        .task(id: model.tick) { reloadTasks() }
        .task(id: model.vault?.rootPath) { reloadTasks() }
    }

    // MARK: header

    private var waiting: (questions: [AgentQuestion], reviews: [PendingReview], feedback: [(AgentSession, UUID, String)]) {
        let qs = model.questions.values.filter { $0.answer == nil && !$0.expired }.sorted { $0.id.uuidString < $1.id.uuidString }
        let reviews = model.pending.values.sorted { $0.rel < $1.rel }
        var fb: [(AgentSession, UUID, String)] = []
        for s in model.sessions {
            for item in s.items {
                if case let .feedback(rel, _, false) = item.kind { fb.append((s, item.id, rel)) }
            }
        }
        return (qs, reviews, fb)
    }

    private var header: some View {
        let running = model.sessions.filter(\.running).count
        let w = waiting
        var parts: [String] = []
        parts.append(running > 0 ? "\(running) 个 agent 在运行" : "没有 agent 在运行")
        if !w.questions.isEmpty { parts.append("\(w.questions.count) 个问题等你回答") }
        if !w.reviews.isEmpty { parts.append("\(w.reviews.reduce(0) { $0 + $1.hunks.count }) 处改动待审阅") }
        parts.append("\(tasks.count) 条未完成的待办")
        return VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(.largeTitle.weight(.semibold))
            Text(parts.joined(separator: " · ")).foregroundStyle(.secondary)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        default: "晚上好"
        }
    }

    // MARK: dispatch

    private var dispatchBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("派一个任务给 \(model.agentPick.displayName)：它在后台完成，改动和问题会回到这里…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...5)
                .focused($draftFocused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || imeComposing() { return .ignored }
                    dispatch()
                    return .handled
                }
            HStack(spacing: 8) {
                AgentBar(model: model).frame(maxWidth: 340)
                Spacer(minLength: 0)
                Text("派出后留在工作台，可以同时派好几个").font(.caption).foregroundStyle(.tertiary)
                Button("派出", systemImage: "paperplane.fill", action: dispatch)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("在新会话里运行 ↩ · 换行 ⇧↩")
            }
        }
        .padding(14)
        .floatingGlass(radius: Metrics.cardRadius + 4)
        .contentShape(.rect)
        .onTapGesture { draftFocused = true }
    }

    private func dispatch() {
        let p = draft
        guard !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.dispatch(p, agent: model.agentPick)
        draft = ""
    }

    // MARK: inbox

    private var inbox: some View {
        let w = waiting
        let count = w.questions.count + w.reviews.count + w.feedback.count
        return DeskCard(title: "等你处理", icon: "tray", count: count) {
            if count == 0 {
                DeskEmpty(icon: "checkmark.circle", text: "没有需要你处理的事")
            }
            ForEach(w.questions) { q in
                VStack(alignment: .leading, spacing: 4) {
                    if let s = model.sessions.first(where: { $0.id == q.sessionID }) {
                        Text("\(s.agent.displayName) · \(s.title)").font(.caption).foregroundStyle(.secondary)
                    }
                    QuestionCard(model: model, question: q)
                }
            }
            ForEach(w.reviews, id: \.rel) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.isProposal ? "doc.badge.ellipsis" : "doc.badge.clock")
                        .font(.title3)
                        .foregroundStyle(r.by.map(Theme.agentColor) ?? .secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(((r.rel as NSString).lastPathComponent as NSString).deletingPathExtension).fontWeight(.medium).lineLimit(1)
                        HStack(spacing: 6) {
                            CountBadge(plus: r.plus, minus: r.minus)
                            Text("\(r.by?.displayName ?? "外部") \(r.isProposal ? "提议" : "改动") · \(r.hunks.count) 处")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("全部接受") { model.acceptAll(r.rel) }
                        .buttonStyle(.glass)
                        .help(r.isProposal ? "把这份提案全部写入文件" : "保留 agent 的全部改动")
                    Button("审阅") { model.review(r.rel) }
                        .buttonStyle(.glassProminent)
                        .help("在 Agent 模式中逐段审阅")
                }
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .padding(10)
                .contentCard()
            }
            ForEach(w.feedback, id: \.1) { s, itemID, rel in
                HStack(spacing: 10) {
                    Image(systemName: "text.bubble").font(.title3).foregroundStyle(.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("审阅意见 · " + ((rel as NSString).lastPathComponent as NSString).deletingPathExtension)
                            .fontWeight(.medium).lineLimit(1)
                        Text("还没有发回给 \(s.agent.displayName)").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("发回") { model.sendFeedback(itemID, in: s) }
                        .buttonStyle(.glassProminent)
                        .disabled(s.running)
                        .help("让 \(s.agent.displayName) 根据你的审阅意见重新修改")
                }
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .padding(10)
                .contentCard()
            }
        }
    }

    // MARK: runs

    private var runs: some View {
        let order: (AgentSession) -> Int = { s in
            switch model.state(of: s) {
            case .asking: 0
            case .running: 1
            case .reviewing: 2
            case .failed: 3
            case .done: 4
            }
        }
        let sorted = model.sessions.enumerated()
            .sorted { (order($0.element), -$0.offset) < (order($1.element), -$1.offset) }
            .map(\.element)
            .filter { !$0.items.isEmpty || $0.running }
        return DeskCard(title: "Agent 任务", icon: "bubble.left.and.text.bubble.right", count: sorted.count) {
            if sorted.isEmpty {
                DeskEmpty(icon: "paperplane", text: "还没有任务。在上面派一个，或者把待办交给 agent。")
            }
            ForEach(sorted.prefix(8)) { s in
                RunRow(model: model, session: s)
            }
            if sorted.count > 8 {
                Text("还有 \(sorted.count - 8) 个会话，在 Agent 模式的会话列表里").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: tasks

    private func reloadTasks() {
        guard let (index, _) = try? model.freshIndex() else { tasks = []; return }
        tasks = index.tasks().filter { !$0.rel.hasPrefix(".twain/") }
    }

    private var openTasks: some View {
        DeskCard(title: "未完成的待办", icon: "checklist", count: tasks.count) {
            if tasks.isEmpty {
                DeskEmpty(icon: "checkmark.seal", text: "库里没有未完成的待办")
            }
            ForEach(Array(tasks.prefix(10).enumerated()), id: \.offset) { _, t in
                let key = "\(t.rel):\(t.task.line)"
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                    Button {
                        model.setWorkspace(.write)
                        model.open(t.rel)
                        model.requestFocus(caret: CommandRegistry.offset(ofLine: t.task.line, in: model.editorText))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.task.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Text(((t.rel as NSString).lastPathComponent as NSString).deletingPathExtension + (t.task.heading.map { " › " + $0 } ?? ""))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("在写作模式中打开 \(t.rel) 第 \(t.task.line) 行")
                    if delegated.contains(key) {
                        Label("已交给 agent", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button {
                            delegated.insert(key)
                            model.delegate(t, agent: model.agentPick)
                        } label: {
                            Label("交给 \(model.agentPick.displayName)", systemImage: Theme.agentSymbol(model.agentPick))
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .help("在后台新开一个会话完成这条待办")
                    }
                }
                .padding(.vertical, 2)
            }
            if tasks.count > 10 {
                Text("还有 \(tasks.count - 10) 条").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: commands & automations

    private var shortcuts: some View {
        DeskCard(title: "命令与自动化", icon: "bolt", count: nil) {
            if model.userCommands.isEmpty && model.automations.isEmpty {
                DeskEmpty(icon: "bolt.slash", text: "库的 .twain/commands 与 .twain/automations 里还没有文件")
            }
            if !model.userCommands.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(model.userCommands, id: \.key) { c in
                        Button {
                            do { try model.runUserCommand(c, input: nil) } catch let e as RPCError { model.showToast(e.message) } catch {}
                        } label: {
                            Label(c.title, systemImage: c.icon)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .help("/\(c.key) · \(c.agent.displayName)" + (c.scope == .vault ? "" : " · 作用于当前笔记"))
                    }
                }
            }
            if !model.automations.isEmpty {
                HStack {
                    Text("自动化").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.automationsOn ? "今日已运行 \(model.automationRunsToday) / \(model.automationDailyLimit) 次" : "已在设置中关闭")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.top, 4)
                ForEach(model.automations, id: \.id) { a in
                    let approved = model.isApproved(a)
                    Button {
                        model.setWorkspace(.write)
                        model.open(a.file)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.circle").foregroundStyle(Theme.agentColor(a.agent))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title).lineLimit(1)
                                Text(a.on.joined(separator: "、") + (a.match.map { " · " + $0 } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(approved ? "已启用" : "待批准")
                                .font(.caption)
                                .foregroundStyle(approved ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("打开 \(a.file)")
                }
            }
        }
    }
}

/// One run on the desk: who, what, where it stands, and what it last said.
private struct RunRow: View {
    @Bindable var model: AppModel
    let session: AgentSession

    var body: some View {
        let state = model.state(of: session)
        let touched = model.touched(session)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: session.source == .terminal ? "apple.terminal" : session.source == .automation ? "bolt.circle" : Theme.agentSymbol(session.agent))
                .foregroundStyle(Theme.agentColor(session.agent))
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        if state == .running { ProgressView().controlSize(.mini) }
                        Text(state.label)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(state.color)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(state.color.opacity(0.12), in: .capsule)
                }
                if let line = model.lastLine(session) {
                    Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if !touched.isEmpty {
                    Label(touched.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }.joined(separator: "、"),
                          systemImage: "doc.text")
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            if session.running, session.source == .app {
                Button("停止", systemImage: "stop.fill") { model.stopAgent(session) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("停止")
            }
        }
        .padding(10)
        .contentCard()
        .contentShape(.rect)
        .onTapGesture {
            model.activeSessionID = session.id
            model.setWorkspace(.agent)
        }
        .help("在 Agent 模式中打开这个会话")
    }
}

/// A titled group on the desk.
private struct DeskCard<Content: View>: View {
    let title: String
    let icon: String
    let count: Int?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon).font(.headline)
                if let count, count > 0 {
                    Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(.fill.secondary, in: .capsule)
                }
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quinary, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

private struct DeskEmpty: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}
