import Foundation

/// The Model Context Protocol side of `plume mcp`: newline-delimited JSON-RPC on stdio, answering
/// `initialize`, `tools/list` and `tools/call`. Each tool call is handed to `call`, which in the CLI
/// forwards it to the app (or answers from files), so this type holds only protocol logic.
public final class MCPServer {
    public typealias Call = (_ spec: CommandSpec, _ params: [String: JSONValue]) -> Result<JSONValue, RPCError>

    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let tools: [CommandSpec]
    let version: String
    let call: Call

    public init(tools: [CommandSpec] = PlumeCommands.mcpTools, version: String, call: @escaping Call) {
        self.tools = tools
        self.version = version
        self.call = call
    }

    public static let instructions = """
    Plume 是用户正在使用的 Markdown 笔记应用，当前目录就是笔记库。
    - 用户说“这段”“这里”“这一节”“我选中的”时，先调用 context 看用户选了什么、光标在哪。
    - 修改笔记优先用 propose_edit：改动进入用户的审阅，每处都写明理由；wait=true 可以拿到审阅结果和拒绝原因。
    - 拿不准用户想要什么时，用 ask_user 问，不要猜。
    """

    /// Answers one incoming line; nil for notifications and for lines that need no reply.
    public func handle(_ line: Data) -> Data? {
        guard let msg = try? JSONDecoder().decode(JSONValue.self, from: line), let method = msg["method"]?.string else {
            return reply(nil, error: RPCError(RPCError.parse, "不是合法的 JSON-RPC 消息"))
        }
        let id = msg["id"]
        guard let id, !id.isNull else { return nil }   // notifications/initialized and friends
        let params = msg["params"]?.object ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.string ?? ""
            return reply(id, result: [
                "protocolVersion": .string(Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "plume", "version": .string(version)],
                "instructions": .string(Self.instructions),
            ])
        case "ping":
            return reply(id, result: [:])
        case "tools/list":
            return reply(id, result: ["tools": .array(tools.map(Self.tool))])
        case "tools/call":
            guard let name = params["name"]?.string, let spec = tools.first(where: { $0.mcpName == name }) else {
                return reply(id, error: RPCError(RPCError.invalidParams, "没有工具 \(params["name"]?.string ?? "")"))
            }
            let args = params["arguments"]?.object ?? [:]
            let outcome: Result<JSONValue, RPCError>
            do {
                try spec.validate(args)
                outcome = call(spec, args)
            } catch let e as RPCError {
                outcome = .failure(e)
            } catch {
                outcome = .failure(RPCError(RPCError.internalError, error.localizedDescription))
            }
            switch outcome {
            case let .success(v):
                return reply(id, result: ["content": [["type": "text", "text": .string(Render.text(spec.id, v))]],
                                          "structuredContent": v.object == nil ? ["result": v] : v, "isError": false])
            case let .failure(e):
                // Tool failures go back as results so the model can read them and adjust.
                return reply(id, result: ["content": [["type": "text", "text": .string(e.message)]], "isError": true])
            }
        default:
            return reply(id, error: RPCError(RPCError.methodNotFound, "不支持的方法 \(method)"))
        }
    }

    public static func tool(_ spec: CommandSpec) -> JSONValue {
        var props: [String: JSONValue] = [:]
        for p in spec.params {
            var s: JSONValue
            switch p.kind {
            case .string: s = ["type": "string"]
            case .int: s = ["type": "integer"]
            case .bool: s = ["type": "boolean"]
            case .strings: s = ["type": "array", "items": ["type": "string"]]
            case .json: s = p.schema ?? [:]
            }
            if case var .object(o) = s {
                o["description"] = .string(p.help)
                s = .object(o)
            }
            props[p.name] = s
        }
        var annotations: [String: JSONValue] = ["readOnlyHint": .bool(spec.effect == .read)]
        if spec.effect != .read { annotations["destructiveHint"] = false }
        return [
            "name": .string(spec.mcpName ?? spec.id),
            "description": .string(spec.summary),
            "inputSchema": ["type": "object", "properties": .object(props),
                            "required": JSONValue(spec.params.filter(\.required).map(\.name))],
            "annotations": .object(annotations),
        ]
    }

    func reply(_ id: JSONValue?, result: JSONValue) -> Data {
        encode(["jsonrpc": "2.0", "id": id ?? .null, "result": result])
    }

    func reply(_ id: JSONValue?, error: RPCError) -> Data {
        encode(["jsonrpc": "2.0", "id": id ?? .null, "error": ["code": JSONValue(error.code), "message": .string(error.message)]])
    }

    func encode(_ v: JSONValue) -> Data {
        var d = v.encoded()
        d.append(0x0A)
        return d
    }
}
