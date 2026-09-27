import AppKit
import Observation
import TwainCore
import SwiftUI

/// Agent runs: launching CLIs, applying what they wrote, the review queue and terminal sessions.
extension AppModel {
    // MARK: agents

    var activeSession: AgentSession? {
        sessions.first { $0.id == activeSessionID } ?? sessions.first
    }

    func agentEnabled(_ k: AgentKind) -> Bool { k == .claude ? claudeOn : codexOn }

    /// Re-reads each CLI's model list and defaults off the main thread.
    func refreshModels() {
        DispatchQueue.global(qos: .userInitiated).async {
            let models = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, CLIEnvironment.models($0)) })
            DispatchQueue.main.async {
                let choices = models.mapValues(\.choices)
                if choices != self.modelChoices { self.modelChoices = choices }
                self.modelFallback = models.compactMapValues(\.fallback)
                self.effortFallback = models.compactMapValues(\.fallbackEffort)
                self.modelsListedBy = models.compactMapValues(\.listedBy)
            }
        }
    }

    func models(_ k: AgentKind) -> [AgentModel] { modelChoices[k] ?? k.builtinModels }

    /// Set when the model list came from a newer client than the CLI Twain runs, e.g. the Codex app.
    func staleCLIWarning(_ k: AgentKind) -> String? {
        guard let listed = modelsListedBy[k], let cliVersion = cli[k]?.version,
              versionIsOlder(cliVersion, than: listed) else { return nil }
        return "模型列表来自 \(k.displayName) \(listed)，而共笔调用的 \(cliVersion) 较旧，新模型可能无法运行。升级 \(k.executable) 命令行后即可使用。"
    }

    /// Human name for a model id; "" is the CLI default.
    func modelName(_ id: String, for k: AgentKind) -> String {
        if id.isEmpty { return modelFallback[k].map { "默认（\(modelName($0, for: k))）" } ?? "默认" }
        return models(k).find(id)?.name ?? id
    }

    /// The name of the model the next run uses, without the "默认（…）" wrapper.
    func modelLabel(_ k: AgentKind) -> String {
        let id = agentModel[k] ?? ""
        if id.isEmpty, let f = modelFallback[k] { return modelName(f, for: k) }
        return modelName(id, for: k)
    }

    /// The model the next run of `k` uses, if it's one we know.
    func currentModel(_ k: AgentKind) -> AgentModel? {
        let id = agentModel[k] ?? ""
        return models(k).find(id.isEmpty ? modelFallback[k] ?? "" : id)
    }

    /// Thinking levels the next run's model offers. Unknown model: the common levels.
    func effortLevels(_ k: AgentKind) -> [String] {
        currentModel(k)?.efforts ?? ["low", "medium", "high", "xhigh", "max"]
    }

    /// The level Twain passes on the command line: the user's pick, fitted to the model; "" to leave it to the CLI.
    func effortArgument(_ k: AgentKind) -> String {
        let pick = agentEffort[k] ?? ""
        guard !pick.isEmpty else { return "" }
        return Effort.clamp(pick, to: effortLevels(k)) ?? ""
    }

    /// The level the next run actually thinks at, as far as we can tell.
    func effectiveEffort(_ k: AgentKind) -> String? {
        let levels = effortLevels(k)
        guard !levels.isEmpty else { return nil }
        let arg = effortArgument(k)
        if !arg.isEmpty { return arg }
        if let f = effortFallback[k] { return Effort.clamp(f, to: levels) }
        return currentModel(k)?.defaultEffort
    }

    /// Starts a run the user asked for. `target` continues that session (sending review feedback
    /// back, say); otherwise the active session is reused when it fits, or a new one begins.
    func runAgent(prompt: String, agent: AgentKind, model: String? = nil, effort: String? = nil, in target: AgentSession? = nil) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, vault != nil else { return }
        var session = target ?? activeSession
        if let t = target, t.running {
            showToast("\(t.agent.displayName) 还在运行，等它结束再发送")
            return
        }
        if target == nil, session == nil || session!.source != .app || session!.agent != agent || session!.running {
            let s = AgentSession(agent: agent, source: .app, title: String(prompt.prefix(10)))
            sessions.append(s)
            session = s
        }
        let s = session!
        if s.title == "新会话" { s.title = String(prompt.prefix(10)) }
        activeSessionID = s.id
        if zen { toggleZen() }
        agentPanel = true
        agentInput = ""
        launch(s, prompt: prompt, model: model, effort: effort)
    }

    /// Runs `prompt` in `s`, resuming the CLI's own session when there is one. Automation
    /// sessions run read-only: their only way to change a note is a proposal.
    @discardableResult
    func launch(_ s: AgentSession, prompt: String, model: String? = nil, effort: String? = nil) -> Bool {
        let agent = s.agent
        guard let v = vault else { return false }
        guard agentEnabled(agent) else { showToast(agent.displayName + " 已在设置中停用"); return false }
        guard let exe = cli[agent]?.path ?? CLIEnvironment.locate(agent.executable) else {
            showToast("没有找到 " + agent.executable + " 命令")
            return false
        }
        flushSave()
        clearGhost()
        s.items.append(SessionItem(kind: .user(prompt)))
        s.running = true
        let model = model ?? agentModel[agent] ?? ""
        let effort = effort ?? effortArgument(agent)
        s.model = model.isEmpty ? modelFallback[agent] : model
        s.effort = effort.isEmpty ? effectiveEffort(agent) : effort
        let readOnly = s.source == .automation || s.readOnly

        let proc = AgentProcess(kind: agent)
        s.process = proc
        let root = v.root, rels = v.notes.map(\.rel), takeGit = gitSnapshot && !readOnly
        // The snapshot reads every note (and may commit to git): never on the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let git = takeGit ? Git.snapshot(root, message: "Twain: snapshot before \(agent.displayName)") : nil
            let snap = VaultSnapshot.take(root: root, rels: rels)
            DispatchQueue.main.async {
                guard let self, s.process === proc, s.running else { return }
                self.runSnapshots[s.id] = (snap, git)
                self.start(s, proc: proc, exe: exe, prompt: prompt, model: model, effort: effort, readOnly: readOnly)
            }
        }
        return true
    }

    func start(_ s: AgentSession, proc: AgentProcess, exe: String, prompt: String, model: String, effort: String, readOnly: Bool) {
        guard let v = vault else { return }
        let agent = s.agent
        let tool = TwainTool.prepare()
        var env = ["TWAIN_SESSION": s.id.uuidString]
        if !s.extraTools.isEmpty { env["TWAIN_MCP_EXTRA"] = s.extraTools.joined(separator: ",") }
        if let tool { env["PATH"] = tool.path }
        if let server { env["TWAIN_SOCK"] = server.path }
        let mcp: AgentArguments.MCP? = mcpOn && tool != nil
            ? AgentArguments.MCP(command: TwainTool.managedLink.path, env: env.filter { $0.key != "PATH" }) : nil
        // Claude Code gives up on a tool call after its own default; questions may wait longer.
        if mcp != nil { env["MCP_TOOL_TIMEOUT"] = "900000" }
        let context = agentContext(tool: tool != nil, mcp: mcp != nil, readOnly: readOnly)
        let args = AgentArguments.build(kind: agent, prompt: prompt, context: context, root: v.rootPath,
                                        resume: s.cliSessionID, model: model, effort: effort, socket: server?.path,
                                        version: cli[agent]?.version, mcp: mcp, readOnly: readOnly)
        emit("session.started", source: eventSource(for: s), ["session": .string(s.id.uuidString), "agent": .string(agent.rawValue)])
        do {
            try proc.start(executable: exe, arguments: args, cwd: v.root, env: env, onEvents: { [weak self, weak s] events in
                guard let self, let s else { return }
                for w in s.apply(events) {
                    let rel = v.relative(w)
                    self.writing.insert(rel)
                }
            }, onExit: { [weak self, weak s] status, stderr, sawFinish in
                guard let self, let s else { return }
                if status != 0 && !sawFinish {
                    let msg = stderr.split(separator: "\n").suffix(3).joined(separator: "\n")
                    s.items.append(SessionItem(kind: .error(msg.isEmpty ? "\(agent.executable) 退出，状态码 \(status)" : msg)))
                }
                s.settleSteps()
                s.running = false
                s.process = nil
                self.finishRun(s)
                self.emit("session.finished", source: self.eventSource(for: s),
                          ["session": .string(s.id.uuidString), "agent": .string(agent.rawValue), "status": JSONValue(Int(status))])
            })
        } catch {
            s.items.append(SessionItem(kind: .error("无法启动 \(exe)：\(error.localizedDescription)")))
            s.running = false
            s.process = nil
            runSnapshots[s.id] = nil
        }
    }

    /// What every run is told about Twain, beyond the user's prompt.
    func agentContext(tool: Bool, mcp: Bool, readOnly: Bool) -> String {
        let noteRel = activeRel ?? ""
        var parts = ["你在共笔笔记库中工作，当前目录就是库的根目录，库里的笔记都是 Markdown 文件。"]
        if !noteRel.isEmpty, !readOnly { parts.append("用户当前打开的笔记是 \(noteRel)，“这篇笔记”“当前笔记”指的就是它。") }
        if mcp {
            parts.append("共笔提供了一组工具（twain 服务器）：context 查看用户选中的文字和光标所在标题；"
                + "找资料时先用 skim 看笔记名片（标题、标签、一句话摘要），看准了再用 read_note 按层级读（1 名片、2 提纲、3 正文或某一节），不要一上来就通读全库；"
                + "search、backlinks、tasks 查询笔记库；propose_edit 提交修改，改动进入用户的逐段审阅，每处都要写明理由；ask_user 在拿不准时直接问用户；open 把笔记打开给用户看。")
        } else if tool {
            parts.append("可以运行 `twain` 命令：`twain context` 查看用户选中的文字和光标位置，`twain skim` 先看笔记名片、`twain read <笔记> --level 2` 按层级读，"
                + "`twain search`、`twain backlinks`、`twain tasks` 查询笔记库，"
                + "`twain propose <笔记> --content - --reason 理由` 提交修改供用户审阅，`twain ask \"问题\"` 向用户提问；`twain help` 列出全部命令。")
        }
        if readOnly {
            parts.append("这是自动化任务，你不能直接修改文件：所有修改都必须用 propose_edit（或 twain propose）提交，逐处写明理由，由用户审阅。")
        } else {
            parts.append(mcp || tool ? "修改笔记优先用 propose_edit 提交；也可以直接修改文件，共笔会把改动交给用户审阅。"
                                     : "直接修改文件即可，共笔会把改动交给用户审阅。")
        }
        parts.append("遵守 AGENTS.md 中的约定。")
        if let r = spaceRules(for: activeRel) { parts.append("\n这篇笔记属于空间「\(r.name)」，另外遵守它的约定：\n" + r.rules) }
        return parts.joined()
    }

    func stopAgent(_ s: AgentSession) {
        guard let p = s.process else { return }
        if p.pid == 0 {
            // Still taking the snapshot: the CLI never started.
            s.process = nil
            s.running = false
            s.items.append(SessionItem(kind: .error("已停止")))
        } else {
            p.stop()
        }
    }

    #if DEBUG
    /// Mimics an agent run without calling a CLI: snapshot, write to disk, finish.
    func debugSimulateRun(rel: String, append: String) {
        guard let v = vault else { return }
        let s = AgentSession(agent: .claude, source: .app, title: "模拟")
        sessions.append(s)
        activeSessionID = s.id
        s.running = true
        runSnapshots[s.id] = (v.snapshotAll(), nil)
        writing.insert(rel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? ((v.diskContent(rel) ?? "") + append).write(to: v.url(rel), atomically: true, encoding: .utf8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                s.running = false
                self.finishRun(s)
            }
        }
    }
    #endif

    /// Compares the vault with the snapshot taken before the run and queues each changed file.
    func finishRun(_ s: AgentSession) {
        guard let snap = runSnapshots.removeValue(forKey: s.id) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let changes = snap.snap.changes()
            DispatchQueue.main.async { self?.applyRun(s, changes: changes, git: snap.git) }
        }
    }

    func applyRun(_ s: AgentSession, changes: [(rel: String, before: String?, after: String?)], git: String?) {
        guard let v = vault else { return }
        v.scan()
        var changed: [String] = []
        for c in changes {
            // Skip files that only Twain itself saved during the run.
            guard let after = c.after, after != v.knownContent(c.rel) else { continue }
            changed.append(c.rel)
            let base = pending[c.rel]?.baseline ?? Markdown.lines(v.knownContent(c.rel) ?? c.before ?? "")
            queueReview(rel: c.rel, baseline: base, proposed: after, by: s.agent, source: s.source, snapshot: git, session: s)
            emit("note.changed", source: eventSource(for: s), ["path": .string(c.rel)])
        }
        for rel in writing where !changed.contains(rel) { v.acknowledge(rel, content: v.diskContent(rel)) }
        writing.removeAll()
        if let rel = activeRel, changed.contains(rel) || dirty == false {
            reloadActiveFromDisk()
        }
        if let first = changed.first {
            let name = (first as NSString).lastPathComponent
            let more = changed.count > 1 ? " 等 \(changed.count) 个文件" : ""
            let auto = reviewMode == .auto && s.source != .automation
            showToast(auto ? "\(s.agent.displayName) 已写入 \(name)\(more)" : "\(s.agent.displayName) 修改了 \(name)\(more) · 待审阅")
        }
        pipelineSessionFinished(s)
    }

    func queueReview(rel: String, baseline: [String], proposed: String, by: AgentKind?,
                             source: SessionSource, snapshot: String?, session: AgentSession?) {
        guard let v = vault else { return }
        v.acknowledge(rel, content: proposed)
        let after = Markdown.lines(proposed)
        let hunks = LineDiff.hunks(from: baseline, to: after)
        let counts = hunks.map { LineDiff.counts($0, base: baseline) }
        let plus = counts.reduce(0) { $0 + $1.plus }, minus = counts.reduce(0) { $0 + $1.minus }
        let item = SessionItem(kind: .change(rel: rel, plus: plus, minus: minus))
        if let session {
            if session.source == .terminal { session.changeItems.append(item) }
            session.items.append(item)
        }
        // A proposal for this note no longer matches the file the agent just wrote.
        if let old = pending[rel], old.isProposal { markStale(old) }
        if hunks.isEmpty || (reviewMode == .auto && session?.source != .automation) {
            pending[rel] = nil
            return
        }
        pending[rel] = PendingReview(rel: rel, by: by, source: source, baseline: baseline, proposed: after,
                                     hunks: hunks, snapshot: snapshot, sessionID: session?.id)
    }

    func reloadActiveFromDisk() {
        guard let v = vault, let rel = activeRel else { return }
        let disk = v.read(rel)
        if disk != editorText {
            editorText = disk
            editorVersion += 1
        }
        dirty = false
    }

    /// Changes that did not come from Twain's own writes.
    func filesChanged(_ rels: [String]) {
        guard let v = vault else { return }
        let appRunning = sessions.contains { $0.source == .app && $0.running }
        var outside: [String] = []
        for rel in rels {
            let disk = v.diskContent(rel)
            if disk == v.knownContent(rel) { continue }
            if rel == activeRel, dirty, !appRunning {
                // Unsaved edits meet an outside write: the save path turns it into a review.
                flushSave()
                continue
            }
            if appRunning {
                writing.insert(rel)
                continue
            }
            outside.append(rel)
        }
        guard !outside.isEmpty else { return }
        // Who wrote it? Only a terminal agent whose transcript shows the write gets the credit;
        // anything else (another editor, sync) is loaded as is, without a review.
        let root = v.rootPath
        let terminals = watchTerminal ? sessions.filter { $0.source == .terminal && $0.alive }.compactMap { s in
            s.transcript.map { (id: s.id, url: $0, agent: s.agent) }
        } : []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var writer: [String: UUID] = [:]
            for t in terminals {
                let recent = TerminalWatcher.recentWrites(transcript: t.url, agent: t.agent, root: root)
                for rel in outside where writer[rel] == nil {
                    let abs = (root as NSString).appendingPathComponent(rel)
                    let name = (rel as NSString).lastPathComponent
                    if recent.paths.contains(abs) || recent.paths.contains(rel) || recent.steps.contains(where: { $0.contains(name) }) {
                        writer[rel] = t.id
                    }
                }
            }
            DispatchQueue.main.async { self?.applyOutsideChanges(outside, writer: writer) }
        }
    }

    func applyOutsideChanges(_ rels: [String], writer: [String: UUID]) {
        guard let v = vault else { return }
        var reloaded: [String] = []
        for rel in rels {
            let disk = v.diskContent(rel)
            if disk == v.knownContent(rel) { continue }
            let term = writer[rel].flatMap { id in sessions.first { $0.id == id } }
            emit(disk == nil ? "note.deleted" : "note.changed", source: term.map(eventSource) ?? "external", ["path": .string(rel)])
            guard let disk else {
                v.acknowledge(rel, content: nil)
                pending[rel] = nil
                if rel == activeRel, let next = v.notes.first { open(next.rel) }
                continue
            }
            if let term {
                let base = pending[rel]?.baseline ?? Markdown.lines(v.knownContent(rel) ?? "")
                queueReview(rel: rel, baseline: base, proposed: disk, by: term.agent, source: .terminal, snapshot: nil, session: term)
                if pending[rel] != nil {
                    showToast("\(term.agent.displayName) 在终端中修改了 \((rel as NSString).lastPathComponent) · 待审阅")
                }
            } else {
                v.acknowledge(rel, content: disk)
                reloaded.append(rel)
            }
            if rel == activeRel {
                if dirty { flushSave() } else { reloadActiveFromDisk() }
            }
        }
        if reloaded.contains(where: { $0 == activeRel }) {
            showToast("「\(((activeRel ?? "") as NSString).lastPathComponent)」在其他程序中被修改，已载入新内容")
        }
    }

    // MARK: review

    var activePending: PendingReview? { activeRel.flatMap { pending[$0] } }

    func setHunk(_ i: Int, _ state: HunkState) {
        guard let rel = activeRel, var p = pending[rel], p.hunks.indices.contains(i) else { return }
        p.hunks[i].state = state
        pending[rel] = p
    }

    // MARK: terminal sessions

    func dropTerminalSessions() {
        sessions.removeAll { $0.source == .terminal }
        if activeSession == nil { activeSessionID = sessions.first?.id }
    }

    func pollTerminal() {
        guard watchTerminal, let v = vault else { return }
        let root = v.rootPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = TerminalWatcher.scan(root: root)
            let transcripts = found.map { f in
                (f, f.agent == .claude ? TerminalWatcher.claudeTranscript(cwd: f.cwd) : TerminalWatcher.codexTranscript(cwd: f.cwd))
            }
            var parsed: [Int32: (URL, Date, [AgentEvent])] = [:]
            let known = DispatchQueue.main.sync { [weak self] in
                Dictionary(uniqueKeysWithValues: (self?.sessions ?? []).compactMap { s in s.pid.map { ($0, s.transcriptStamp) } })
            }
            for (f, u) in transcripts {
                guard let u, let m = TerminalWatcher.modified(u) else { continue }
                if let stamp = known[f.pid], stamp == m { continue }
                parsed[f.pid] = (u, m, TerminalWatcher.events(transcript: u, agent: f.agent, root: root))
            }
            DispatchQueue.main.async { self?.applyTerminalScan(found, parsed) }
        }
    }

    func applyTerminalScan(_ found: [TerminalWatcher.Found], _ parsed: [Int32: (URL, Date, [AgentEvent])]) {
        let pids = Set(found.map(\.pid))
        for s in sessions where s.source == .terminal {
            s.alive = s.pid.map(pids.contains) ?? false
            s.running = s.alive && Date().timeIntervalSince(s.lastActivity) < 15
        }
        for f in found where !sessions.contains(where: { $0.pid == f.pid }) {
            let s = AgentSession(agent: f.agent, source: .terminal, title: "终端会话")
            s.pid = f.pid
            sessions.insert(s, at: 0)
            if activeSessionID == nil { activeSessionID = s.id }
        }
        for (pid, (u, stamp, events)) in parsed {
            guard let s = sessions.first(where: { $0.pid == pid }) else { continue }
            s.transcript = u
            s.transcriptStamp = stamp
            s.items = []
            s.title = "终端会话"
            s.apply(events)
            s.settleSteps()
            s.items += s.changeItems
            if let firstUser = s.items.first(where: { if case .user = $0.kind { return true }; return false }),
               case let .user(t) = firstUser.kind {
                s.title = String(t.prefix(10))
            }
        }
        // Forget terminal sessions that ended and never touched the vault.
        sessions.removeAll { $0.source == .terminal && !$0.alive && $0.changeItems.isEmpty && $0.id != activeSessionID }
    }

    func newSession() {
        let s = AgentSession(agent: agentPick, source: .app, title: "新会话")
        sessions.append(s)
        activeSessionID = s.id
    }
}
