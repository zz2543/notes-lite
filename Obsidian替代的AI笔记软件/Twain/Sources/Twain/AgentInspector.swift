import TwainCore
import SwiftUI

/// One conversation with an agent, and the composer that starts the next turn. In the writing
/// workspace it is the trailing inspector; as the `stage` of the agent workspace it takes the
/// middle of the window, in a readable column, with the notes the session touched above it.
struct AgentInspector: View {
    @Bindable var model: AppModel
    var stage = false
    @FocusState private var inputFocused: Bool

    /// Readable width of the conversation when it has the whole middle of the window.
    static let stageWidth: CGFloat = 720

    private static let suggestions: [(String, String)] = [
        ("text.append", "总结这篇笔记，在开头加一段摘要"),
        ("checklist", "整理这篇笔记的待办，合并重复项"),
        ("list.bullet.indent", "把这篇笔记改写成清晰的层级结构"),
    ]

    /// Tasks that span the vault, offered when the conversation has the stage.
    private static let vaultSuggestions: [(String, String)] = [
        ("tray.full", "汇总全库未完成的待办，按项目整理成一篇笔记"),
        ("link", "为当前笔记找出相关的笔记，补上 [[双链]]"),
        ("calendar", "根据这周改过的笔记，写一篇本周回顾"),
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
            VStack(spacing: 8) {
                AgentBar(model: model)
                if !model.sessions.isEmpty { sessionBar(sess) }
                if stage, let sess { TouchedStrip(model: model, session: sess) }
            }
            .frame(maxWidth: stage ? Self.stageWidth : .infinity)
            .padding(.horizontal, Metrics.floatInset).padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
        .safeAreaBar(edge: .bottom) { composer }
        .onAppear { if stage { inputFocused = true } }
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
            parts.append(s.model.map { model.modelName($0, for: s.agent) } ?? s.agent.displayName)
            if let e = s.effort { parts.append(Effort.name(e)) }
            if let id = s.cliSessionID { parts.append("会话 " + String(id.prefix(8))) }
        }
        if s.running { parts.append("运行中") }
        return parts.joined(separator: " · ")
    }

    // MARK: transcript

    private func transcript(_ sess: AgentSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                let finals = Self.turnFinalReplies(sess.items)
                LazyVStack(alignment: .leading, spacing: stage ? 16 : 12) {
                    ForEach(sess.items) { item in
                        ItemView(model: model, session: sess, item: item, replyActions: finals.contains(item.id))
                            .id(item.id)
                    }
                    if sess.running && sess.source == .app {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("\(sess.agent.displayName) 正在工作…").font(.caption).foregroundStyle(.secondary)
                        }
                        .id("running")
                    }
                }
                .padding(.horizontal, stage ? 24 : 16).padding(.vertical, 12)
                .frame(maxWidth: stage ? Self.stageWidth + 48 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onChange(of: sess.items.count) { _, _ in
                withAnimation { proxy.scrollTo(sess.running ? AnyHashable("running") : AnyHashable(sess.items.last?.id), anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            AgentLogo(agent: model.agentPick)
                .frame(width: stage ? 108 : 84, height: stage ? 108 : 84)
                .id(model.agentPick)
                .transition(.blurReplace)
            VStack(spacing: 6) {
                Text(stage ? "让 agent 在你的笔记库里工作" : "描述一个任务").font(stage ? .title2.weight(.semibold) : .title3.weight(.semibold))
                Text(stage
                     ? "它写入的笔记会在右侧打开，你看着它写。回复可以直接插入笔记或存成新笔记；在笔记里选中一段，会作为引用一起发送。"
                     : "Claude Code 或 Codex 会直接读写库里的 Markdown 文件。每次改动都进入审阅，可以逐段接受或还原。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            if model.activeRel != nil || stage {
                GlassEffectContainer(spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestions, id: \.1) { icon, prompt, run in
                            Button(action: run) {
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
                .frame(maxWidth: stage ? 460 : .infinity)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The vault's note commands, or the built-in prompts when it has none.
    private var suggestions: [(String, String, () -> Void)] {
        let m = model
        var out: [(String, String, () -> Void)] = []
        if m.activeRel != nil {
            let own = m.userCommands.filter { $0.scope == .note }.prefix(3)
            if !own.isEmpty {
                out = own.map { c in (c.icon, c.title, {
                    do { try m.runUserCommand(c, input: nil) } catch let e as RPCError { m.showToast(e.message) } catch {}
                }) }
            } else {
                out = Self.suggestions.map { icon, prompt in (icon, prompt, { m.runAgent(prompt: prompt, agent: m.agentPick) }) }
            }
        }
        if stage {
            out = Array(out.prefix(2)) + Self.vaultSuggestions.map { icon, prompt in (icon, prompt, { m.runAgent(prompt: prompt, agent: m.agentPick) }) }
        }
        return out
    }

    /// The last reply of each turn — the one worth keeping — gets the note actions.
    static func turnFinalReplies(_ items: [SessionItem]) -> Set<UUID> {
        var out = Set<UUID>()
        var last: UUID?
        for item in items {
            switch item.kind {
            case .agent: last = item.id
            case .user: if let l = last { out.insert(l) }; last = nil
            default: break
            }
        }
        if let last { out.insert(last) }
        return out
    }

    // MARK: composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ContextShelf(model: model)

            HStack(alignment: .bottom, spacing: 8) {
                TextField(stage ? "让 \(model.agentPick.displayName) 在笔记库里做点什么…" : "让 \(model.agentPick.displayName) 修改当前笔记…",
                          text: $model.agentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(2...8)
                    .focused($inputFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        // Return while an input method is composing picks the candidate; let it through.
                        if press.modifiers.contains(.shift) || imeComposing() { return .ignored }
                        send()
                        return .handled
                    }
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
        .frame(maxWidth: stage ? Self.stageWidth : .infinity)
        .padding(Metrics.floatInset)
        .frame(maxWidth: .infinity)
    }

    private func send() {
        guard !model.agentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.runAgent(prompt: model.composedPrompt(model.agentInput), agent: model.agentPick)
    }
}

/// The capsule under the toolbar: which agent the next run goes to, and the model it runs on.
/// Resumed sessions keep their history under a newly picked model.
struct AgentBar: View {
    @Bindable var model: AppModel
    @Namespace private var selection

    var body: some View {
        // Drop decoration before the model name gets cut short.
        ViewThatFits(in: .horizontal) {
            row(icons: true, fit: true)
            row(icons: false, fit: true)
            row(icons: false, fit: false)
        }
        .padding(4)
        .frame(height: 40)
        .glassCapsule(interactive: true)
    }

    private func row(icons: Bool, fit: Bool) -> some View {
        HStack(spacing: 4) {
            segments(icons: icons).layoutPriority(1)
            modelMenu(icon: icons)
                .fixedSize(horizontal: fit, vertical: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func segments(icons: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(AgentKind.allCases, id: \.self) { k in
                let on = model.agentPick == k
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.agentPick = k }
                } label: {
                    HStack(spacing: 5) {
                        if icons {
                            Image(systemName: Theme.agentSymbol(k))
                                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.agentColor(k)))
                        }
                        Text(k.displayName).lineLimit(1)
                    }
                    .font(.callout.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .background {
                        if on { Capsule().fill(.tint).matchedGeometryEffect(id: "pick", in: selection) }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .opacity(model.agentEnabled(k) ? 1 : 0.45)
                .help(model.agentEnabled(k) ? "下一次运行使用 \(k.displayName)" : "\(k.displayName) 已在设置中停用")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func modelMenu(icon: Bool) -> some View {
        let kind = model.agentPick
        return Button {
            model.refreshModels()
            model.modelPickerOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                if icon { Image(systemName: "cpu").imageScale(.small) }
                Text(model.modelLabel(kind)).lineLimit(1).truncationMode(.tail)
                if let e = model.effectiveEffort(kind) {
                    Text("· " + Effort.name(e)).lineLimit(1).fixedSize().foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("\(kind.displayName) 使用的模型与思考强度")
        .popover(isPresented: $model.modelPickerOpen, arrowEdge: .bottom) {
            ModelPicker(model: model, kind: kind)
        }
    }

    /// "" (CLI default), the known models, and the current choice if it's a custom id.
    static func options(_ model: AppModel, _ kind: AgentKind) -> [String] {
        var ids = [""] + model.models(kind).map(\.id)
        if let cur = model.agentModel[kind], !cur.isEmpty, !ids.contains(cur) { ids.append(cur) }
        return ids
    }
}

/// The popover behind the model chip: the CLI's own model list, and how hard the model thinks.
struct ModelPicker: View {
    @Bindable var model: AppModel
    let kind: AgentKind
    @State private var hovered: String?
    @State private var showMore = false

    var body: some View {
        let all = model.models(kind)
        let primary = all.filter(\.primary)
        let more = all.filter { !$0.primary }
        let current = model.agentModel[kind] ?? ""
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader(kind.displayName + " 模型")
                    row(id: "", name: model.modelName("", for: kind), detail: "沿用 \(kind.executable) 自己的配置")
                    ForEach(primary) { row(id: $0.id, name: $0.name, detail: $0.detail) }
                    if !current.isEmpty, all.find(current) == nil {
                        row(id: current, name: current, detail: "自定义模型")
                    }
                    if !more.isEmpty {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { showMore.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("更多模型")
                                Image(systemName: "chevron.right").imageScale(.small)
                                    .rotationEffect(.degrees(showMore || more.contains { $0.id == current } ? 90 : 0))
                                Spacer()
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if showMore || more.contains(where: { $0.id == current }) {
                            ForEach(more) { row(id: $0.id, name: $0.name, detail: $0.detail) }
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)

            if let warn = model.staleCLIWarning(kind) {
                Label(warn, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }

            Divider()
            effort.padding(14)
            Divider()
            Button {
                model.openSettings(.agent)
            } label: {
                Label("在设置中填写其他模型…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 320)
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.bottom, 4)
    }

    private func row(id: String, name: String, detail: String?) -> some View {
        let on = (model.agentModel[kind] ?? "") == id
        return Button {
            model.agentModel[kind] = id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.callout.weight(on ? .semibold : .regular)).lineLimit(1)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if on { Image(systemName: "checkmark").font(.callout.weight(.semibold)).foregroundStyle(.tint) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(hovered == id ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: Metrics.rowRadius, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
    }

    @ViewBuilder private var effort: some View {
        let levels = model.effortLevels(kind)
        let explicit = !(model.agentEffort[kind] ?? "").isEmpty
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("思考强度", systemImage: "brain").font(.callout.weight(.medium))
                Spacer()
                if let cur = model.effectiveEffort(kind) {
                    Text(Effort.name(cur) + (explicit ? "" : "（默认）"))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                if explicit {
                    Button("重置", systemImage: "arrow.counterclockwise") { model.agentEffort[kind] = "" }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                        .help("跟随 \(kind.executable) 的默认强度")
                }
            }
            if levels.count >= 2 {
                let index = Binding<Double>(
                    get: { Double(levels.firstIndex(of: model.effectiveEffort(kind) ?? "") ?? 0) },
                    set: { model.agentEffort[kind] = levels[min(max(Int($0.rounded()), 0), levels.count - 1)] })
                Slider(value: index, in: 0...Double(levels.count - 1), step: 1)
                    .labelsHidden()
                HStack(spacing: 0) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { i, l in
                        Button(Effort.name(l)) { model.agentEffort[kind] = l }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(l == model.effectiveEffort(kind) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        if i < levels.count - 1 { Spacer(minLength: 0) }
                    }
                }
            } else {
                Text("\(model.modelLabel(kind)) 不支持调节思考强度").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Items

struct ItemView: View {
    @Bindable var model: AppModel
    let session: AgentSession
    let item: SessionItem
    var replyActions = false

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
            VStack(alignment: .leading, spacing: 6) {
                AgentMarkdownReply(source: t)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if replyActions && !(session.running && item.id == session.items.last?.id) {
                    ReplyActions(model: model, session: session, text: t)
                }
            }
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
        case let .question(id):
            if let q = model.questions[id] { QuestionCard(model: model, question: q) }
        case let .feedback(rel, message, sent):
            FeedbackCard(model: model, session: session, itemID: item.id, rel: rel, message: message, sent: sent)
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
                    Button("审阅") { model.review(rel) }
                        .buttonStyle(.glassProminent)
                } else if model.vault?.note(rel) != nil {
                    Button("打开") {
                        model.open(rel)
                        model.revealNote()
                    }
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

/// An agent's `ask_user`: the question, its options, and room to answer in your own words.
struct QuestionCard: View {
    @Bindable var model: AppModel
    let question: AgentQuestion
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(question.question).fontWeight(.medium).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(Theme.agentColor(question.agent))
            }
            if let answer = question.answer {
                Label("你的回答：" + answer, systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.secondary)
            } else if question.expired {
                Label("没有回答，\(question.agent.displayName) 已继续", systemImage: "clock.badge.xmark")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                if !question.options.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(question.options, id: \.self) { o in
                            Button { model.answer(question.id, o) } label: {
                                Text(o).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                if question.allowText {
                    HStack(spacing: 6) {
                        TextField(question.options.isEmpty ? "输入回答…" : "或者写下你的回答…", text: $text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .focused($focused)
                            .onSubmit { model.answer(question.id, text) }
                        Button("回答", systemImage: "arrow.up") { model.answer(question.id, text) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.circle)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.rowRadius + 2, style: .continuous))
                }
            }
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .padding(12)
        .contentCard()
        .onAppear { if question.answer == nil, !question.expired, question.options.isEmpty { focused = true } }
    }
}

/// After a review with rejections: what will be sent back, and the button that sends it.
private struct FeedbackCard: View {
    @Bindable var model: AppModel
    let session: AgentSession
    let itemID: UUID
    let rel: String
    let message: String
    let sent: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
                Text("审阅意见 · \((rel as NSString).lastPathComponent)").fontWeight(.medium).lineLimit(1)
                Spacer(minLength: 0)
                Button(expanded ? "收起" : "查看") { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } }
                    .buttonStyle(.borderless).font(.caption)
            }
            if expanded {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sent {
                Label("已发回给 \(session.agent.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("把意见发回给 \(session.agent.displayName)", systemImage: "arrowshape.turn.up.left") {
                    model.sendFeedback(itemID, in: session)
                }
                .buttonStyle(.glassProminent)
                .disabled(session.running)
                .help("在这个会话里继续，让 \(session.agent.displayName) 根据你的审阅意见重新修改")
            }
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .padding(12)
        .contentCard()
    }
}
