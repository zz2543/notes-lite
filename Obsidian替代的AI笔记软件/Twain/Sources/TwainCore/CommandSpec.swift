import Foundation

/// How much a command can change: decides whether it runs straight away or goes through the user.
public enum CommandEffect: String, Codable, Sendable {
    /// Reads the vault or the editor state.
    case read
    /// Moves the user's view (opens a note, shows a message) without touching files.
    case ui
    /// Hands the user something to decide on (a change to review, a question).
    case propose
    /// Changes files.
    case write
}

public struct ParamSpec: Codable, Equatable, Sendable {
    /// `json` takes any JSON value; on the command line it is written as JSON text.
    public enum Kind: String, Codable, Sendable { case string, int, bool, strings, json }

    public var name: String
    public var kind: Kind
    public var required: Bool
    /// Taken from the first bare argument on the command line (`twain search 关键词`).
    public var positional: Bool
    public var help: String
    /// JSON Schema for `json` params, so MCP clients know the shape.
    public var schema: JSONValue?

    public init(_ name: String, _ kind: Kind = .string, required: Bool = false, positional: Bool = false, help: String,
                schema: JSONValue? = nil) {
        self.name = name
        self.kind = kind
        self.required = required
        self.positional = positional
        self.help = help
        self.schema = schema
    }
}

/// What a command is, independent of who runs it. One spec yields the CLI's help and
/// argument parsing, the socket method, and (later) the MCP tool schema.
public struct CommandSpec: Codable, Equatable, Sendable {
    public var id: String
    public var summary: String
    public var params: [ParamSpec]
    public var effect: CommandEffect
    /// False when the CLI can answer from the files alone while the app is closed.
    public var needsApp: Bool
    /// The tool name agents see over MCP; nil keeps the command off MCP.
    public var mcpName: String?

    public init(_ id: String, _ summary: String, effect: CommandEffect, needsApp: Bool = true, mcp: String? = nil,
                params: [ParamSpec] = []) {
        self.id = id
        self.summary = summary
        self.effect = effect
        self.needsApp = needsApp
        self.mcpName = mcp
        self.params = params
    }

    public var usage: String {
        var parts = ["twain", id]
        for p in params {
            let flag: String
            if p.positional {
                flag = "<\(p.name)>"
            } else {
                switch p.kind {
                case .bool: flag = "--\(p.name)"
                case .int: flag = "--\(p.name) N"
                case .string, .strings, .json: flag = "--\(p.name) <\(p.name)>"
                }
            }
            parts.append(p.required ? flag : "[\(flag)]")
        }
        return parts.joined(separator: " ")
    }

    public var help: String {
        var lines = [usage, "  " + summary]
        if !params.isEmpty { lines.append("") }
        for p in params {
            let name = p.positional ? "<\(p.name)>" : "--\(p.name)"
            lines.append("  " + name.padding(toLength: max(14, name.count + 2), withPad: " ", startingAt: 0) + p.help)
        }
        return lines.joined(separator: "\n")
    }

