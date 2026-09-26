import Foundation
import TwainCore

struct CLIInfo: Equatable {
    var path: String?
    var version: String?
    var found: Bool { path != nil }
}

/// GUI apps don't inherit the shell's PATH, so we ask a login shell once.
enum CLIEnvironment {
    static let path: String = {
        let fallback = [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let marker = "__TWAIN_PATH__"
        let out = run(shell, ["-ilc", "printf '\(marker)%s\(marker)' \"$PATH\""], timeout: 6)
        var dirs: [String] = []
        if let out, let a = out.range(of: marker), let b = out.range(of: marker, range: a.upperBound..<out.endIndex) {
            dirs = out[a.upperBound..<b.lowerBound].split(separator: ":").map(String.init)
        }
        for d in fallback where !dirs.contains(d) { dirs.append(d) }
        return dirs.joined(separator: ":")
    }()

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        env["NO_COLOR"] = "1"
        return env
    }

    static func locate(_ name: String) -> String? {
        for dir in path.split(separator: ":") {
            let p = String(dir) + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static func detect(_ kind: AgentKind) -> CLIInfo {
        guard let p = locate(kind.executable) else { return CLIInfo() }
        let v = run(p, ["--version"], timeout: 8)?
            .split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        return CLIInfo(path: p, version: v)
    }

    /// What `kind` offers, read fresh from the CLI's own files each call.
    struct Models {
        var choices: [AgentModel]
        /// Model and thinking level the CLI uses when Twain passes none, when we can tell.
        var fallback: String?
        var fallbackEffort: String?
        /// Version of the client that wrote the list, when it says.
        var listedBy: String?
    }

    static func models(_ kind: AgentKind) -> Models {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        switch kind {
        case .claude:
            let dir = home.appendingPathComponent(".claude")
            let catalog = ClaudeModels.latestCatalog(in: dir.appendingPathComponent("cache/model-catalog"))
                .flatMap { try? Data(contentsOf: $0) }
                .map(ClaudeModels.parseCatalog) ?? []
            let conf = (try? Data(contentsOf: dir.appendingPathComponent("settings.json"))).map(ClaudeModels.configured)
            return Models(choices: catalog.isEmpty ? kind.builtinModels : catalog,
                          fallback: conf?.model, fallbackEffort: conf?.effort)
        case .codex:
            let dir = home.appendingPathComponent(".codex")
            let data = try? Data(contentsOf: dir.appendingPathComponent("models_cache.json"))
            let cached = data.map(CodexModels.parseCache) ?? []
            let toml = try? String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
            return Models(choices: cached, fallback: toml.flatMap(CodexModels.configuredModel),
                          fallbackEffort: toml.flatMap(CodexModels.configuredEffort),
                          listedBy: data.flatMap(CodexModels.cacheClientVersion))
        }
    }

    /// Runs a short command and returns stdout, or nil on timeout/failure.
    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil, timeout: TimeInterval = 10) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        // The login-shell probe that computes `path` must not read `path` itself.
        if exe != (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") {
            p.environment = environment
        }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        let reader = DispatchQueue(label: "twain.run")
        let group = DispatchGroup()
        group.enter()
        reader.async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        while p.isRunning, Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return nil }
        group.wait()
        return String(data: data, encoding: .utf8)
    }
}

enum Git {
    static func isRepo(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
    }

