import AppKit
import TwainCore
import SwiftUI

/// One request to run a command, from ⌘K or from an agent over the socket.
struct CommandCall {
    var params: [String: JSONValue] = [:]
    var caller: RPCCaller?
    /// The agent session the caller belongs to, when Twain can tell.
    var session: AgentSession?
    /// The socket connection, for commands that answer later or keep sending (`watch`).
    var connection: AgentServer.Connection?
}

/// How a command appears in ⌘K. Labels can depend on state ("进入/退出专注模式").
struct PaletteInfo {
    var label: (AppModel) -> String
    var hint: String = ""
    var icon: String
    var tint: Color? = nil
    var visible: (AppModel) -> Bool = { _ in true }
}

/// A command the app knows how to run. The same entry feeds ⌘K and the socket, so anything
/// agents can do goes through the code the user's own actions use.
struct AppCommand {
    typealias Reply = (Result<JSONValue, RPCError>) -> Void

    let spec: CommandSpec
    var palette: PaletteInfo?
    /// False for commands that only make sense with the user at the keyboard (modal panels).
    var agents = true
    /// Answers through `reply`, possibly much later (a question waits for the user).
    let perform: (AppModel, CommandCall, @escaping Reply) -> Void

    init(spec: CommandSpec, palette: PaletteInfo? = nil, agents: Bool = true,
         async perform: @escaping (AppModel, CommandCall, @escaping Reply) -> Void) {
        self.spec = spec
        self.palette = palette
        self.agents = agents
        self.perform = perform
    }

    init(spec: CommandSpec, palette: PaletteInfo? = nil, agents: Bool = true,
         run: @escaping (AppModel, CommandCall) throws -> JSONValue) {
        self.init(spec: spec, palette: palette, agents: agents) { m, call, reply in
            do { reply(.success(try run(m, call))) } catch let e as RPCError { reply(.failure(e)) } catch {
                reply(.failure(RPCError(RPCError.internalError, error.localizedDescription)))
            }
        }
    }
}

enum CommandRegistry {
    static let builtin: [AppCommand] = agentCommands + paletteCommands + debugCommands

