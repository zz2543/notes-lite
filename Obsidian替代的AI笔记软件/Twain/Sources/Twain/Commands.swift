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
    var label: @MainActor (AppModel) -> String
    var hint: String = ""
    var icon: String
    var tint: Color? = nil
    var visible: @MainActor (AppModel) -> Bool = { _ in true }
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
    let perform: @MainActor (AppModel, CommandCall, @escaping Reply) -> Void

    init(spec: CommandSpec, palette: PaletteInfo? = nil, agents: Bool = true,
         async perform: @escaping @MainActor (AppModel, CommandCall, @escaping Reply) -> Void) {
        self.spec = spec
        self.palette = palette
        self.agents = agents
        self.perform = perform
    }

    init(spec: CommandSpec, palette: PaletteInfo? = nil, agents: Bool = true,
         run: @escaping @MainActor (AppModel, CommandCall) throws -> JSONValue) {
        self.init(spec: spec, palette: palette, agents: agents) { m, call, reply in
            reply(Self.attempt { try run(m, call) })
        }
    }

    /// Answers from the index once it has caught up with the disk (walked off the main thread)
    /// and with the editor's unsaved text.
    init(spec: CommandSpec, palette: PaletteInfo? = nil, agents: Bool = true,
         indexed run: @escaping @MainActor (AppModel, CommandCall, VaultIndex, Vault) throws -> JSONValue) {
        self.init(spec: spec, palette: palette, agents: agents) { m, call, reply in
            m.withFreshIndex { result in
                switch result {
                case let .success((index, v)): reply(Self.attempt { try run(m, call, index, v) })
                case let .failure(e): reply(.failure(e))
                }
            }
        }
    }

    static func attempt(_ f: () throws -> JSONValue) -> Result<JSONValue, RPCError> {
        do { return .success(try f()) } catch let e as RPCError { return .failure(e) } catch {
            return .failure(RPCError(RPCError.internalError, error.localizedDescription))
        }
    }
}