    /// Turns `twain <id> …` arguments into params. Unknown `--flags` pass through as strings,
    /// so commands the app registers later work before the CLI knows their spec.
    public func parse(_ args: [String]) throws -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        var bare: [String] = []
        var i = 0
        func spec(_ name: String) -> ParamSpec? { params.first { $0.name == name } }
        while i < args.count {
            let a = args[i]
            i += 1
            guard a.hasPrefix("--"), a.count > 2 else { bare.append(a); continue }
            var name = String(a.dropFirst(2))
            var value: String?
            if let eq = name.firstIndex(of: "=") {
                value = String(name[name.index(after: eq)...])
                name = String(name[..<eq])
            }
            let p = spec(name)
            if p?.kind == .bool {
                out[name] = try value.map { try Self.convert($0, to: .bool, name: "--" + name, into: nil) } ?? .bool(true)
                continue
            }
            if value == nil {
                guard i < args.count else { throw RPCError(RPCError.invalidParams, "--\(name) 缺少取值") }
                value = args[i]
                i += 1
            }
            out[name] = try Self.convert(value!, to: p?.kind ?? .string, name: name, into: out[name])
        }
        let positional = params.filter { $0.positional && out[$0.name] == nil }
        // Let `twain search 两个 词` mean one query instead of failing.
        if let last = positional.last, last.kind == .string, bare.count > positional.count {
            bare = Array(bare.prefix(positional.count - 1)) + [bare.dropFirst(positional.count - 1).joined(separator: " ")]
        }
        guard bare.count <= positional.count else {
            throw RPCError(RPCError.invalidParams, "多余的参数：" + bare.dropFirst(positional.count).joined(separator: " "))
        }
        for (p, v) in zip(positional, bare) {
            out[p.name] = try Self.convert(v, to: p.kind, name: p.name, into: nil)
        }
        return out
    }

    /// Checks params received over the socket against the spec.
    public func validate(_ params: [String: JSONValue]) throws {
        for p in self.params {
            guard let v = params[p.name], !v.isNull else {
                if p.required { throw RPCError(RPCError.invalidParams, "缺少参数 \(p.name)") }
                continue
            }
            let ok: Bool
            switch p.kind {
            case .string: ok = v.string != nil
            case .int: ok = v.int != nil
            case .bool: ok = v.bool != nil
            case .strings: ok = v.array?.allSatisfy { $0.string != nil } ?? false
            case .json: ok = true
            }
            if !ok { throw RPCError(RPCError.invalidParams, "参数 \(p.name) 应为 \(p.kind.rawValue)") }
        }
    }

    static func convert(_ s: String, to kind: ParamSpec.Kind, name: String, into existing: JSONValue?) throws -> JSONValue {
        switch kind {
        case .string: return .string(s)
        case .bool:
            guard let b = ["true": true, "1": true, "yes": true, "false": false, "0": false, "no": false][s.lowercased()] else {
                throw RPCError(RPCError.invalidParams, "\(name) 需要 true 或 false")
            }
            return .bool(b)
        case .int:
            guard let n = Int(s) else { throw RPCError(RPCError.invalidParams, "--\(name) 需要整数") }
            return JSONValue(n)
        case .strings:
            let items = s.split(separator: ",").map { JSONValue.string(String($0).trimmingCharacters(in: .whitespaces)) }
            return .array((existing?.array ?? []) + items)
        case .json:
            guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) else {
                throw RPCError(RPCError.invalidParams, "\(name) 需要 JSON")
            }
            return v
        }
    }
}

/// The commands every Twain understands. The app may register more; `twain commands` lists them all.
public enum TwainCommands {
    static func noteParam(_ required: Bool) -> ParamSpec {
        ParamSpec("note", required: required, positional: true,
                  help: required ? "笔记标题或路径" : "笔记标题或路径；省略时为用户当前打开的笔记")
    }

