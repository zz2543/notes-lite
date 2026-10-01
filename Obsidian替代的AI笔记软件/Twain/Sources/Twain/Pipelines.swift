import AppKit
import SwiftUI
import TwainCore

/// One run of a pipeline: which step it is on and what it is waiting for.
struct PipelineRun: Identifiable, Equatable {
    enum Status: Equatable { case running, waitingReview, waitingUser, done, stopped(String) }
    let id = UUID()
    let pipeline: Pipeline
    let sessionID: UUID
    var step = 0
    var status = Status.running
    var vars: [String: String]
    /// What the agent said at the end of each finished step, for `{{prev}}` and `{{steps.N}}`.
    var outputs: [String] = []
    /// Session items before the current step started, to find what it said.
    var itemMark = 0
}

extension AppModel {
    static let defaultPipelines: [(String, String)] = [
        ("write.md", """
        ---
        title: 研究并写成文章
        agent: claude
        scope: vault
        icon: doc.text.magnifyingglass
        ---
        ## 调研
        gate: ask
        围绕「{{input}}」在库里找资料：先用 skim 看相关笔记的名片，再用 read_note 读真正相关的部分。
        列出 5 到 10 条要点，每条注明出处（笔记路径和行号），并指出资料里的空白和矛盾。不要写文章，不要改文件。

        ## 大纲
        gate: review
        根据上一步的要点（以及我在上一步给的意见）写一份文章大纲：标题、各节标题、每节一两句要点。
        用 propose_edit 新建笔记 写作/{{input}}.md 提交，只写大纲，正文留空。

        ## 分节写作
        gate: review
        读取 写作/{{input}}.md 当前的大纲（我可能改过），一节一节地写正文：写完一节就用 propose_edit 提交（wait=true），
        edits 里只替换那一节的要点，reason 写清依据来自哪些笔记；等我审阅完、看过我接受或拒绝的原因，再写下一节。
        保持我的语气，不要编造资料里没有的事实。
        """),
        ("inbox.md", """
        ---
        title: 整理收件箱
        agent: claude
        scope: vault
        icon: tray.and.arrow.down
        ---
        ## 分类建议
        gate: ask
        读收件箱（找标题含“收件箱”或 Inbox 的笔记），逐条判断应该归到哪篇笔记（用 skim 找候选）。
        以表格列出：条目 · 建议归入的笔记 · 理由。先不要改任何文件。

        ## 执行
        gate: review
        按上一步的建议（以我给的修改意见为准）把条目归档：对每篇目标笔记用 propose_edit 追加，对收件箱用 propose_edit 删掉已归档的条目。
        每处都写明理由。
        """),
        ("weekly.md", """
        ---
        title: 周回顾
        agent: claude
        scope: vault
        icon: calendar.badge.clock
        ---
        ## 收集
        gate: none
        用 twain 的 skim、tasks 和 reviews 了解我这一周（截至 {{date}}）写了什么、完成和未完成的待办、接受和拒绝过哪些改动。
        只整理事实，列成要点，不写结论。

        ## 回顾草稿
        gate: review
        根据上一步的事实写一篇周回顾：本周做成了什么、卡在哪里、下周最重要的三件事。
        用 propose_edit 新建笔记 日记/周回顾-{{date}}.md 提交。语气平实，每个判断都要能在上一步的事实里找到依据。
        """),
    ]

    func loadPipelines() {
        guard let v = vault else { agents.pipelines = []; return }
        let fm = FileManager.default
        let dir = v.root.appendingPathComponent(".twain/pipelines")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, text) in Self.defaultPipelines {
                try? (text + "\n").write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        agents.pipelines = files.compactMap { u in
            (try? String(contentsOf: u, encoding: .utf8)).flatMap { Pipeline.parse(file: v.relative(u.path), text: $0) }
        } + pluginFiles("pipelines").compactMap { Pipeline.parse(file: $0.0, text: $0.1) }
    }

    func pipeline(named name: String) -> Pipeline? {
        let n = name.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
        return agents.pipelines.first { $0.key.lowercased() == n || $0.title == name }
    }