    #if DEBUG
    /// Stand-ins for the user's clicks, so `scripts/e2e.sh` can drive reviews and questions.
    static let debugCommands: [AppCommand] = [
        AppCommand(spec: CommandSpec("debug.review", "（调试）替用户处理一篇笔记的审阅", effect: .write, params: [
            ParamSpec("note", required: true, positional: true, help: "笔记路径"),
            ParamSpec("states", .strings, help: "每处改动 accepted 或 rejected"),
            ParamSpec("feedback", .strings, help: "每处改动的拒绝原因"),
        ])) { m, call in
            let rel = call.params["note"]?.string ?? ""
            guard let r = m.pending[rel] else { throw RPCError(RPCError.notFound, "\(rel) 没有待审阅的改动") }
            m.open(rel)
            let states = (call.params["states"]?.array ?? []).compactMap(\.string)
            let feedback = (call.params["feedback"]?.array ?? []).compactMap(\.string)
            for i in r.hunks.indices {
                m.setHunk(i, i < states.count ? HunkState(rawValue: states[i]) ?? .accepted : .accepted)
                if i < feedback.count { m.setFeedback(i, feedback[i]) }
            }
            m.finishReview(all: nil)
            return ["done": true]
        },
        AppCommand(spec: CommandSpec("debug.run", "（调试）像用户在 Agent 面板里输入一样启动一次运行", effect: .write, params: [
            ParamSpec("prompt", required: true, positional: true, help: "提示词"),
            ParamSpec("agent", help: "claude 或 codex"),
            ParamSpec("model", help: "模型"),
            ParamSpec("note", help: "先打开这篇笔记"),
        ])) { m, call in
            if let n = call.params["note"]?.string { m.open(n) }
            let agent = AgentKind(rawValue: call.params["agent"]?.string ?? "claude") ?? .claude
            m.runAgent(prompt: call.params["prompt"]?.string ?? "", agent: agent, model: call.params["model"]?.string)
            return ["session": JSONValue(m.activeSession?.id.uuidString)]
        },
        AppCommand(spec: CommandSpec("debug.transcript", "（调试）一个会话的时间线", effect: .read, params: [
            ParamSpec("session", required: true, positional: true, help: "会话 id"),
        ])) { m, call in
            guard let s = m.sessions.first(where: { $0.id.uuidString == call.params["session"]?.string }) else {
                throw RPCError(RPCError.notFound, "没有这个会话")
            }
            return ["running": .bool(s.running), "items": .array(s.items.map { item -> JSONValue in
                switch item.kind {
                case let .user(t): return ["user": .string(t)]
                case let .agent(t): return ["agent": .string(t)]
                case let .step(_, t, _): return ["step": .string(t)]
                case let .error(t): return ["error": .string(t)]
                case let .change(rel, p, mi): return ["change": .string("\(rel) +\(p) -\(mi)")]
                case let .question(id): return ["question": .string(m.questions[id]?.question ?? "")]
                case let .feedback(rel, _, sent): return ["feedback": .string(rel), "sent": .bool(sent)]
                }
            })]
        },
        AppCommand(spec: CommandSpec("debug.feedback", "（调试）点会话里最近一条“把意见发回”", effect: .write, params: [
            ParamSpec("session", required: true, positional: true, help: "会话 id"),
        ])) { m, call in
            guard let s = m.sessions.first(where: { $0.id.uuidString == call.params["session"]?.string }),
                  let item = s.items.last(where: { if case .feedback(_, _, false) = $0.kind { return true }; return false }) else {
                throw RPCError(RPCError.notFound, "没有待发送的审阅意见")
            }
            m.sendFeedback(item.id, in: s)
            return ["sent": true]
        },
        AppCommand(spec: CommandSpec("debug.rename", "（调试）像在侧栏里一样重命名一篇笔记", effect: .write, params: [
            ParamSpec("note", required: true, positional: true, help: "笔记路径"),
            ParamSpec("title", required: true, help: "新名字"),
        ])) { m, call in
            let rel = call.params["note"]?.string ?? ""
            guard m.renameNote(rel, to: call.params["title"]?.string ?? "") else {
                throw RPCError(RPCError.invalidParams, m.toast ?? "没有重命名")
            }
            return ["toast": JSONValue(m.toast)]
        },
        AppCommand(spec: CommandSpec("debug.type", "（调试）像用户在编辑器里输入一样替换当前笔记的正文并移动光标", effect: .write, params: [
            ParamSpec("text", required: true, positional: true, help: "新正文"),
            ParamSpec("caret", .int, help: "光标位置（UTF-16），默认在末尾"),
        ])) { m, call in
            let text = call.params["text"]?.string ?? ""
            m.editorDidChange(text)
            m.editorSelection = NSRange(location: call.params["caret"]?.int ?? (text as NSString).length, length: 0)
            return ["done": true]
        },
        AppCommand(spec: CommandSpec("debug.approve", "（调试）像在设置里一样启用一条自动化", effect: .write, params: [
            ParamSpec("id", required: true, positional: true, help: "自动化文件名（不含 .md）"),
        ])) { m, call in
            m.loadVaultConfig()
            guard let a = m.automations.first(where: { $0.id == call.params["id"]?.string }) else {
                throw RPCError(RPCError.notFound, "没有这条自动化")
            }
            m.setApproved(a, true)
            return ["approved": .string(a.id)]
        },
        AppCommand(spec: CommandSpec("debug.answer", "（调试）替用户回答最近的问题", effect: .write, params: [
            ParamSpec("text", required: true, positional: true, help: "回答"),
        ])) { m, call in
            guard let q = m.questions.values.first(where: { $0.answer == nil && !$0.expired }) else {
                throw RPCError(RPCError.notFound, "没有等待回答的问题")
            }
            m.answer(q.id, call.params["text"]?.string ?? "")
            return ["question": .string(q.question)]
        },
    ]
    #else
    static let debugCommands: [AppCommand] = []
    #endif

    /// Built-in commands plus the vault's own (`.twain/commands/`).
    static func all(_ m: AppModel) -> [AppCommand] { builtin + m.userCommands.map(userCommand) }

    static func command(_ id: String, in m: AppModel) -> AppCommand? { all(m).first { $0.spec.id == id } }

    static func exposed(_ m: AppModel) -> [AppCommand] { all(m).filter(\.agents) }

    // MARK: agent-facing

