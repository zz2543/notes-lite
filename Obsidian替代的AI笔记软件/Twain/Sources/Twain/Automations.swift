import Foundation
import TwainCore

// MARK: - Events

extension AppModel {
    /// Who caused an event, as `twain watch` and automations see it.
    func eventSource(for s: AgentSession) -> String {
        if let a = s.automationID { return "automation:" + a }
        return (s.source == .terminal ? "terminal:" : "agent:") + s.id.uuidString
    }

    /// Tells `twain watch` clients and automations that something happened.
    func emit(_ type: String, source: String, _ data: [String: JSONValue] = [:]) {
        var payload = data
        payload["type"] = .string(type)
        payload["source"] = .string(source)
        payload["time"] = .string(ISO8601DateFormatter().string(from: Date()))
        if !subscribers.isEmpty {
            var line = JSONValue.object(["jsonrpc": "2.0", "method": "event", "params": .object(payload)]).encoded()
            line.append(0x0A)
            for sub in subscribers.values where sub.events?.contains(type) ?? !TwainEvents.optIn.contains(type) {
                sub.send(line)
            }
        }
        automationEvent(type, source: source, path: data["path"]?.string)
    }

    /// `watch`: keeps the connection and sends every matching event down it until the client leaves.
    func watch(_ call: CommandCall, reply: @escaping AppCommand.Reply) {
        guard let conn = call.connection else {
            reply(.failure(RPCError(RPCError.invalidRequest, "watch 只能通过 twain 命令使用")))
            return
        }
        let wanted = (call.params["events"]?.array?.compactMap(\.string)).map(Set.init)
        if let unknown = wanted?.subtracting(TwainEvents.names), !unknown.isEmpty {
            reply(.failure(RPCError(RPCError.invalidParams, "没有这些事件：\(unknown.sorted().joined(separator: "、"))；可用的有："
                + TwainEvents.names.joined(separator: "、"))))
            return
        }
        let id = UUID()
        reply(.success(["watching": JSONValue((wanted.map(Array.init) ?? TwainEvents.names.filter { !TwainEvents.optIn.contains($0) }).sorted())]))
        subscribers[id] = (wanted, { conn.send($0) })
        conn.onClose { [weak self] in self?.subscribers[id] = nil }
    }

    /// Reports the selection to those who asked for it, once it has held still for half a second.
    func selectionChanged() {
        guard subscribers.values.contains(where: { $0.events?.contains("selection.changed") == true }) else { return }
        selectionEventWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let rel = self.activeRel else { return }
            let c = EditorContext.describe(text: self.editorText, selection: self.editorSelection)
            self.emit("selection.changed", source: "user", ["path": .string(rel), "cursor": c["cursor"] ?? .null,
                                                            "selection": c["selection"] ?? .null])
        }
        selectionEventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

// MARK: - Vault commands and automations

extension AppModel {
    /// Written into `.twain/commands/` the first time a vault opens, replacing the prompts that
    /// used to be built into the slash menu and ⌘K. Users edit or delete them like any file.
    static let defaultCommands: [(String, String)] = [
        ("summarize.md", """
        ---
        title: 让 Claude Code 总结当前笔记
        agent: claude
        scope: note
        icon: text.append
        ---
        总结这篇笔记（{{path}}），在开头加一段摘要。
        """),
        ("continue.md", """
        ---
        title: 让 Claude Code 续写
        agent: claude
        scope: note
        icon: text.cursor
        ---
        根据上下文续写这篇笔记（{{path}}），从光标所在的位置接着写，保持我的语气。
        """),
        ("todos.md", """
        ---
        title: 让 Codex 整理当前笔记的待办
        agent: codex
        scope: note
        icon: checklist
        ---
        整理这篇笔记（{{path}}）的待办，合并重复项。
        """),
        ("polish.md", """
        ---
        title: 润色选中段落
        agent: claude
        scope: selection
        icon: wand.and.stars
        ---
        把我在 {{path}} 第 {{line}} 行起选中的这段改得更简洁，保留原意和语气：

        {{selection}}
        """),
        ("rules.md", """
        ---
        title: 从最近的审阅总结写作规则
        agent: claude
        scope: vault
        icon: text.book.closed
        ---
        运行 `twain reviews` 查看我最近审阅过的修改，重点看被拒绝的改动和我写下的原因。
        从中总结 3–5 条具体、可执行的写作和修改规则，提议加入 AGENTS.md 的“写作规则”一节（没有这一节就新建）。
        用 propose_edit 提交，每条规则都注明来自哪些审阅。只写能从审阅记录里看出来的规则，不要泛泛而谈。
        """),
    ]

    /// A sample automation, written disabled-by-approval like any other.
    static let sampleAutomation = ("inbox.md.example", """
        ---
        title: 收件箱归类
        on: note.saved
        match: 收件箱.md
        agent: claude
        model: haiku
        debounce: 120
        ---
        {{path}} 刚被修改。把收件箱里新增的条目归到库里合适的笔记中，用 propose_edit 提交，每条都写明为什么放在那里。
        没有需要归类的就什么都不做。
        """)