@MainActor
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
            guard let r = m.agents.pending[rel] else { throw RPCError(RPCError.notFound, "\(rel) 没有待审阅的改动") }
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
            guard let s = m.agents.sessions.first(where: { $0.id.uuidString == call.params["session"]?.string }) else {
                throw RPCError(RPCError.notFound, "没有这个会话")
            }
            return ["running": .bool(s.running), "items": .array(s.items.map { item -> JSONValue in
                switch item.kind {
                case let .user(t): return ["user": .string(t)]
                case let .agent(t): return ["agent": .string(t)]
                case let .step(_, t, _): return ["step": .string(t)]
                case let .error(t): return ["error": .string(t)]
                case let .change(rel, p, mi): return ["change": .string("\(rel) +\(p) -\(mi)")]
                case let .question(id): return ["question": .string(m.agents.questions[id]?.question ?? "")]
                case let .feedback(rel, _, sent): return ["feedback": .string(rel), "sent": .bool(sent)]
                case let .pipeline(id):
                    let r = m.agents.pipelineRuns[id]
                    return ["pipeline": .string(r?.pipeline.key ?? ""), "step": JSONValue(r?.step ?? 0), "status": .string(r.map { "\($0.status)" } ?? "")]
                }
            })]
        },
        AppCommand(spec: CommandSpec("debug.feedback", "（调试）点会话里最近一条“把意见发回”", effect: .write, params: [
            ParamSpec("session", required: true, positional: true, help: "会话 id"),
        ])) { m, call in
            guard let s = m.agents.sessions.first(where: { $0.id.uuidString == call.params["session"]?.string }),
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
                throw RPCError(RPCError.invalidParams, m.chrome.toast ?? "没有重命名")
            }
            return ["toast": JSONValue(m.chrome.toast)]
        },
        AppCommand(spec: CommandSpec("debug.type", "（调试）像用户在编辑器里输入一样替换当前笔记的正文并移动光标", effect: .write, params: [
            ParamSpec("text", required: true, positional: true, help: "新正文"),
            ParamSpec("caret", .int, help: "光标位置（UTF-16），默认在末尾"),
        ])) { m, call in
            let text = call.params["text"]?.string ?? ""
            m.editorDidChange(text)
            m.editor.editorSelection = NSRange(location: call.params["caret"]?.int ?? (text as NSString).length, length: 0)
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
        AppCommand(spec: CommandSpec("debug.summarize", "（调试）为笔记生成 AI 摘要", effect: .write, params: [
            ParamSpec("limit", .int, help: "最多几篇"),
        ])) { m, call, reply in
            m.summarizeNotes(limit: call.params["limit"]?.int)
            @MainActor func poll() {
                if m.summarizing == nil { reply(.success(["toast": JSONValue(m.chrome.toast)])) }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll() } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll() }
        },
        AppCommand(spec: CommandSpec("debug.aireview", "（调试）AI 审阅一篇笔记，等运行结束", effect: .write, params: [
            ParamSpec("note", required: true, positional: true, help: "笔记"),
            ParamSpec("model", help: "模型"),
        ])) { m, call, reply in m.withFreshIndex { r in
            guard case let .success((index, _)) = r, let rel = index.resolve(call.params["note"]?.string ?? "") else {
                return reply(.failure(RPCError(RPCError.notFound, "找不到笔记")))
            }
            m.open(rel)
            m.startAIReview(model: call.params["model"]?.string)
            let s = m.activeSession
            @MainActor func poll() {
                if s?.running == false { reply(.success(["annotations": .array(m.editor.annotations.map(\.json)),
                                                          "transcript": .string(s?.markdown ?? "")])) }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { poll() } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { poll() }
        } },
        AppCommand(spec: CommandSpec("debug.companion", "（调试）在当前笔记末尾写一段，等伴写给出一句话", effect: .write, params: [
            ParamSpec("text", required: true, positional: true, help: "追加的文字"),
        ])) { m, call, reply in
            if !m.prefs.companionOn { m.toggleCompanion() }
            m.companionLast = .distantPast
            m.editor.companionTip = nil
            let t = m.editor.editorText + (call.params["text"]?.string ?? "")
            m.editorDidChange(t)
            m.editor.editorSelection = NSRange(location: (t as NSString).length, length: 0)
            let start = Date()
            @MainActor func poll() {
                if let tip = m.editor.companionTip {
                    reply(.success(["kind": .string(tip.kind.rawValue), "text": .string(tip.text), "quote": JSONValue(tip.quote),
                                    "seconds": JSONValue(Int(Date().timeIntervalSince(start)))]))
                } else if Date().timeIntervalSince(start) > 60 { reply(.success(["tip": .null])) }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll() } }
            }
            poll()
        },
        AppCommand(spec: CommandSpec("debug.pipeline", "（调试）运行流水线或处理它的关口，返回停下时的状态", effect: .write, params: [
            ParamSpec("action", required: true, positional: true, help: "start / continue / redo / stop / wait"),
            ParamSpec("name", help: "流水线"), ParamSpec("input", help: "输入"), ParamSpec("model", help: "模型"),
            ParamSpec("feedback", help: "意见"),
        ])) { m, call, reply in
            let action = call.params["action"]?.string ?? ""
            var id = m.agents.pipelineRuns.values.sorted { $0.step < $1.step }.last?.id
            do {
                switch action {
                case "start":
                    guard let p = m.pipeline(named: call.params["name"]?.string ?? "") else { throw RPCError(RPCError.notFound, "没有这个流水线") }
                    _ = try m.runPipeline(p, input: call.params["input"]?.string, model: call.params["model"]?.string)
                    id = m.agents.pipelineRuns.values.first { $0.status == .running }?.id
                case "continue":
                    if let id, let f = call.params["feedback"]?.string, var r = m.agents.pipelineRuns[id], !r.outputs.isEmpty {
                        r.outputs[r.outputs.count - 1] += "\n\n（用户的意见：\(f)）"
                        m.agents.pipelineRuns[id] = r
                    }
                    if let id { m.advancePipeline(id) }
                case "redo": if let id { m.redoPipelineStep(id, feedback: call.params["feedback"]?.string ?? "") }
                case "stop": if let id { m.stopPipeline(id) }
                default: break
                }
            } catch let e as RPCError { return reply(.failure(e)) } catch {}
            @MainActor func poll() {
                guard let id, let r = m.agents.pipelineRuns[id] else { return reply(.failure(RPCError(RPCError.notFound, "没有流水线在运行"))) }
                if r.status == .running { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { poll() }; return }
                reply(.success(["step": JSONValue(r.step + 1), "status": .string("\(r.status)"), "output": .string(r.outputs.last ?? ""),
                                "pending": JSONValue(m.agents.pending.keys.sorted())]))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { poll() }
        },
        AppCommand(spec: CommandSpec("debug.desk", "（调试）在问库里提问，等 agent 交完卡片", effect: .write, params: [
            ParamSpec("question", required: true, positional: true, help: "问题"),
            ParamSpec("scope", help: "folder:… 或 tag:…"), ParamSpec("model", help: "模型"),
        ])) { m, call, reply in
            m.newDesk()
            guard let id = m.chrome.openDesk else { return reply(.failure(RPCError(RPCError.internalError, "没能新建"))) }
            m.ask(desk: id, question: call.params["question"]?.string ?? "", scope: call.params["scope"]?.string ?? "",
                  model: call.params["model"]?.string)
            let sid = m.currentDesk?.session
            @MainActor func poll() {
                let s = m.agents.sessions.first { $0.id.uuidString == sid }
                if s?.running == false, let d = m.desks.first(where: { $0.id == id }) {
                    reply(.success(["desk": .string(id), "cards": .array(d.cards.map { c in
                        ["kind": .string(c.kind.rawValue), "title": .string(c.title), "body": .string(c.body),
                         "sources": .array(c.sources.map { .string($0.path + ":" + ($0.line.map(String.init) ?? "")) })]
                    }), "said": .string(s?.markdown.suffix(300).description ?? "")]))
                } else { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { poll() } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { poll() }
        },
        AppCommand(spec: CommandSpec("debug.space", "（调试）用模板新建空间", effect: .write, params: [
            ParamSpec("template", required: true, positional: true, help: "模板 id"),
            ParamSpec("folder", help: "文件夹"),
        ])) { m, call in
            guard let t = SpaceTemplate.all.first(where: { $0.id == call.params["template"]?.string }) else { throw RPCError(RPCError.notFound, "没有这个模板") }
            let id = try m.installTemplate(t, name: t.name, folder: call.params["folder"]?.string ?? t.folder)
            return ["space": .string(id)]
        },
        AppCommand(spec: CommandSpec("debug.answer", "（调试）替用户回答最近的问题", effect: .write, params: [
            ParamSpec("text", required: true, positional: true, help: "回答"),
        ])) { m, call in
            guard let q = m.agents.questions.values.first(where: { $0.answer == nil && !$0.expired }) else {
                throw RPCError(RPCError.notFound, "没有等待回答的问题")
            }
            m.answer(q.id, call.params["text"]?.string ?? "")
            return ["question": .string(q.question)]
        },
    ]
    #else
    static let debugCommands: [AppCommand] = []
    #endif

    /// Built-in commands plus the vault's own (`.twain/commands/`, `.twain/pipelines/`).
    static func all(_ m: AppModel) -> [AppCommand] {
        builtin + m.userCommands.map(userCommand) + m.agents.pipelines.map(pipelineCommand) + m.spaces.map(spaceCommand)
    }

    static func spaceCommand(_ p: Plugin) -> AppCommand {
        ui("space." + p.id, "打开空间「\(p.name)」", PaletteInfo(label: { _ in "空间：" + p.name }, icon: p.icon)) { $0.openSpace(p.id) }
    }

    static func pipelineCommand(_ p: Pipeline) -> AppCommand {
        AppCommand(spec: CommandSpec("pipeline." + p.key, p.title, effect: .propose),
                   palette: PaletteInfo(label: { _ in "流水线：" + p.title }, hint: "\(p.steps.count) 步", icon: p.icon,
                                        tint: Theme.agentColor(p.agent)),
                   agents: false) { m, _ in
            _ = try m.runPipeline(p)
            return ["done": true]
        }
    }

    static func command(_ id: String, in m: AppModel) -> AppCommand? { all(m).first { $0.spec.id == id } }

    static func exposed(_ m: AppModel) -> [AppCommand] { all(m).filter(\.agents) }

    // MARK: agent-facing

    static let agentCommands: [AppCommand] = [
        AppCommand(spec: TwainCommands.context) { m, call, index, v in m.contextJSON(session: call.session, index: index, vault: v) },
        query(TwainCommands.notes),
        query(TwainCommands.search),
        query(TwainCommands.skim),
        query(TwainCommands.read),
        query(TwainCommands.backlinks),
        query(TwainCommands.outline),
        query(TwainCommands.tasks),
        query(TwainCommands.reviews),
        AppCommand(spec: TwainCommands.open) { m, call, index, _ in
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
            let caret = line.map { NoteFile.offset(ofLine: $0, in: m.editor.editorText) } ?? 0
            m.requestFocus(caret: caret)
            return ["note": .string(rel), "line": JSONValue(line ?? 1)]
        },
        AppCommand(spec: TwainCommands.reveal) { m, call, index, _ in
            let rel = try VaultQueries.note(call.params, index: index, current: nil)
            if m.chrome.columnVisibility == .detailOnly { m.chrome.columnVisibility = .all }
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
            if m.userCommand(named: name) == nil, let p = m.pipeline(named: name) {
                guard let s = try m.runPipeline(p, input: call.params["input"]?.string) else { throw RPCError(RPCError.invalidParams, "没有给出输入") }
                return ["command": .string(p.key), "session": .string(s.id.uuidString), "agent": .string(p.agent.rawValue), "pipeline": true]
            }
            guard let cmd = m.userCommand(named: name) else {
                throw RPCError(RPCError.notFound, "没有自定义命令 \(name)；可用的有：" + (m.userCommands.map(\.key) + m.agents.pipelines.map(\.key)).joined(separator: "、"))
            }
            let s = try m.runUserCommand(cmd, input: call.params["input"]?.string)
            return ["command": .string(cmd.key), "session": .string(s.id.uuidString), "agent": .string(cmd.agent.rawValue)]
        },
        AppCommand(spec: TwainCommands.watch) { m, call, reply in m.watch(call, reply: reply) },
        AppCommand(spec: TwainCommands.annotate) { m, call, index, v in try m.annotateCommand(call, index: index, vault: v) },
        AppCommand(spec: TwainCommands.cards) { m, call, index, _ in try m.cardsCommand(call, index: index) },
    ] + TwainCommands.dataCommands.map { spec in
        AppCommand(spec: spec) { m, call in
            guard let v = m.vault else { throw RPCError(RPCError.noVault, "共笔没有打开任何库") }
            let r = try DataQueries.run(spec.id, call.params, root: v.root)
            if spec.effect == .write { m.dataChanged(r["collection"]?.string ?? "", added: r["added"]?.int ?? 0, source: call.session.map(m.eventSource) ?? "external") }
            return r
        }
    } + [
        AppCommand(spec: TwainCommands.annotations) { m, call, index, v in try m.annotationsCommand(call, index: index, vault: v) },
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
        AppCommand(spec: spec) { m, call, index, _ in
            try VaultQueries.run(spec.id, call.params, index: index, current: m.editor.activeRel)
        }
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
                                                  visible: { $0.editor.activeRel != nil })) { $0.beginRename() },
        ui("zen", "进入或退出专注模式", PaletteInfo(label: { $0.chrome.zen ? "退出专注模式" : "进入专注模式" }, hint: "⌘.",
                                          icon: "arrow.up.left.and.arrow.down.right")) { $0.toggleZen() },
        ui("editor.typewriter", "切换打字机滚动", PaletteInfo(label: { "打字机滚动：" + ($0.prefs.typewriter ? "关闭" : "开启") },
                                                  icon: "text.aligncenter")) { $0.prefs.typewriter.toggle() },
        ui("editor.dim", "切换段落聚焦", PaletteInfo(label: { "段落聚焦：" + ($0.prefs.dim ? "关闭" : "开启") },
                                           icon: "text.line.first.and.arrowtriangle.forward")) { $0.prefs.dim.toggle() },
        AppCommand(spec: CommandSpec("editor.font", "轮换正文字体", effect: .ui),
                   palette: PaletteInfo(label: { _ in "切换字体：衬线 / 无衬线 / 等宽" }, icon: "textformat"), agents: false) { m, _ in
            m.prefs.font = m.prefs.font.next
            return ["done": true]
        },
        ui("review.next", "打开下一处待审阅的改动", agents: true,
           PaletteInfo(label: { "审阅待定改动（\($0.agents.pending.count)）" }, hint: "⇧⌘R", icon: "checklist",
                       visible: { !$0.agents.pending.isEmpty })) { $0.reviewNext() },
        ui("space.new", "新建一个空间（日记、自律、子弹笔记、LLM Wiki 或空白）",
           PaletteInfo(label: { _ in "新建空间…" }, icon: "plus.square.dashed")) { $0.chrome.panelOrigin = nil; $0.chrome.newSpaceSheet = true },
        ui("desk.new", "问库：向整个笔记库提一个问题，答案是一组带出处的卡片",
           PaletteInfo(label: { _ in "问库：向笔记库提问" }, hint: "⇧⌘A", icon: "rectangle.stack.badge.person.crop")) { $0.newDesk() },
        ui("companion", "开关伴写：停笔时页边偶尔出现一句提问或思路（小模型）",
           PaletteInfo(label: { "伴写：" + ($0.prefs.companionOn ? "关闭" : "开启") }, icon: "sparkle.text.clipboard")) { $0.toggleCompanion() },
        ui("note.review", "让 agent 审阅当前笔记，在正文旁留下批注（不改动笔记）",
           PaletteInfo(label: { m in "AI 审阅：让 \(m.agents.agentPick.displayName) 批注这篇笔记" }, icon: "text.bubble",
                       visible: { $0.editor.activeRel != nil && $0.activeNote?.isHTML != true })) { $0.startAIReview() },
        ui("note.annotations.clear", "忽略当前笔记上的全部批注",
           PaletteInfo(label: { _ in "忽略全部批注" }, icon: "xmark.bubble", visible: { !$0.visibleAnnotations.isEmpty })) { $0.dismissAllAnnotations() },
        ui("notes.summarize", "为还没有最新摘要的笔记生成 AI 摘要（小模型，分批，每天有上限）",
           PaletteInfo(label: { m in m.summarizing.map { "正在生成摘要 \($0.done)/\($0.total)…" } ?? "为笔记生成 AI 摘要" },
                       icon: "text.badge.star")) { $0.summarizeNotes() },
        ui("note.info", "查看和编辑当前笔记的名片（摘要、标签）",
           PaletteInfo(label: { _ in "笔记信息与摘要" }, hint: "⌘I", icon: "info.circle", visible: { $0.editor.activeRel != nil })) { $0.chrome.panelOrigin = nil; $0.chrome.noteInfoOpen = true },
        ui("settings.agent", "打开 Agent 与 CLI 设置",
           PaletteInfo(label: { _ in "Agent 与 CLI 设置" }, hint: "⌘,", icon: "gearshape")) { $0.openSettings(.agent) },
        ui("vault.choose", "选择另一个库", PaletteInfo(label: { _ in "打开其他库…" }, hint: "⌘O", icon: "folder")) { $0.chooseVault() },
        ui("onboarding", "重新运行新手引导", PaletteInfo(label: { _ in "重新运行新手引导" }, icon: "hand.wave")) { $0.chrome.onboardingStep = 0 },
    ]
}