    /// The template variables a command or pipeline sees, taken from the editor.
    func templateVars(scope: UserCommand.Scope, title: String, input: String?) throws -> [String: String] {
        let ns = editor.editorText as NSString
        let sel = NSIntersectionRange(editor.editorSelection, NSRange(location: 0, length: ns.length))
        let selected = editor.activeRel == nil ? "" : ns.substring(with: sel)
        if scope != .vault, editor.activeRel == nil { throw RPCError(RPCError.invalidParams, "「\(title)」需要先打开一篇笔记") }
        if scope == .selection, selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RPCError(RPCError.invalidParams, "「\(title)」需要先在笔记里选中一段文字")
        }
        let rel = editor.activeRel ?? ""
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return ["selection": selected, "note": editor.editorText, "path": rel,
                "title": ((rel as NSString).lastPathComponent as NSString).deletingPathExtension,
                "line": String(EditorContext.position(sel.location, in: ns).line),
                "date": f.string(from: Date()), "input": input ?? ""]
    }

    /// Starts `p`. When it needs `{{input}}` and none was given, asks for it first.
    @discardableResult
    func runPipeline(_ p: Pipeline, input: String? = nil, model: String? = nil) throws -> AgentSession? {
        var p = p
        if let model { p.model = model; for i in p.steps.indices { p.steps[i].model = model } }
        var input = input
        if p.needsInput, (input ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            guard let typed = Self.promptForInput(title: p.title, message: "这个流水线需要一个主题或输入：") else { return nil }
            input = typed
        }
        let vars = try templateVars(scope: p.scope, title: p.title, input: input)
        flushSave()
        let s = AgentSession(agent: p.agent, source: .app, title: "流水线 · " + p.title)
        s.extraTools = p.tools
        agents.sessions.append(s)
        agents.activeSessionID = s.id
        var run = PipelineRun(pipeline: p, sessionID: s.id, vars: vars)
        run.itemMark = 1
        agents.pipelineRuns[run.id] = run
        s.items.append(SessionItem(kind: .pipeline(run.id)))
        startPipelineStep(run.id)
        return s
    }

    private func startPipelineStep(_ id: UUID) {
        guard var run = agents.pipelineRuns[id], let s = agents.sessions.first(where: { $0.id == run.sessionID }) else { return }
        let step = run.pipeline.steps[run.step]
        var vars = run.vars
        vars["prev"] = run.outputs.last ?? ""
        for (i, o) in run.outputs.enumerated() { vars["steps.\(i + 1)"] = o }
        let header = "（流水线「\(run.pipeline.title)」第 \(run.step + 1)/\(run.pipeline.steps.count) 步：\(step.title)）\n"
        run.status = .running
        run.itemMark = s.items.count
        agents.pipelineRuns[id] = run
        runAgent(prompt: header + Template.render(step.prompt, vars), agent: run.pipeline.agent,
                 model: step.model ?? run.pipeline.model, effort: step.effort, in: s)
    }

    /// Called when a run of `s` has finished and its changes are queued.
    func pipelineSessionFinished(_ s: AgentSession) {
        guard let (id, run) = agents.pipelineRuns.first(where: { $0.value.sessionID == s.id && $0.value.status == .running }) else { return }
        var r = run
        let said = s.items.dropFirst(r.itemMark).compactMap { item -> String? in
            if case let .agent(t) = item.kind { return t }
            return nil
        }
        let failed = s.items.dropFirst(r.itemMark).contains { if case .error = $0.kind { return true }; return false }
        if failed && said.isEmpty {
            r.status = .stopped("第 \(r.step + 1) 步出错，流水线已停下")
            agents.pipelineRuns[id] = r
            return
        }
        r.outputs.append(said.last ?? "")
        switch r.pipeline.steps[r.step].gate {
        case .none:
            agents.pipelineRuns[id] = r
            advancePipeline(id)
        case .ask:
            r.status = .waitingUser
            agents.pipelineRuns[id] = r
            NSApp.requestUserAttention(.informationalRequest)
        case .review:
            r.status = .waitingReview
            agents.pipelineRuns[id] = r
            pipelineReviewsChanged()
        }
    }

    /// Moves every run waiting on reviews forward once its session has none left.
    func pipelineReviewsChanged() {
        for (id, run) in agents.pipelineRuns where run.status == .waitingReview {
            if !agents.pending.values.contains(where: { $0.sessionID == run.sessionID }) { advancePipeline(id) }
        }
    }

    func advancePipeline(_ id: UUID) {
        guard var run = agents.pipelineRuns[id] else { return }
        run.step += 1
        if run.step >= run.pipeline.steps.count {
            run.status = .done
            agents.pipelineRuns[id] = run
            showToast("流水线「\(run.pipeline.title)」完成")
            return
        }
        agents.pipelineRuns[id] = run
        startPipelineStep(id)
    }

    /// Runs the current step again with the user's opinion of its result.
    func redoPipelineStep(_ id: UUID, feedback: String) {
        guard var run = agents.pipelineRuns[id], let s = agents.sessions.first(where: { $0.id == run.sessionID }), !s.running else { return }
        if !run.outputs.isEmpty { run.outputs.removeLast() }
        run.status = .running
        run.itemMark = s.items.count
        agents.pipelineRuns[id] = run
        let step = run.pipeline.steps[run.step]
        runAgent(prompt: "对第 \(run.step + 1) 步「\(step.title)」的结果，我的意见是：\(feedback)\n请按意见重做这一步，要求和之前一样。",
                 agent: run.pipeline.agent, model: step.model ?? run.pipeline.model, effort: step.effort, in: s)
    }

    func stopPipeline(_ id: UUID) {
        guard var run = agents.pipelineRuns[id] else { return }
        if let s = agents.sessions.first(where: { $0.id == run.sessionID }), s.running { stopAgent(s) }
        run.status = .stopped("已停止")
        agents.pipelineRuns[id] = run
    }

    static func promptForInput(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "开始")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let t = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// The pipeline's progress in its session, and the gate where the user decides.
