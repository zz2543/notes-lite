import TwainCore
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
            // Another session (or the first reply) cross-fades in instead of replacing the view at once.
            if let sess, !sess.items.isEmpty {
                transcript(sess)
                    .id(sess.id)
                    .transition(.opacity)
            } else {
                emptyState
                    .transition(.opacity)
            }
        }
        .motion(Motion.standard, value: sess.map { $0.items.isEmpty ? UUID?.none : $0.id } ?? nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) {
            VStack(spacing: 8) {
                AgentBar(model: model)
                if !model.agents.sessions.isEmpty { sessionBar(sess) }
            }
            .padding(.horizontal, Metrics.floatInset).padding(.top, 8)
        }
        .safeAreaBar(edge: .bottom) { composer }
    }

    // MARK: session bar

    private func sessionBar(_ sess: AgentSession?) -> some View {
        HStack(spacing: 8) {
            Menu {
                Picker("会话", selection: Binding(get: { sess?.id }, set: { model.agents.activeSessionID = $0 })) {
                    ForEach(model.agents.sessions) { s in
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
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                    Button("新会话", systemImage: "square.and.pencil", action: model.newSession)
                        .help("新会话")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
            .motion(Motion.pop, value: sess?.running == true && sess?.source == .app)
        }
    }

    private func sessionTitle(_ s: AgentSession) -> String {
        (s.source == .terminal ? "终端 · " : "") + s.agent.displayName + " · " + s.title
    }

    private func meta(_ s: AgentSession) -> String {
        var parts: [String] = []
        if s.source == .terminal {
            parts.append("终端 pid \(s.pid.map(String.init) ?? "?")")
            parts.append(!s.alive ? "已结束" : model.prefs.watchTerminal ? "监听中" : "未监听")
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
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sess.items) {
                        ItemView(model: model, session: sess, item: $0).id($0.id)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                    if sess.running && sess.source == .app {
                        let now = Self.activity(sess)
                        HStack(spacing: 8) {
                            GlyphSpinner(activity: now, tint: Theme.agentColor(sess.agent))
                            RollingText(text: "\(sess.agent.displayName) \(now.verb)…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .id("running")
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .motion(Motion.standard, value: sess.items.count)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            // A session opens at its latest message. The scroll view places its first offset
            // itself once the rows are laid out; a scrollTo from onAppear ran before the lazy
            // rows had real heights and left a long conversation at the top. The transcript
            // gets a fresh scroll view per session (`.id(sess.id)` above), so switching
            // sessions lands at the bottom too.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .contextMenu {
                Button("拷贝整个会话（Markdown）", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sess.markdown, forType: .string)
                    model.showToast("已拷贝会话")
                }
            }
            .onChange(of: sess.items.count) { _, _ in
                withMotion { proxy.scrollTo(sess.running ? AnyHashable("running") : AnyHashable(sess.items.last?.id), anchor: .bottom) }
            }
        }
    }

    /// What the agent is doing right now, from its latest step that is still running.
    static func activity(_ sess: AgentSession) -> GlyphSpinner.Activity {
        for item in sess.items.reversed() {
            if case let .step(_, text, running) = item.kind { return running ? GlyphSpinner.Activity(step: text) : .think }
        }
        return .think
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            AgentLogo(agent: model.agents.agentPick)
                .frame(width: 84, height: 84)
                .id(model.agents.agentPick)
                .transition(.blurReplace)
            VStack(spacing: 6) {
                Text("描述一个任务").font(.title3.weight(.semibold))
                Text("Claude Code 或 Codex 会直接读写库里的 Markdown 文件。每次改动都进入审阅，可以逐段接受或还原。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if model.editor.activeRel != nil {
                GlassEffectContainer(spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.1) { i, s in
                            let (icon, prompt, run) = s
                            Button(action: run) {
                                Label(prompt, systemImage: icon)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .arrive(i + 1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The vault's note commands, or the built-in prompts when it has none.
    private var suggestions: [(String, String, () -> Void)] {
        let m = model
        let own = m.userCommands.filter { $0.scope == .note }.prefix(3)
        if !own.isEmpty {
            return own.map { c in (c.icon, c.title, {
                do { try m.runUserCommand(c, input: nil) } catch let e as RPCError { m.showToast(e.message) } catch {}
            }) }
        }
        return Self.suggestions.map { icon, prompt in (icon, prompt, { m.runAgent(prompt: prompt, agent: m.agents.agentPick) }) }
    }

    // MARK: composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let n = model.activeNote {
                    Label((n.rel as NSString).lastPathComponent, systemImage: "doc.text")
                        .lineLimit(1).truncationMode(.middle)
                        .id(n.rel)
                        .transition(.blurReplace)
                }
                Label("AGENTS.md", systemImage: "doc.badge.gearshape").lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(TagLabelStyle())
            .motion(Motion.quick, value: model.activeNote?.rel)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: Bindable(model.agents).agentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(2...8)
                    .focused($inputFocused)
                    .accessibilityLabel("让 \(model.agents.agentPick.displayName) 修改当前笔记")
                    // Example requests take turns as the placeholder while the field is empty.
                    .overlay(alignment: .topLeading) {
                        if model.agents.agentInput.isEmpty {
                            RotatingPrompt(prompts: placeholderPrompts)
                                .font(.body)
                                .foregroundStyle(Color(nsColor: .placeholderTextColor))
                                .allowsHitTesting(false)
                        }
                    }
                    .onKeyPress(.return, phases: .down) { press in
                        // Return while an input method is composing picks the candidate; let it through.
                        if press.modifiers.contains(.shift) || imeComposing() { return .ignored }
                        send()
                        return .handled
                    }
                // While a run is going and nothing is typed, the same button becomes stop.
                let running = model.agents.sessions.first { $0.id == model.agents.activeSessionID }.map { $0.running && $0.source == .app } ?? false
                let empty = model.agents.agentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let stops = running && empty
                Button {
                    if stops, let s = model.agents.sessions.first(where: { $0.id == model.agents.activeSessionID }) { model.stopAgent(s) } else { send() }
                } label: {
                    Image(systemName: stops ? "stop.fill" : "arrow.up")
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityLabel(stops ? "停止" : "发送")
                }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(empty && !running)
                    .motion(Motion.quick, value: stops)
                    .help(stops ? "停止" : "发送 ↩ · 换行 ⇧↩")
            }
        }
        .padding(14)
        .floatingGlass(radius: Metrics.cardRadius + 4)
        .contentShape(.rect)
        .onTapGesture { inputFocused = true }
        .padding(Metrics.floatInset)
    }

    private var placeholderPrompts: [String] {
        let who = model.agents.agentPick.displayName
        guard model.editor.activeRel != nil else { return ["让 \(who) 在库里做点什么…"] }
        return ["让 \(who) 修改当前笔记…", "总结这篇笔记，在开头加一段摘要…", "整理待办，合并重复项…",
                "找出库里和这篇相关的笔记…", "把这一段改写得更清楚…"]
    }

    private func send() {
        model.runAgent(prompt: model.agents.agentInput, agent: model.agents.agentPick)
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
                let on = model.agents.agentPick == k
                Button {
                    withMotion(Motion.quick) { model.agents.agentPick = k }
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
        let kind = model.agents.agentPick
        return Button {
            model.refreshModels()
            model.chrome.modelPickerOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                if icon { Image(systemName: "cpu").imageScale(.small) }
                // When the panel is narrow the effort goes first, so the model name stays readable.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text(model.modelLabel(kind)).lineLimit(1).fixedSize()
                        if let e = model.effectiveEffort(kind) {
                            Text("· " + Effort.name(e)).lineLimit(1).fixedSize().foregroundStyle(.tertiary)
                        }
                    }
                    Text(model.modelLabel(kind)).lineLimit(1).fixedSize()
                    Text(model.modelLabel(kind)).lineLimit(1).truncationMode(.tail)
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
        .popover(isPresented: Bindable(model.chrome).modelPickerOpen, arrowEdge: .bottom) {
            ModelPicker(model: model, kind: kind)
        }
    }

    /// "" (CLI default), the known models, and the current choice if it's a custom id.
    static func options(_ model: AppModel, _ kind: AgentKind) -> [String] {
        var ids = [""] + model.models(kind).map(\.id)
        if let cur = model.prefs.agentModel[kind], !cur.isEmpty, !ids.contains(cur) { ids.append(cur) }
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
        let current = model.prefs.agentModel[kind] ?? ""
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
                            withMotion(Motion.quick) { showMore.toggle() }
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
        let on = (model.prefs.agentModel[kind] ?? "") == id
        return Button {
            model.prefs.agentModel[kind] = id
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
        let explicit = !(model.prefs.agentEffort[kind] ?? "").isEmpty
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("思考强度", systemImage: "brain").font(.callout.weight(.medium))
                Spacer()
                if let cur = model.effectiveEffort(kind) {
                    Text(Effort.name(cur) + (explicit ? "" : "（默认）"))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                if explicit {
                    Button("重置", systemImage: "arrow.counterclockwise") { model.prefs.agentEffort[kind] = "" }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                        .help("跟随 \(kind.executable) 的默认强度")
                }
            }
            if levels.count >= 2 {
                let index = Binding<Double>(
                    get: { Double(levels.firstIndex(of: model.effectiveEffort(kind) ?? "") ?? 0) },
                    set: { model.prefs.agentEffort[kind] = levels[min(max(Int($0.rounded()), 0), levels.count - 1)] })
                Slider(value: index, in: 0...Double(levels.count - 1), step: 1)
                    .labelsHidden()
                HStack(spacing: 0) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { i, l in
                        Button(Effort.name(l)) { model.prefs.agentEffort[kind] = l }
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
                ZStack {
                    if running {
                        GlyphSpinner(activity: GlyphSpinner.Activity(step: text), tint: Theme.agentColor(session.agent))
                            .transition(.blurReplace)
                    } else {
                        Image(systemName: Self.icon(text)).foregroundStyle(.tertiary)
                            .transition(.blurReplace)
                    }
                }
                .frame(width: 16)
                .motion(Motion.pop, value: running)
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
        case let .question(id):
            if let q = model.agents.questions[id] { QuestionCard(model: model, question: q) }
        case let .feedback(rel, message, sent):
            FeedbackCard(model: model, session: session, itemID: item.id, rel: rel, message: message, sent: sent)
        case let .pipeline(id):
            PipelineCard(model: model, runID: id)
        case let .change(rel, plus, minus):
            ChangeItem(model: model, rel: rel, plus: plus, minus: minus)
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
private struct QuestionCard: View {
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
                    .symbolEffect(.bounce, options: .nonRepeating, value: Motion.style == .lively)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
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
        // Answering folds the options into the answer.
        .motion(Motion.standard, value: question.answer != nil || question.expired)
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
                Button(expanded ? "收起" : "查看") { withMotion(Motion.quick) { expanded.toggle() } }
                    .buttonStyle(.borderless).font(.caption)
            }
            if expanded {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if sent {
                Label("已发回给 \(session.agent.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            } else {
                Button("把意见发回给 \(session.agent.displayName)", systemImage: "arrowshape.turn.up.left") {
                    model.sendFeedback(itemID, in: session)
                }
                .buttonStyle(.glassProminent)
                .disabled(session.running)
                .help("在这个会话里继续，让 \(session.agent.displayName) 根据你的审阅意见重新修改")
                .transition(.opacity)
            }
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .padding(12)
        .contentCard()
        .motion(Motion.standard, value: sent)
    }
}

/// A file the agent changed. While it waits for review it is a card with the review button;
/// once handled it folds down to one quiet line, so a long session doesn't fill up with
/// finished business.
private struct ChangeItem: View {
    @Bindable var model: AppModel
    let rel: String
    let plus: Int
    let minus: Int

    var body: some View {
        let pendingNow = model.agents.pending[rel] != nil
        let name = (rel as NSString).lastPathComponent
        Group {
            if pendingNow {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.clock")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).fontWeight(.medium).lineLimit(1)
                        HStack(spacing: 6) {
                            CountBadge(plus: plus, minus: minus)
                            Text("待审阅").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("审阅") {
                        model.open(rel)
                        model.editor.showDiff = true
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .padding(10)
                .contentCard()
                .transition(.blurReplace)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green.opacity(0.85))
                    Text(name).lineLimit(1).truncationMode(.middle)
                    CountBadge(plus: plus, minus: minus)
                    Spacer(minLength: 0)
                    if model.vault?.note(rel) != nil {
                        Button("打开") { model.open(rel) }
                            .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .overlay(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                .transition(.blurReplace)
            }
        }
        .motion(Motion.morph, value: pendingNow)
    }
}
