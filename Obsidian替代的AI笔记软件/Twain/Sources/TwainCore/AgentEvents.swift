import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude, codex

    public var displayName: String { self == .claude ? "Claude Code" : "Codex" }
    public var executable: String { rawValue }
}

/// What Twain shows for a line of CLI output, independent of which CLI produced it.
public enum AgentEvent: Equatable, Sendable {
    case session(String)
    case user(String)
    case text(String)
    /// `write` is the absolute path the step is about to modify, if any.
    case step(id: String, text: String, write: String?)
    case stepDone(id: String)
    case error(String)
    case finished(isError: Bool)
}

public func vaultRelative(_ path: String, root: String) -> String {
    let r = root.hasSuffix("/") ? root : root + "/"
    if path.hasPrefix(r) { return String(path.dropFirst(r.count)) }
    // macOS reports /private/tmp for /tmp and friends.
    if path.hasPrefix("/private" + r) { return String(path.dropFirst(r.count + 8)) }
    return path
}

func truncate(_ s: String, _ n: Int) -> String {
    let one = s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? s
    return one.count > n ? String(one.prefix(n)) + "…" : one
}

func stripShellWrapper(_ cmd: String) -> String {
    for p in ["/bin/zsh -lc ", "/bin/bash -lc ", "bash -lc ", "zsh -lc ", "sh -c "] where cmd.hasPrefix(p) {
        var rest = String(cmd.dropFirst(p.count))
        if let f = rest.first, f == "'" || f == "\"", rest.last == f, rest.count >= 2 {
            rest = String(rest.dropFirst().dropLast())
        }
        return rest
    }
    return cmd
}

func isInjectedContext(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty || t.hasPrefix("<") || t.hasPrefix("# AGENTS.md") || t.hasPrefix("Caveat:")
}

// MARK: - Claude Code (`claude -p --output-format stream-json --verbose`, and ~/.claude transcripts)

public enum ClaudeStream {
    static let writeTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    public static func describe(tool name: String, input: [String: Any], root: String) -> (String, String?) {
        let file = (input["file_path"] as? String) ?? (input["notebook_path"] as? String)
        let rel = file.map { vaultRelative($0, root: root) }
        switch name {
        case "Read": return ("读取 " + (rel ?? ""), nil)
        case _ where writeTools.contains(name): return ("写入 " + (rel ?? ""), file)
        case "Glob": return ("查找 " + ((input["pattern"] as? String) ?? ""), nil)
        case "Grep": return ("搜索 " + ((input["pattern"] as? String) ?? ""), nil)
        case "Bash": return ("$ " + truncate((input["command"] as? String) ?? "", 60), nil)
        case "TodoWrite": return ("更新待办", nil)
        case "WebSearch": return ("网页搜索 " + ((input["query"] as? String) ?? ""), nil)
        case "WebFetch": return ("读取网页 " + ((input["url"] as? String) ?? ""), nil)
        case "Task", "Agent": return ("子任务 " + truncate((input["description"] as? String) ?? "", 40), nil)
        default: return (name, nil)
        }
    }

    /// `transcript` enables user-text events, which only make sense when reading a saved session.
    public static func events(from obj: [String: Any], root: String, transcript: Bool = false) -> [AgentEvent] {
        let type = obj["type"] as? String
        if transcript, (obj["isSidechain"] as? Bool) == true || (obj["isMeta"] as? Bool) == true { return [] }
        switch type {
        case "system":
            if obj["subtype"] as? String == "init", let sid = obj["session_id"] as? String { return [.session(sid)] }
            return []
        case "assistant":
            guard let msg = obj["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] else { return [] }
            var out: [AgentEvent] = []
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let t = block["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.text(t)) }
                case "tool_use":
                    let (text, write) = describe(tool: block["name"] as? String ?? "tool", input: block["input"] as? [String: Any] ?? [:], root: root)
                    out.append(.step(id: block["id"] as? String ?? UUID().uuidString, text: text, write: write))
                default: break
                }
            }
            return out
        case "user":
            guard let msg = obj["message"] as? [String: Any] else { return [] }
            if let s = msg["content"] as? String {
                return transcript && !isInjectedContext(s) ? [.user(s)] : []
            }
            guard let content = msg["content"] as? [[String: Any]] else { return [] }
            var out: [AgentEvent] = []
            for block in content {
                if block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String {
                    out.append(.stepDone(id: id))
                } else if transcript, block["type"] as? String == "text", let t = block["text"] as? String, !isInjectedContext(t) {
                    out.append(.user(t))
                }
            }
            return out
        case "result":
            let isError = (obj["is_error"] as? Bool) ?? false
            var out: [AgentEvent] = []
            if let sid = obj["session_id"] as? String { out.append(.session(sid)) }
            if isError { out.append(.error((obj["result"] as? String) ?? (obj["subtype"] as? String) ?? "Claude Code 运行失败")) }
            out.append(.finished(isError: isError))
            return out
        default:
            return []
        }
    }
}