    /// Commits the working tree before an agent writes, so every change can be undone.
    /// Returns the short hash of the snapshot (or of HEAD when there was nothing to commit).
    static func snapshot(_ root: URL, message: String) -> String? {
        guard isRepo(root) else { return nil }
        let git = "/usr/bin/git"
        let status = CLIEnvironment.run(git, ["status", "--porcelain"], cwd: root) ?? ""
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            CLIEnvironment.run(git, ["add", "-A"], cwd: root)
            CLIEnvironment.run(git, ["commit", "-q", "-m", message], cwd: root)
        }
        return CLIEnvironment.run(git, ["rev-parse", "--short", "HEAD"], cwd: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One running `claude -p` / `codex exec` process, streaming JSON events.
final class AgentProcess {
    let kind: AgentKind
    private let process = Process()
    private var buffer = Data()
    private var stderrTail = Data()
    private var sawFinish = false

    var pid: Int32 { process.processIdentifier }

    init(kind: AgentKind) { self.kind = kind }

    /// `env` is added to the CLI's environment; a `PATH` there is put in front of the usual one.
    func start(executable: String, arguments: [String], cwd: URL, env extra: [String: String] = [:],
               onEvents: @escaping ([AgentEvent]) -> Void,
               onExit: @escaping (_ status: Int32, _ stderr: String, _ sawFinish: Bool) -> Void) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var env = CLIEnvironment.environment
        for (k, v) in extra { env[k] = k == "PATH" ? v + ":" + (env["PATH"] ?? "") : v }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let root = cwd.path
        let kind = self.kind
        let queue = DispatchQueue(label: "twain.agent.\(kind.rawValue)")
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            queue.async {
                guard let self else { return }
                self.buffer.append(chunk)
                let objs = JSONLines.drain(&self.buffer)
                let events = objs.flatMap { obj in
                    kind == .claude ? ClaudeStream.events(from: obj, root: root) : CodexStream.events(from: obj, root: root)
                }
                if events.contains(where: { if case .finished = $0 { return true }; return false }) { self.sawFinish = true }
                if !events.isEmpty { DispatchQueue.main.async { onEvents(events) } }
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            queue.async {
                guard let self else { return }
                self.stderrTail.append(chunk)
                if self.stderrTail.count > 8000 { self.stderrTail = self.stderrTail.suffix(4000) }
            }
        }
        process.terminationHandler = { [weak self] p in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            queue.async {
                guard let self else { return }
                // Flush whatever arrived after the last newline.
                let rest = out.fileHandleForReading.readDataToEndOfFile()
                self.buffer.append(rest)
                self.buffer.append(0x0A)
                let events = JSONLines.drain(&self.buffer).flatMap { obj in
                    kind == .claude ? ClaudeStream.events(from: obj, root: root) : CodexStream.events(from: obj, root: root)
                }
                if events.contains(where: { if case .finished = $0 { return true }; return false }) { self.sawFinish = true }
                let errText = String(data: self.stderrTail, encoding: .utf8) ?? ""
                let status = p.terminationStatus
                let saw = self.sawFinish
                DispatchQueue.main.async {
                    if !events.isEmpty { onEvents(events) }
                    onExit(status, errText, saw)
                }
            }
        }
        try process.run()
    }

    func stop() {
        if process.isRunning { process.interrupt() }
    }
}

/// Tab 续写: a short continuation from `claude -p` with a small model and no tools.
final class GhostCompleter {
    private var current: Process?
    private var generation = 0

    func cancel() {
        generation += 1
        current?.terminate()
        current = nil
    }

    func complete(paragraph: String, context: String, cwd: URL, done: @escaping (String) -> Void) {
        cancel()
        guard let exe = CLIEnvironment.locate("claude") else { return }
        let gen = generation
        let prompt = """
        你是写作助手。下面是一篇 Markdown 笔记的上下文，以及光标所在段落。请续写这一段接下来的半句或一句（不超过 30 个字），\
        保持作者的语气和语言。只输出续写的文字本身，不要引号、不要解释、不要重复已有内容。

        <上下文>
        \(context)
        </上下文>

        <当前段落>
        \(paragraph)
        </当前段落>
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["-p", prompt, "--model", "haiku", "--tools", "", "--no-session-persistence",
                       "--disable-slash-commands", "--output-format", "text"]
        p.currentDirectoryURL = cwd
        p.environment = CLIEnvironment.environment
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.terminationHandler = { [weak self] proc in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = (String(data: data, encoding: .utf8) ?? "")
                .split(separator: "\n").first.map(String.init)?
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"“”「」"))
            DispatchQueue.main.async {
                guard let self, gen == self.generation, proc.terminationStatus == 0, let text, !text.isEmpty else { return }
                self.current = nil
                done(String(text.prefix(60)))
            }
        }
        do {
            try p.run()
            current = p
        } catch {}
    }
}
