import Foundation

/// Command lines for `claude -p` and `codex exec`, kept apart from process handling so they can be tested.
public enum AgentArguments {
    /// How the agent starts `plume mcp` as its MCP server.
    public struct MCP: Equatable, Sendable {
        public var command: String
        public var env: [String: String]
        /// Longest a tool call may block, for questions and `wait`ing proposals.
        public var timeout: Int

        public init(command: String, env: [String: String], timeout: Int = 900) {
            self.command = command
            self.env = env
            self.timeout = timeout
        }
    }

    /// `model` / `effort` nil or empty leave the choice to the CLI's own configuration.
    /// `socket` is Plume's socket, which the agent's `plume` command must be able to reach.
    /// `version` is what the CLI's `--version` printed; it decides whether Codex can be told to let the socket through.
    /// `readOnly` runs may not touch files at all: their only way to change a note is a proposal.
    public static func build(kind: AgentKind, prompt: String, context: String, root: String, resume: String?,
                             model: String? = nil, effort: String? = nil, socket: String? = nil, version: String? = nil,
                             mcp: MCP? = nil, readOnly: Bool = false) -> [String] {
        let model = model.flatMap { $0.isEmpty ? nil : $0 }
        let effort = effort.flatMap { $0.isEmpty ? nil : $0 }
        switch kind {
        case .claude:
            // `-p` denies every tool not allowed here: acceptEdits lets file edits through, and the
            // list lets `plume` and Plume's MCP tools through. Read-only runs keep only the latter.
            let allowed = ["Bash(plume:*)"] + (mcp == nil ? [] : ["mcp__plume"])
            var a = ["-p", prompt, "--output-format", "stream-json", "--verbose",
                     "--permission-mode", readOnly ? "default" : "acceptEdits", "--allowedTools", allowed.joined(separator: ","),
                     "--append-system-prompt", context]
            if let mcp { a += ["--mcp-config", claudeMCPConfig(mcp)] }
            if let model { a += ["--model", model] }
            if let effort { a += ["--effort", effort] }
            if let resume { a += ["--resume", resume] }
            return a
        case .codex:
            let full = context + "\n\n" + prompt
            let sandbox = readOnly ? "read-only" : "workspace-write"
            let m = (model.map { ["-m", $0] } ?? []) + (effort.map { ["-c", "model_reasoning_effort=\"\($0)\""] } ?? [])
            let net = readOnly ? [] : socket.flatMap { codexProxyWorks(version) ? codexSocketAccess($0) : nil } ?? []
            let tools = mcp.map(codexMCP) ?? []
            if let resume {
                return ["exec", "resume", resume, "--json", "--skip-git-repo-check",
                        "-c", "sandbox_mode=\"\(sandbox)\""] + net + tools + m + [full]
            }
            return ["exec", "--json", "-s", sandbox, "--skip-git-repo-check", "-C", root] + net + tools + m + [full]
        }
    }

    static func claudeMCPConfig(_ mcp: MCP) -> String {
        let server: JSONValue = ["type": "stdio", "command": .string(mcp.command), "args": ["mcp"],
                                 "env": .object(mcp.env.mapValues(JSONValue.string))]
        return JSONValue.object(["mcpServers": ["plume": server]]).text()
    }

    static func codexMCP(_ mcp: MCP) -> [String] {
        let env = mcp.env.sorted { $0.key < $1.key }.map { "\($0.key)=\(tomlString($0.value))" }.joined(separator: ",")
        return ["-c", "mcp_servers.plume.command=\(tomlString(mcp.command))",
                "-c", "mcp_servers.plume.args=[\"mcp\"]",
                "-c", "mcp_servers.plume.env={\(env)}",
                "-c", "mcp_servers.plume.tool_timeout_sec=\(mcp.timeout)",
                // `codex exec` never asks, so a tool that needs approval is simply refused. Plume's
                // tools need none: every change they carry still waits for the user in review.
                "-c", "mcp_servers.plume.default_tools_approval_mode=\"approve\""]
    }

    static func tomlString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The oldest Codex these flags were tried on. Earlier versions may ignore the proxy settings
    /// yet honour `network_access=true`, which would open the whole network, so they get neither.
    public static let codexProxyMinimum = "0.157.0"

    /// False also when the version is unknown: without the flags `plume` still reads files, just not the app.
    public static func codexProxyWorks(_ version: String?) -> Bool {
        guard let version, version.range(of: #"\d+(\.\d+)+"#, options: .regularExpression) != nil else { return false }
        return !versionIsOlder(version, than: codexProxyMinimum)
    }

    /// Codex's workspace-write sandbox refuses every socket. Routing its network through Codex's own
    /// proxy lets exactly Plume's socket through while every web domain stays blocked (the proxy's
    /// domain allowlist is empty).
    static func codexSocketAccess(_ socket: String) -> [String] {
        ["-c", "sandbox_workspace_write.network_access=true",
         "-c", "features.network_proxy.enabled=true",
         "-c", "features.network_proxy.unix_sockets={\(tomlString(socket))=\"allow\"}"]
    }
}