    func loadVaultConfig() {
        guard let v = vault else { return }
        let fm = FileManager.default
        let dir = v.root.appendingPathComponent(".twain")
        let commandsDir = dir.appendingPathComponent("commands")
        let automationsDir = dir.appendingPathComponent("automations")
        if !fm.fileExists(atPath: commandsDir.path) {
            try? fm.createDirectory(at: commandsDir, withIntermediateDirectories: true)
            for (name, text) in Self.defaultCommands {
                try? (text + "\n").write(to: commandsDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
        if !fm.fileExists(atPath: automationsDir.path) {
            try? fm.createDirectory(at: automationsDir, withIntermediateDirectories: true)
            try? (Self.sampleAutomation.1 + "\n").write(to: automationsDir.appendingPathComponent(Self.sampleAutomation.0),
                                                       atomically: true, encoding: .utf8)
        }
        func read(_ d: URL) -> [(String, String)] {
            let files = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "md" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .compactMap { u in (try? String(contentsOf: u, encoding: .utf8)).map { (v.relative(u.path), $0) } }
        }
        userCommands = read(commandsDir).compactMap { UserCommand.parse(file: $0.0, text: $0.1) }
        let before = automations
        automations = read(automationsDir).compactMap { Automation.parse(file: $0.0, text: $0.1) }
        loadPipelines()
        for (id, work) in automationTimers where !automations.contains(where: { $0.id == id && isApproved($0) }) {
            work.cancel()
            automationTimers[id] = nil
        }
        let fresh = automations.filter { a in !isApproved(a) && !before.contains(a) }
        if let first = fresh.first {
            showToast("发现自动化「\(first.title)」" + (fresh.count > 1 ? "等 \(fresh.count) 条" : "") + "，在设置 → Agent 中启用后才会运行")
        }
    }

    func userCommand(named name: String) -> UserCommand? {
        let n = name.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
        return userCommands.first { $0.key.lowercased() == n }
            ?? userCommands.first { (($0.file as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased() == n }
    }

    /// Fills in the command's template from the editor and starts it. Returns the session it runs in.
    @discardableResult
    func runUserCommand(_ c: UserCommand, input: String?) throws -> AgentSession {
        guard vault != nil else { throw RPCError(RPCError.noVault, "共笔没有打开任何库") }
        let vars = try templateVars(scope: c.scope, title: c.title, input: input)
        runAgent(prompt: Template.render(c.prompt, vars), agent: c.agent, model: c.model, effort: c.effort)
        guard let s = activeSession else { throw RPCError(RPCError.internalError, "没能启动 \(c.agent.displayName)") }
        return s
    }

    // MARK: automations

    private var approvalKey: String { "automation.approved." + (vault?.rootPath ?? "") }

    /// Approval is tied to the file's content: an edited (or newly pulled) automation asks again.
    func isApproved(_ a: Automation) -> Bool {
        (UserDefaults.standard.dictionary(forKey: approvalKey) as? [String: String])?[a.id] == a.fingerprint
    }

    func setApproved(_ a: Automation, _ on: Bool) {
        var d = UserDefaults.standard.dictionary(forKey: approvalKey) as? [String: String] ?? [:]
        d[a.id] = on ? a.fingerprint : nil
        UserDefaults.standard.set(d, forKey: approvalKey)
        if !on { automationTimers.removeValue(forKey: a.id)?.cancel() }
        tick += 1
    }

    private var runsKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "automation.runs." + f.string(from: Date())
    }

    var automationRunsToday: Int { UserDefaults.standard.integer(forKey: runsKey) }

    /// Starts (or restarts) the quiet-period countdown of every automation the event concerns.
    func automationEvent(_ type: String, source: String, path: String?) {
        guard automationsOn else { return }
        for a in automations where isApproved(a) && a.triggers(event: type, path: path) {
            // An automation never wakes itself up, and one run at a time is enough.
            if source == "automation:" + a.id { continue }
            if sessions.contains(where: { $0.automationID == a.id && $0.running }) { continue }
            automationTimers[a.id]?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.fireAutomation(a.id, event: type, path: path) }
            automationTimers[a.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(a.debounce), execute: work)
        }
    }

    func fireAutomation(_ id: String, event: String, path: String?) {
        automationTimers[id] = nil
        guard automationsOn, let a = automations.first(where: { $0.id == id }), isApproved(a), let v = vault else { return }
        guard !sessions.contains(where: { $0.automationID == a.id && $0.running }) else { return }
        guard automationRunsToday < automationDailyLimit else {
            showToast("今天的自动化已运行 \(automationDailyLimit) 次，达到上限，「\(a.title)」没有运行")
            return
        }
        UserDefaults.standard.set(automationRunsToday + 1, forKey: runsKey)
        tick += 1
        let rel = path ?? ""
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let prompt = Template.render(a.prompt, [
            "path": rel, "title": ((rel as NSString).lastPathComponent as NSString).deletingPathExtension,
            "note": rel.isEmpty ? "" : (v.diskContent(rel) ?? ""), "event": event, "date": f.string(from: Date()),
        ])
        let s = AgentSession(agent: a.agent, source: .automation, title: "自动化 · " + a.title)
        s.automationID = a.id
        sessions.append(s)
        if activeSessionID == nil { activeSessionID = s.id }
        if launch(s, prompt: prompt, model: a.model, effort: a.effort) {
            showToast("自动化「\(a.title)」开始运行")
        }
    }
}