struct PipelineCard: View {
    @Bindable var model: AppModel
    let runID: UUID
    @State private var feedback = ""

    var body: some View {
        if let run = model.agents.pipelineRuns[runID] {
            VStack(alignment: .leading, spacing: 10) {
                Label(run.pipeline.title, systemImage: run.pipeline.icon).font(.callout.weight(.semibold))
                PipelineTrack(run: run)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(run.pipeline.steps.enumerated()), id: \.offset) { i, step in
                        HStack(spacing: 8) {
                            stateIcon(i, run).frame(width: 16)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                                .id("\(i)-\(Self.iconKey(i, run))")
                            // Finished steps recede; the current one stays in front.
                            Text("\(i + 1). \(step.title)").font(.callout)
                                .foregroundStyle(i == run.step && run.status != .done ? AnyShapeStyle(.primary)
                                                 : i < run.step || run.status == .done ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                            Spacer(minLength: 0)
                            Text(Self.gateLabel(step.gate)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                gate(run)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .id(Self.gateKey(run.status))
            }
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .padding(12)
            .contentCard()
            .motion(Motion.pop, value: "\(run.step)-\(Self.gateKey(run.status))")
        }
    }

    @ViewBuilder
    private func stateIcon(_ i: Int, _ run: PipelineRun) -> some View {
        if i < run.step || run.status == .done {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if i == run.step {
            switch run.status {
            case .running: GlyphSpinner(activity: .think)
            case .waitingReview, .waitingUser: Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            case .stopped: Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func gate(_ run: PipelineRun) -> some View {
        switch run.status {
        case .waitingUser:
            VStack(alignment: .leading, spacing: 6) {
                Text("第 \(run.step + 1) 步完成。看看上面的结果，决定下一步：").font(.caption).foregroundStyle(.secondary)
                TextField("有意见就写在这里，按意见重做这一步…", text: $feedback, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...4).padding(8)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 8, style: .continuous))
                HStack {
                    Button("继续下一步", systemImage: "arrow.right") {
                        if var r = model.agents.pipelineRuns[runID], !feedback.isEmpty {
                            // The opinion carries into the next step as part of {{prev}}.
                            r.outputs[r.outputs.count - 1] += "\n\n（用户的意见：\(feedback)）"
                            model.agents.pipelineRuns[runID] = r
                        }
                        feedback = ""
                        model.advancePipeline(runID)
                    }
                    .buttonStyle(.solid)
                    Button("按意见重做", systemImage: "arrow.counterclockwise") {
                        model.redoPipelineStep(runID, feedback: feedback)
                        feedback = ""
                    }
                    .buttonStyle(.soft).disabled(feedback.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("停止") { model.stopPipeline(runID) }.buttonStyle(.soft)
                }
            }
        case .waitingReview:
            let n = model.agents.pending.values.filter { $0.sessionID == run.sessionID }.reduce(0) { $0 + $1.hunks.count }
            HStack {
                Text("等你审阅第 \(run.step + 1) 步的 \(n) 处改动，审阅完自动进入下一步").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("审阅") { model.reviewNext() }.buttonStyle(.solid)
                Button("停止") { model.stopPipeline(runID) }.buttonStyle(.soft)
            }
        case let .stopped(why):
            Text(why).font(.caption).foregroundStyle(.secondary)
        case .done:
            Label("全部完成", systemImage: "checkmark.seal").font(.caption).foregroundStyle(.green)
        case .running:
            Button("停止") { model.stopPipeline(runID) }.buttonStyle(.soft)
        }
    }

    /// What a step's icon shows, so a change of icon can transition.
    static func iconKey(_ i: Int, _ run: PipelineRun) -> String {
        i < run.step || run.status == .done ? "done" : i == run.step ? gateKey(run.status) : "todo"
    }

    static func gateKey(_ s: PipelineRun.Status) -> String {
        switch s {
        case .running: "running"
        case .waitingReview: "review"
        case .waitingUser: "user"
        case .stopped: "stopped"
        case .done: "done"
        }
    }

    static func gateLabel(_ g: Pipeline.Gate) -> String {
        switch g {
        case .review: "审阅后继续"
        case .ask: "你决定后继续"
        case .none: "自动继续"
        }
    }
}

/// One segment per step: finished ones filled, the current one filling while it runs, and
/// held still in orange while it waits for you. Under 活泼 the waiting segment's line ripples
/// like a held breath, so the card says "paused" without reading a word.
private struct PipelineTrack: View {
    let run: PipelineRun

    var body: some View {
        HStack(spacing: 4) {
            ForEach(run.pipeline.steps.indices, id: \.self) { i in
                segment(i)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 10)
        .motion(Motion.content, value: "\(run.step)-\(PipelineCard.gateKey(run.status))")
        .accessibilityLabel("第 \(min(run.step + 1, run.pipeline.steps.count)) 步，共 \(run.pipeline.steps.count) 步")
    }

    @ViewBuilder private func segment(_ i: Int) -> some View {
        let done = i < run.step || run.status == .done
        let current = i == run.step && run.status != .done
        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)
            if done {
                Capsule().fill(.green.opacity(0.8)).transition(.opacity)
            } else if current {
                switch run.status {
                case .running:
                    RunningFill()
                case .waitingUser, .waitingReview:
                    if Motion.style == .lively && !Motion.reduce {
                        Ripple().transition(.opacity)
                    } else {
                        LayerCapsule(color: .systemOrange.withAlphaComponent(0.85), motion: Motion.ambient ? .pulse : .none)
                            .transition(.opacity)
                    }
                case .stopped:
                    Capsule().fill(.secondary.opacity(0.5))
                case .done:
                    EmptyView()
                }
            }
        }
    }

    /// The running step fills and drains slowly; nothing tells how long it will take.
    private struct RunningFill: View {
        var body: some View {
            if Motion.ambient {
                LayerCapsule(color: .controlAccentColor, motion: .breathe)
            } else {
                Capsule().fill(.tint).scaleEffect(x: 0.5, anchor: .leading)
            }
        }
    }

    /// The waiting step's line drawn as a slow sine wave. It ripples for a few seconds and then
    /// holds still: a run can wait for you for hours, and a 30 fps redraw that long costs battery.
    private struct Ripple: View {
        @State private var settled = false

        var body: some View {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: settled)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Canvas { g, size in
                    var p = Path()
                    let mid = size.height / 2
                    for x in stride(from: 0.0, through: size.width, by: 1.5) {
                        let env = sin(.pi * x / max(size.width, 1))
                        let y = mid + sin(x * 0.45 + t * 5) * 2.2 * env
                        if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    g.stroke(p, with: .color(.orange), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
            }
            .frame(height: 10)
            .task {
                try? await Task.sleep(for: .seconds(8))
                settled = true
            }
        }
    }
}