    public static let context = CommandSpec(
        "context", "用户此刻在共笔里的状态：当前笔记、选中的文字、光标所在标题、反链、待审阅的改动。"
            + "用户说“这段”“这里”“这一节”时先调用它。", effect: .read, mcp: "context")
    public static let notes = CommandSpec(
        "notes", "列出库里的笔记。", effect: .read, needsApp: false,
        params: [ParamSpec("folder", help: "只列这个文件夹（含子文件夹）")])
    public static let search = CommandSpec(
        "search", "全文搜索，标题命中排在前面。多个词需同时出现在同一行。", effect: .read, needsApp: false, mcp: "search",
        params: [ParamSpec("query", required: true, positional: true, help: "要找的词"),
                 ParamSpec("limit", .int, help: "最多返回几条，默认 20")])
    public static let backlinks = CommandSpec(
        "backlinks", "哪些笔记用 [[双链]] 链接到了这篇笔记，附上所在行。", effect: .read, needsApp: false, mcp: "backlinks",
        params: [noteParam(false)])
    public static let outline = CommandSpec(
        "outline", "一篇笔记的标题、待办和出链，带行号。", effect: .read, needsApp: false,
        params: [noteParam(false)])
    public static let skim = CommandSpec(
        "skim", "浏览笔记的“名片”：标题、标签、主要标题和一句话摘要，不读正文。在一个范围里找资料时先用它，"
            + "看准了再用 read_note 按层级读。", effect: .read, needsApp: false, mcp: "skim",
        params: [ParamSpec("folder", help: "只看这个文件夹（含子文件夹）"),
                 ParamSpec("tag", help: "只看带这个标签的笔记"),
                 ParamSpec("query", positional: true, help: "标题、标签或摘要里包含的词"),
                 ParamSpec("limit", .int, help: "最多返回几张，默认 60")])
    public static let read = CommandSpec(
        "read", "分级读一篇笔记：level 1 是名片，2 是提纲（每节的行号、长度和开头一句），3 是全文（带行号）。"
            + "给 section 时只读那一节。从低到高按需读，省上下文。", effect: .read, needsApp: false, mcp: "read_note",
        params: [noteParam(true),
                 ParamSpec("level", .int, help: "1 名片 · 2 提纲 · 3 全文，默认 2"),
                 ParamSpec("section", help: "只读这个标题下的一节（level 3）")])
    public static let tasks = CommandSpec(
        "tasks", "全库的待办事项，默认只列未完成的。", effect: .read, needsApp: false, mcp: "tasks",
        params: [ParamSpec("folder", help: "只看这个文件夹"),
                 ParamSpec("tag", help: "只看带这个 #标签 的笔记"),
                 ParamSpec("done", .bool, help: "也列出已完成的")])
    public static let open = CommandSpec(
        "open", "在共笔里打开一篇笔记给用户看，可定位到行或标题。", effect: .ui, mcp: "open",
        params: [noteParam(true),
                 ParamSpec("line", .int, help: "定位到第几行（从 1 开始）"),
                 ParamSpec("heading", help: "定位到这个标题")])
    public static let reveal = CommandSpec(
        "reveal", "在侧栏中定位一篇笔记。", effect: .ui,
        params: [noteParam(true)])
    public static let notify = CommandSpec(
        "notify", "在共笔里给用户显示一条消息；由共笔启动的 agent 调用时，也会记进会话。", effect: .ui,
        params: [ParamSpec("message", required: true, positional: true, help: "消息内容")])
    public static let propose = CommandSpec(
        "propose", "提议修改（或新建）一篇笔记。改动不会直接写入：用户在共笔里逐段审阅，接受的部分才写进文件。"
            + "每处改动都应说明理由。用 content 给出整篇新内容，或用 edits 给出若干处替换。",
        effect: .propose, mcp: "propose_edit",
        params: [noteParam(true),
                 ParamSpec("content", help: "整篇笔记的新内容（与 edits 二选一；命令行里写 - 表示从标准输入读取）"),
                 ParamSpec("edits", .json, help: #"若干处替换：[{"old": 原文片段, "new": 新文字, "reason": 理由}]，原文片段须在笔记中唯一出现"#,
                           schema: ["type": "array", "items": ["type": "object", "required": ["old", "new"], "properties": [
                               "old": ["type": "string", "description": "要替换的原文，须在笔记中唯一出现"],
                               "new": ["type": "string", "description": "替换成的文字"],
                               "reason": ["type": "string", "description": "这一处为什么这样改"],
                           ]]]),
                 ParamSpec("reason", help: "这次修改的整体理由"),
                 ParamSpec("notes", .json, help: #"用 content 时逐段说明理由：[{"line": 新内容中的行号, "text": 理由}]"#,
                           schema: ["type": "array", "items": ["type": "object", "required": ["line", "text"], "properties": [
                               "line": ["type": "integer", "description": "新内容中的行号，从 1 开始"],
                               "text": ["type": "string"],
                           ]]]),
                 ParamSpec("wait", .bool, help: "等用户审阅完再返回，结果里有每处改动是否被接受及拒绝原因")])
    public static let ask = CommandSpec(
        "ask", "在共笔里向用户提一个问题并等待回答。拿不准用户意图、需要用户在几个方案里选一个时使用。",
        effect: .propose, mcp: "ask_user",
        params: [ParamSpec("question", required: true, positional: true, help: "问题"),
                 ParamSpec("options", .strings, help: "可选答案（命令行里用逗号分隔）"),
                 ParamSpec("text", .bool, help: "允许用户自己输入回答（没有 options 时总是允许）"),
                 ParamSpec("timeout", .int, help: "最多等多少秒，默认 600")])
    public static let reviews = CommandSpec(
        "reviews", "最近处理过的修改提案：哪些改动被接受、哪些被拒绝，以及用户写的拒绝原因。", effect: .read, needsApp: false,
        params: [ParamSpec("limit", .int, help: "最多返回几条，默认 20")])
    public static let run = CommandSpec(
        "run", "运行库里的一条自定义命令（.twain/commands/ 下的文件），在共笔中启动一次 agent 会话。",
        effect: .propose, mcp: "run_command",
        params: [ParamSpec("name", required: true, positional: true, help: "命令名（文件名或 key）"),
                 ParamSpec("input", help: "填入命令模板中 {{input}} 的内容")])
    public static let watch = CommandSpec(
        "watch", "持续输出共笔里发生的事件，每行一个 JSON。", effect: .read,
        params: [ParamSpec("events", .strings, help: "只看这些事件，逗号分隔；可用事件见 twain help watch")])
    public static let commands = CommandSpec(
        "commands", "列出所有可用命令，包括 app 里注册的。", effect: .read, needsApp: false)