// MARK: - Codex (`codex exec --json`)

public enum CodexStream {
    static func command(_ item: [String: Any]) -> String {
        if let s = item["command"] as? String { return stripShellWrapper(s) }
        if let a = item["command"] as? [String] {
            if a.count >= 3, a[1] == "-lc" || a[1] == "-c" { return a[2] }
            return a.joined(separator: " ")
        }
        return ""
    }

    static func errorMessage(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = obj["message"] as? String { return m }
        }
        return raw
    }

    static func describe(_ item: [String: Any], root: String) -> (String, String?)? {
        switch item["type"] as? String {
        case "command_execution":
            return ("$ " + truncate(command(item), 60), nil)
        case "file_change":
            let changes = item["changes"] as? [[String: Any]] ?? []
            let paths = changes.compactMap { $0["path"] as? String }
            return ("写入 " + paths.map { vaultRelative($0, root: root) }.joined(separator: ", "), paths.first)
        case "mcp_tool_call":
            return ("工具 " + [item["server"] as? String, item["tool"] as? String].compactMap { $0 }.joined(separator: "."), nil)
        case "web_search":
            return ("网页搜索 " + ((item["query"] as? String) ?? ""), nil)
        default:
            return nil
        }
    }

    public static func events(from obj: [String: Any], root: String) -> [AgentEvent] {
        switch obj["type"] as? String {
        case "thread.started":
            return (obj["thread_id"] as? String).map { [.session($0)] } ?? []
        case "item.started":
            guard let item = obj["item"] as? [String: Any], let id = item["id"] as? String,
                  let (text, write) = describe(item, root: root) else { return [] }
            return [.step(id: id, text: text, write: write)]
        case "item.completed":
            guard let item = obj["item"] as? [String: Any] else { return [] }
            let id = item["id"] as? String ?? UUID().uuidString
            switch item["type"] as? String {
            case "agent_message":
                return (item["text"] as? String).map { [.text($0)] } ?? []
            case "error":
                return [.step(id: id, text: "⚠︎ " + truncate((item["message"] as? String) ?? "", 80), write: nil), .stepDone(id: id)]
            default:
                guard let (text, write) = describe(item, root: root) else { return [] }
                // Consumers ignore a step whose id they have already seen.
                return [.step(id: id, text: text, write: write), .stepDone(id: id)]
            }
        case "turn.completed":
            return [.finished(isError: false)]
        case "turn.failed":
            let e = obj["error"] as? [String: Any]
            return [.error(errorMessage((e?["message"] as? String) ?? "Codex 运行失败")), .finished(isError: true)]
        case "error":
            return [.error(errorMessage((obj["message"] as? String) ?? "Codex 出错"))]
        default:
            return []
        }
    }
}

// MARK: - Codex session files (~/.codex/sessions/**/rollout-*.jsonl)