    static let agentCommands: [AppCommand] = [
        AppCommand(spec: TwainCommands.context) { m, call in try m.contextJSON(session: call.session) },
        query(TwainCommands.notes),
        query(TwainCommands.search),
        query(TwainCommands.backlinks),
        query(TwainCommands.outline),
        query(TwainCommands.tasks),
        query(TwainCommands.reviews),
        AppCommand(spec: TwainCommands.open) { m, call in
            let (index, _) = try m.freshIndex()
            let rel = try VaultQueries.note(call.params, index: index, current: nil)
            var line = call.params["line"]?.int
            if let heading = call.params["heading"]?.string {
                let wanted = heading.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                guard let h = index.notes[rel]?.outline.headings.first(where: { $0.text == wanted }) else {
                    throw RPCError(RPCError.notFound, "\(rel) 里没有标题：\(heading)")
                }
                line = h.line
            }
            m.open(rel)
            let caret = line.map { Self.offset(ofLine: $0, in: m.editorText) } ?? 0
            m.requestFocus(caret: caret)
            return ["note": .string(rel), "line": JSONValue(line ?? 1)]
        },
        AppCommand(spec: TwainCommands.reveal) { m, call in
            let (index, _) = try m.freshIndex()
            let rel = try VaultQueries.note(call.params, index: index, current: nil)
            if m.columnVisibility == .detailOnly { m.columnVisibility = .all }
            m.revealInSidebar(rel)
            return ["note": .string(rel)]
        },
        AppCommand(spec: TwainCommands.notify) { m, call in
            let text = call.params["message"]?.string ?? ""
            m.showToast(text)
            call.session?.items.append(SessionItem(kind: .step(id: UUID().uuidString, text: "通知：" + text, running: false)))
            return ["shown": true]
        },
        AppCommand(spec: TwainCommands.propose) { m, call, reply in m.propose(call, reply: reply) },
        AppCommand(spec: TwainCommands.ask) { m, call, reply in m.ask(call, reply: reply) },
        AppCommand(spec: TwainCommands.run) { m, call in
            let name = call.params["name"]?.string ?? ""
            guard let cmd = m.userCommand(named: name) else {
                throw RPCError(RPCError.notFound, "没有自定义命令 \(name)；可用的有：" + m.userCommands.map(\.key).joined(separator: "、"))
            }
            let s = try m.runUserCommand(cmd, input: call.params["input"]?.string)
            return ["command": .string(cmd.key), "session": .string(s.id.uuidString), "agent": .string(cmd.agent.rawValue)]
        },
        AppCommand(spec: TwainCommands.watch) { m, call, reply in m.watch(call, reply: reply) },
        AppCommand(spec: TwainCommands.commands) { m, _ in
            ["commands": .array(exposed(m).map(\.spec.json))]
        },
    ]

    /// A vault command file as a ⌘K entry. Agents reach it through `run`, not by its own id.
    static func userCommand(_ c: UserCommand) -> AppCommand {
        AppCommand(spec: CommandSpec("cmd." + c.key, c.title, effect: .propose),
                   palette: PaletteInfo(label: { _ in c.title }, hint: "/" + c.key, icon: c.icon, tint: Theme.agentColor(c.agent)),
                   agents: false) { m, _ in
            _ = try m.runUserCommand(c, input: nil)
            return ["done": true]
        }
    }

    /// A read command answered from the index, identically to the CLI's offline mode.
    static func query(_ spec: CommandSpec) -> AppCommand {
        AppCommand(spec: spec) { m, call in
            let (index, _) = try m.freshIndex()
            return try VaultQueries.run(spec.id, call.params, index: index, current: m.activeRel)
        }
    }

    /// UTF-16 offset of the start of 1-based `line`, clamped to the text.
    static func offset(ofLine line: Int, in text: String) -> Int {
        let ns = text as NSString
        var loc = 0, n = 1
        while n < line, loc < ns.length {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(r)
            n += 1
        }
        return min(loc, ns.length)
    }

    // MARK: ⌘K

    static func ui(_ id: String, _ summary: String, agents: Bool = false, _ palette: PaletteInfo,
                   run: @escaping (AppModel) -> Void) -> AppCommand {
        AppCommand(spec: CommandSpec(id, summary, effect: .ui), palette: palette, agents: agents) { m, _ in
            run(m)
            return ["done": true]
        }
    }