extension AppModel {
    /// The index brought up to date with the disk (walked off the main thread) and with the
    /// editor's unsaved text; `body` runs on the main thread.
    func withFreshIndex(_ body: @escaping @MainActor (Result<(VaultIndex, Vault), RPCError>) -> Void) {
        guard let v = vault else { return body(.failure(RPCError(RPCError.noVault, "共笔没有打开任何库"))) }
        v.refresh { [weak self] fresh in
            guard let self, self.vault === v else { return body(.failure(RPCError(RPCError.noVault, "共笔没有打开任何库"))) }
            var index = fresh
            if self.editor.dirty, let rel = self.editor.activeRel { index.update(rel, text: self.editor.editorText) }
            body(.success((index, v)))
        }
    }

    func contextJSON(session: AgentSession?, index: VaultIndex, vault v: Vault) -> JSONValue {
        var out: [String: JSONValue] = [
            "vault": .string(v.rootPath),
            "protocol": JSONValue(RPC.protocolVersion),
            "pending": .array(agents.pending.values.sorted { $0.rel < $1.rel }.map { p in
                ["path": .string(p.rel), "by": JSONValue(p.by?.displayName), "plus": JSONValue(p.plus), "minus": JSONValue(p.minus)]
            }),
            "note": .null,
        ]
        if let session {
            out["session"] = ["id": .string(session.id.uuidString), "agent": .string(session.agent.rawValue), "title": .string(session.title)]
        }
        guard let rel = editor.activeRel else { return .object(out) }
        var note = EditorContext.describe(text: editor.editorText, selection: editor.editorSelection)
        note["path"] = .string(rel)
        note["title"] = .string(((rel as NSString).lastPathComponent as NSString).deletingPathExtension)
        note["unsaved"] = .bool(editor.dirty)
        note["backlinks"] = .array(index.backlinks(to: rel).prefix(20).map { h in
            ["path": .string(h.rel), "line": JSONValue(h.line ?? 0), "text": .string(h.text)]
        })
        note["pendingReview"] = .bool(agents.pending[rel] != nil)
        out["note"] = .object(note)
        return .object(out)
    }
}