    public static let all: [CommandSpec] = [context, notes, search, skim, read, backlinks, outline, tasks, open, reveal, notify,
                                            propose, ask, reviews, run, watch, commands, annotate, annotations, cards] + dataCommands

    public static func spec(_ id: String) -> CommandSpec? { all.first { $0.id == id } }

    /// Tools only runs that need them get (an AI review gets `annotate`), so the default set stays small.
    public static let optionalMCP: Set<String> = ["annotate", "cards"]

    /// What agents get over MCP. Kept short on purpose: every tool costs context and attention.
    public static var mcpTools: [CommandSpec] { mcpTools(extra: []) }

    public static func mcpTools(extra: [String]) -> [CommandSpec] {
        all.filter { $0.mcpName != nil && (!optionalMCP.contains($0.id) || extra.contains($0.id)) }
    }
}

/// Events the app reports through `twain watch` and feeds to automations.
public enum TwainEvents {
    public static let all: [(String, String)] = [
        ("note.opened", "用户打开了一篇笔记"),
        ("note.saved", "用户保存了笔记"),
        ("note.changed", "笔记在共笔之外被修改（终端里的 agent、同步、其他编辑器）"),
        ("note.created", "新建了笔记"),
        ("note.deleted", "删除了笔记"),
        ("note.renamed", "用户重命名了笔记（from 是原路径）"),
        ("proposal.created", "agent 提交了修改提案"),
        ("review.resolved", "用户处理完一次审阅"),
        ("session.started", "共笔中的 agent 会话开始运行"),
        ("session.finished", "agent 会话运行结束"),
        ("selection.changed", "用户的选区变化（需显式订阅，节流 500 毫秒）"),
        ("data.added", "数据集合新增了记录（collection、count）"),
        ("note.imported", "外部程序通过接口导入了一篇笔记"),
        ("annotation.created", "agent 在笔记上留下了批注"),
        ("annotation.resolved", "用户处理了一条批注"),
    ]
    public static var names: [String] { all.map(\.0) }
    /// Sent only to those who ask for them by name.
    public static let optIn: Set<String> = ["selection.changed"]
}

public extension CommandSpec {
    /// Reads back what `json` wrote, for commands only the app knows about.
    init?(json j: JSONValue) {
        guard let id = j["id"]?.string, let effect = j["effect"]?.string.flatMap(CommandEffect.init(rawValue:)) else { return nil }
        let params = (j["params"]?.array ?? []).compactMap { p -> ParamSpec? in
            guard let name = p["name"]?.string, let kind = p["kind"]?.string.flatMap(ParamSpec.Kind.init(rawValue:)) else { return nil }
            return ParamSpec(name, kind, required: p["required"]?.bool ?? false, positional: p["positional"]?.bool ?? false,
                             help: p["help"]?.string ?? "")
        }
        self.init(id, j["summary"]?.string ?? "", effect: effect, needsApp: j["needsApp"]?.bool ?? true,
                  mcp: j["mcp"]?.string, params: params)
    }

    var json: JSONValue {
        .object([
            "id": .string(id), "summary": .string(summary), "effect": .string(effect.rawValue),
            "needsApp": .bool(needsApp), "usage": .string(usage), "mcp": mcpName.map(JSONValue.string) ?? .null,
            "params": .array(params.map { p in
                .object(["name": .string(p.name), "kind": .string(p.kind.rawValue), "required": .bool(p.required),
                         "positional": .bool(p.positional), "help": .string(p.help)])
            }),
        ])
    }
}
