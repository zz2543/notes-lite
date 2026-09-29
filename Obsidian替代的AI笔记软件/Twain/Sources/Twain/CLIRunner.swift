import Foundation
import TwainCore

/// Starting the agent CLIs, in one place: the environment, the arguments every quick call
/// shares, feeding the prompt, timeouts and cancellation. A full agent run (`AgentProcess`),
/// the companion's long-lived chat (`LiveModel`), Tab 续写 and the one-shot jobs (summaries)
/// all launch through it.
enum CLIRunner {
    /// `claude -p` with a small model and nothing else: no tools, no MCP servers to connect to
    /// (their startup is most of a quick call's time), no slash commands, no saved session.
    static func quickArguments(model: String) -> [String] {
        ["-p", "--model", model, "--tools", "", "--strict-mcp-config", "--no-session-persistence", "--disable-slash-commands"]
    }

    /// A process for `exe` with the login shell's PATH. A `PATH` in `extra` goes in front of it.
    static func process(_ exe: String, _ args: [String], cwd: URL, env extra: [String: String] = [:]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = cwd
        var env = CLIEnvironment.environment
        for (k, v) in extra { env[k] = k == "PATH" ? v + ":" + (env["PATH"] ?? "") : v }
        p.environment = env
        return p
    }

    /// A one-shot call in flight.
    final class Call {
        fileprivate var process: Process?
        fileprivate var cancelled = false

        /// Stops the call; its completion then receives nil.
        func cancel() {
            cancelled = true
            process?.terminate()
        }
    }

    /// One question, one answer: `done` gets the reply's text on the main queue, or nil on
    /// failure, timeout or cancel. The prompt goes in on stdin, so long ones fit.
    @discardableResult
    static func text(_ prompt: String, model: String = "haiku", cwd: URL, timeout: TimeInterval,
                     done: @escaping (String?) -> Void) -> Call {
        let call = Call()
        guard let exe = CLIEnvironment.locate("claude") else {
            DispatchQueue.main.async { done(nil) }
            return call
        }
        let p = process(exe, quickArguments(model: model) + ["--output-format", "text"], cwd: cwd)
        let input = Pipe(), out = Pipe()
        p.standardInput = input
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var finished = false
        let finish: (String?) -> Void = { text in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                done(call.cancelled ? nil : text)
            }
        }
        p.terminationHandler = { proc in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            finish(proc.terminationStatus == 0 && text?.isEmpty == false ? text : nil)
        }
        do {
            try p.run()
            call.process = p
            DispatchQueue.global(qos: .userInitiated).async {
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak p] in
                guard let p, p.isRunning else { return }
                p.terminate()
                finish(nil)
            }
        } catch {
            finish(nil)
        }
        return call
    }

    /// The first JSON object in a reply, tolerating code fences and chatter around it.
    static func jsonObject(_ text: String) -> [String: Any]? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let data = String(text[a...b]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