    static let paletteCommands: [AppCommand] = [
        ui("note.new", "新建一篇笔记并打开", PaletteInfo(label: { _ in "新建笔记" }, hint: "⌘N", icon: "square.and.pencil")) { $0.newNote() },
        ui("note.rename", "在侧栏里重命名当前笔记", PaletteInfo(label: { _ in "重命名笔记…" }, icon: "pencil",
                                                  visible: { $0.activeRel != nil })) { $0.beginRename() },
        ui("zen", "进入或退出专注模式", PaletteInfo(label: { $0.zen ? "退出专注模式" : "进入专注模式" }, hint: "⌘.",
                                          icon: "arrow.up.left.and.arrow.down.right")) { $0.toggleZen() },
        ui("editor.typewriter", "切换打字机滚动", PaletteInfo(label: { "打字机滚动：" + ($0.typewriter ? "关闭" : "开启") },
                                                  icon: "text.aligncenter")) { $0.typewriter.toggle() },
        ui("editor.dim", "切换段落聚焦", PaletteInfo(label: { "段落聚焦：" + ($0.dim ? "关闭" : "开启") },
                                           icon: "text.line.first.and.arrowtriangle.forward")) { $0.dim.toggle() },
        AppCommand(spec: CommandSpec("editor.font", "轮换正文字体", effect: .ui),
                   palette: PaletteInfo(label: { _ in "切换字体：衬线 / 无衬线 / 等宽" }, icon: "textformat"), agents: false) { m, _ in
            m.font = m.font.next
            return ["done": true]
        },
        ui("review.next", "打开下一处待审阅的改动", agents: true,
           PaletteInfo(label: { "审阅待定改动（\($0.pending.count)）" }, hint: "⇧⌘R", icon: "checklist",
                       visible: { !$0.pending.isEmpty })) { $0.reviewNext() },
        ui("settings.agent", "打开 Agent 与 CLI 设置",
           PaletteInfo(label: { _ in "Agent 与 CLI 设置" }, hint: "⌘,", icon: "gearshape")) { $0.openSettings(.agent) },
        ui("vault.choose", "选择另一个库", PaletteInfo(label: { _ in "打开其他库…" }, hint: "⌘O", icon: "folder")) { $0.chooseVault() },
        ui("onboarding", "重新运行新手引导", PaletteInfo(label: { _ in "重新运行新手引导" }, icon: "hand.wave")) { $0.onboardingStep = 0 },
    ]
}

extension AppModel {
    /// The index brought up to date with the disk and with the editor's unsaved text.
    func freshIndex() throws -> (VaultIndex, Vault) {
        guard let v = vault, let index else { throw RPCError(RPCError.noVault, "共笔没有打开任何库") }
        index.refresh()
        if dirty, let rel = activeRel { index.update(rel, text: editorText) }
        return (index, v)
    }

    func contextJSON(session: AgentSession?) throws -> JSONValue {
        let (index, v) = try freshIndex()
        var out: [String: JSONValue] = [
            "vault": .string(v.rootPath),
            "protocol": JSONValue(RPC.protocolVersion),
            "pending": .array(pending.values.sorted { $0.rel < $1.rel }.map { p in
                ["path": .string(p.rel), "by": JSONValue(p.by?.displayName), "plus": JSONValue(p.plus), "minus": JSONValue(p.minus)]
            }),
            "note": .null,
        ]
        if let session {
            out["session"] = ["id": .string(session.id.uuidString), "agent": .string(session.agent.rawValue), "title": .string(session.title)]
        }
        guard let rel = activeRel else { return .object(out) }
        var note = EditorContext.describe(text: editorText, selection: editorSelection)
        note["path"] = .string(rel)
        note["title"] = .string(((rel as NSString).lastPathComponent as NSString).deletingPathExtension)
        note["unsaved"] = .bool(dirty)
        note["backlinks"] = .array(index.backlinks(to: rel).prefix(20).map { h in
            ["path": .string(h.rel), "line": JSONValue(h.line ?? 0), "text": .string(h.text)]
        })
        note["pendingReview"] = .bool(pending[rel] != nil)
        out["note"] = .object(note)
        return .object(out)
    }
}