public enum CodexRollout {
    static let patchFileRe = try! NSRegularExpression(pattern: #"\*\*\* (?:Update|Add|Delete) File: (.+)"#)
    static let cmdRe = try! NSRegularExpression(pattern: #""cmd"\s*:\s*"((?:[^"\\]|\\.)*)""#)

    public static func cwd(ofMeta obj: [String: Any]) -> String? {
        guard obj["type"] as? String == "session_meta", let p = obj["payload"] as? [String: Any] else { return nil }
        return p["cwd"] as? String
    }

    static func texts(_ content: Any?) -> [String] {
        (content as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
    }

    public static func events(from obj: [String: Any], root: String, index: Int) -> [AgentEvent] {
        guard let payload = obj["payload"] as? [String: Any] else { return [] }
        switch obj["type"] as? String {
        case "session_meta":
            return (payload["id"] as? String).map { [.session($0)] } ?? []
        case "response_item":
            let id = (payload["call_id"] as? String) ?? "r\(index)"
            switch payload["type"] as? String {
            case "message":
                let role = payload["role"] as? String
                let t = texts(payload["content"]).joined(separator: "\n")
                if role == "user", !isInjectedContext(t) { return [.user(t)] }
                if role == "assistant", !t.isEmpty { return [.text(t)] }
                return []
            case "function_call":
                let args = payload["arguments"] as? String ?? ""
                var cmd = ""
                if let d = args.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    cmd = (a["cmd"] as? String) ?? (a["command"] as? String) ?? ((a["command"] as? [String])?.last ?? "")
                }
                let name = payload["name"] as? String ?? "tool"
                return [.step(id: id, text: cmd.isEmpty ? name : "$ " + truncate(stripShellWrapper(cmd), 60), write: nil), .stepDone(id: id)]
            case "custom_tool_call":
                let input = payload["input"] as? String ?? ""
                let ns = input as NSString
                if payload["name"] as? String == "apply_patch" {
                    let files = patchFileRe.matches(in: input, range: NSRange(location: 0, length: ns.length)).map {
                        vaultRelative(ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces), root: root)
                    }
                    return [.step(id: id, text: "写入 " + files.joined(separator: ", "), write: nil), .stepDone(id: id)]
                }
                if let m = cmdRe.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) {
                    let raw = ns.substring(with: m.range(at: 1))
                    let cmd = (try? JSONSerialization.jsonObject(with: Data(("\"" + raw + "\"").utf8), options: .fragmentsAllowed) as? String) ?? raw
                    return [.step(id: id, text: "$ " + truncate(cmd, 60), write: nil), .stepDone(id: id)]
                }
                return [.step(id: id, text: payload["name"] as? String ?? "tool", write: nil), .stepDone(id: id)]
            default:
                return []
            }
        default:
            return []
        }
    }
}

public enum JSONLines {
    /// Splits a buffer into complete lines and leaves the trailing partial line in `buffer`.
    /// Linear: the consumed lines are cut off once at the end, not one at a time from the front.
    public static func drain(_ buffer: inout Data) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var start = buffer.startIndex
        while let nl = buffer[start...].firstIndex(of: 0x0A) {
            if nl > start, let obj = try? JSONSerialization.jsonObject(with: buffer[start..<nl]) as? [String: Any] { out.append(obj) }
            start = buffer.index(after: nl)
        }
        if start > buffer.startIndex { buffer = Data(buffer[start...]) }
        return out
    }

    /// Where the next read of a growing JSONL file starts: just past the last complete line.
    public struct Cursor: Equatable, Sendable {
        public var offset: UInt64
        /// Objects read so far, for numbering what comes next.
        public var lines: Int

        public init(offset: UInt64 = 0, lines: Int = 0) {
            self.offset = offset
            self.lines = lines
        }
    }

    /// The complete lines of `url` after `cursor`, or of its last `cap` bytes when there is no
    /// cursor (or the file got shorter, i.e. was replaced). `fresh` is true when reading started
    /// over, so earlier results must be dropped rather than extended.
    public static func read(_ url: URL, after cursor: Cursor?, cap: UInt64 = 3 << 20) -> (objects: [[String: Any]], cursor: Cursor, fresh: Bool) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return ([], cursor ?? Cursor(), cursor == nil) }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        var fresh = false
        var start: UInt64
        var lines = cursor?.lines ?? 0
        if let c = cursor, c.offset <= size {
            start = c.offset
        } else {
            fresh = true
            lines = 0
            start = size > cap ? size - cap : 0
        }
        try? h.seek(toOffset: start)
        var data = h.readDataToEndOfFile()
        // Starting mid-file: the first line is a fragment.
        if fresh, start > 0 {
            guard let nl = data.firstIndex(of: 0x0A) else { return ([], Cursor(offset: start, lines: 0), true) }
            start += UInt64(data.distance(from: data.startIndex, to: nl) + 1)
            data = Data(data[data.index(after: nl)...])
        }
        let total = data.count
        let objects = drain(&data)
        let consumed = UInt64(total - data.count)
        return (objects, Cursor(offset: start + consumed, lines: lines + objects.count), fresh)
    }
}
