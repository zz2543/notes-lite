import Darwin
import Foundation
import TwainCore

// `twain <command> [args] [--json]`: asks the running Twain app over its socket, or answers
// read commands from the files when the app is closed. `twain mcp` serves the same commands
// to agents over MCP; `twain watch` streams the app's events.
//
// Exit codes: 0 ok · 1 the command failed · 2 bad usage · 3 needs the app, which is not running.

let version = "0.2.0"
let env = ProcessInfo.processInfo.environment
let socketPath = env["TWAIN_SOCK"] ?? RPC.defaultSocketPath

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(("twain: " + message + "\n").utf8))
    exit(code)
}

func out(_ s: String) {
    FileHandle.standardOutput.write(Data((s.hasSuffix("\n") || s.isEmpty ? s : s + "\n").utf8))
}

var args = Array(CommandLine.arguments.dropFirst())
func takeFlag(_ f: String) -> Bool {
    guard let i = args.firstIndex(of: f) else { return false }
    args.remove(at: i)
    return true
}
let asJSON = takeFlag("--json")
let forceOffline = takeFlag("--offline")

let overview = """
twain — 让 agent 使用共笔笔记库的命令行工具

用法：twain <命令> [参数] [--json]

\(TwainCommands.all.map { "  " + $0.id.padding(toLength: 11, withPad: " ", startingAt: 0) + $0.summary }.joined(separator: "\n"))
  mcp        以 MCP 服务器方式运行（供 Claude Code、Codex 等 agent 挂载）

  twain help <命令>   查看某个命令的参数
  --json              输出 JSON 而不是文本
  --offline           不连接共笔，直接读文件（只支持只读命令）

共笔没有运行时，notes / search / backlinks / outline / tasks / reviews 仍可在库目录里使用。
"""

if args.first == "--version" || args.first == "-v" {
    out("twain \(version) (protocol \(RPC.protocolVersion))")
    exit(0)
}
if args.isEmpty || args.first == "--help" || args.first == "-h" {
    out(overview)
    exit(0)
}
if args.first == "help" {
    guard args.count > 1 else { out(overview); exit(0) }
    guard let spec = TwainCommands.spec(args[1]) else { fail("没有命令 \(args[1])，运行 twain commands 查看全部", code: 2) }
    out(spec.help)
    if spec.id == "watch" {
        out("\n事件：\n" + TwainEvents.all.map { "  " + $0.0.padding(toLength: 18, withPad: " ", startingAt: 0) + $0.1 }.joined(separator: "\n"))
    }
    exit(0)
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let vaultRoot = findVaultRoot(from: cwd)
let caller = RPCCaller(session: env["TWAIN_SESSION"], pid: getppid(), vault: vaultRoot?.path)

/// Answers `spec` from the files alone.
func offline(_ spec: CommandSpec, _ params: [String: JSONValue]) throws -> JSONValue {
    if spec.id == "commands" { return ["commands": .array(TwainCommands.all.map(\.json))] }
    guard !spec.needsApp, VaultQueries.ids.contains(spec.id) else {
        throw RPCError(RPCError.appNotRunning, "共笔没有运行，\(spec.id) 需要打开共笔")
    }
    guard let root = vaultRoot else {
        throw RPCError(RPCError.appNotRunning, "共笔没有运行，当前目录也不在任何库里（找不到 .twain/）")
    }
    let index = VaultIndex(root: root)
    index.refresh()
    return try VaultQueries.run(spec.id, params, index: index, current: nil)
}

func attempt(_ f: () throws -> JSONValue) -> Result<JSONValue, RPCError> {
    do { return .success(try f()) } catch let e as RPCError { return .failure(e) } catch {
        return .failure(RPCError(RPCError.internalError, error.localizedDescription))
    }
}

/// How long to wait for the app: questions and `wait`ing proposals wait for the user.
func timeout(_ spec: CommandSpec, _ params: [String: JSONValue]) -> TimeInterval {
    switch spec.id {
    case "ask": return TimeInterval((params["timeout"]?.int ?? 600) + 30)
    case "propose" where params["wait"]?.bool == true: return 6 * 3600
    case _ where spec.id.hasPrefix("debug."): return 900
    default: return 30
    }
}

/// Runs one command against the app, falling back to the files where that gives the same answer.
func invoke(_ spec: CommandSpec, _ params: [String: JSONValue]) -> Result<JSONValue, RPCError> {
    if forceOffline { return attempt { try offline(spec, params) } }
    let req = RPCRequest(id: 1, method: spec.id, params: params, caller: caller)
    switch UnixSocket.call(req, path: socketPath, timeout: timeout(spec, params)) {
    case let .success(resp):
        if let e = resp.error {
            // The app has a different vault open: read commands can still answer from this one.
            if e.code == RPCError.otherVault, !spec.needsApp, VaultQueries.ids.contains(spec.id) {
                return attempt { try offline(spec, params) }
            }
            return .failure(e)
        }
        return .success(resp.result ?? .null)
    case .failure(.unreachable):
        return attempt { try offline(spec, params) }
    case .failure(.denied):
        // Read commands still work from the files; the rest need the socket the sandbox blocks.
        if !spec.needsApp, VaultQueries.ids.contains(spec.id) { return attempt { try offline(spec, params) } }
        return .failure(RPCError(RPCError.appNotRunning,
                                 "连接共笔被拒绝：当前环境（很可能是 agent 的沙箱）不允许访问本地 socket \(socketPath)"))
    case let .failure(.broken(why)):
        return .failure(RPCError(RPCError.internalError, why))
    }
}

// MARK: twain mcp

if args.first == "mcp" {
    // A run may be given extra tools (an AI review gets `annotate`) through TWAIN_MCP_EXTRA.
    let extra = (env["TWAIN_MCP_EXTRA"] ?? "").split(separator: ",").map(String.init)
    let server = MCPServer(tools: TwainCommands.mcpTools(extra: extra), version: version) { spec, params in invoke(spec, params) }
    let lock = NSLock()
    var buffer = Data()
    let input = FileHandle.standardInput
    while true {
        let chunk = input.availableData
        if chunk.isEmpty { exit(0) }   // the agent closed our stdin: it is done with us
        buffer.append(chunk)
        for line in RPC.drainLines(&buffer) {
            // Tool calls can wait on the user for minutes; keep answering pings meanwhile.
            DispatchQueue.global().async {
                guard let reply = server.handle(line) else { return }
                lock.lock()
                FileHandle.standardOutput.write(reply)
                lock.unlock()
            }
        }
    }
}

// MARK: twain <command>

let id = args.removeFirst()
if args.contains("--help") || args.contains("-h") {
    if let spec = TwainCommands.spec(id) { out(spec.help); exit(0) }
}
/// A command only the app knows (its own, or a newer Twain's): ask it for the spec.
func appSpec(_ id: String) -> CommandSpec? {
    let req = RPCRequest(id: 1, method: "commands", caller: caller)
    guard case let .success(resp) = UnixSocket.call(req, path: socketPath, timeout: 5) else { return nil }
    return (resp.result?["commands"]?.array ?? []).lazy.compactMap(CommandSpec.init(json:)).first { $0.id == id }
}

// Unknown to both: flags still pass through as strings, and the app says what is wrong.
let spec = TwainCommands.spec(id) ?? appSpec(id) ?? CommandSpec(id, "", effect: .ui)
if args.contains("--help") || args.contains("-h") { out(spec.help); exit(0) }
var params: [String: JSONValue]
do {
    params = try spec.parse(args)
    // `--content -` reads the new text from stdin, so agents can pipe a whole note in.
    if spec.id == "propose", params["content"]?.string == "-" {
        params["content"] = .string(String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self))
    }
    try spec.validate(params)
} catch let e as RPCError {
    fail(e.message + "\n\n" + spec.help, code: 2)
} catch {
    fail(error.localizedDescription, code: 2)
}

if spec.id == "watch" {
    let req = RPCRequest(id: 1, method: "watch", params: params, caller: caller)
    var started = false
    let problem = UnixSocket.stream(req, path: socketPath) { line in
        guard let msg = try? JSONDecoder().decode(JSONValue.self, from: line) else { return true }
        if !started {
            started = true
            if let e = msg["error"] { fail(e["message"]?.string ?? "订阅失败", code: 1) }
            let names = (msg["result"]?["watching"]?.array ?? []).compactMap(\.string)
            FileHandle.standardError.write(Data("twain: 正在监听 \(names.joined(separator: ", "))\n".utf8))
            return true
        }
        if msg["method"]?.string == "event", let p = msg["params"] {
            out(p.text())
        }
        return true
    }
    switch problem {
    case nil: fail("共笔已退出", code: 1)
    case .unreachable: fail("共笔没有运行", code: 3)
    case .denied: fail("连接共笔被拒绝：当前环境不允许访问本地 socket \(socketPath)", code: 3)
    case let .broken(why): fail(why, code: 1)
    }
}

switch invoke(spec, params) {
case let .success(result):
    out(asJSON ? result.text(pretty: true) : Render.text(spec.id, result))
case let .failure(e):
    if asJSON { out(JSONValue.object(["error": ["code": JSONValue(e.code), "message": .string(e.message)]]).text(pretty: true)) }
    fail(e.message, code: e.code == RPCError.appNotRunning ? 3 : e.code == RPCError.invalidParams ? 2 : 1)
}
