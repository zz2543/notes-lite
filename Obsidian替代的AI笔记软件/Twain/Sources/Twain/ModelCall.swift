import Foundation

/// One question to a model, one answer, no tools: `claude -p` with a small model. For the
/// quick jobs around the editor (summaries, the writing companion) that need no agent loop.
final class ModelCall {
    private var process: Process?
    private var cancelled = false

    /// Runs `prompt`; `done` gets the reply (nil on failure, timeout or cancel) on the main queue.
    @discardableResult
    static func ask(_ prompt: String, model: String = "haiku", cwd: URL, timeout: TimeInterval = 90,
                    done: @escaping (String?) -> Void) -> ModelCall {
        let call = ModelCall()
        call.start(prompt, model: model, cwd: cwd, timeout: timeout, done: done)
        return call
    }

    func cancel() {
        cancelled = true
        process?.terminate()
    }

    private func start(_ prompt: String, model: String, cwd: URL, timeout: TimeInterval, done: @escaping (String?) -> Void) {
        guard let exe = CLIEnvironment.locate("claude") else { DispatchQueue.main.async { done(nil) }; return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        // No tools, no MCP servers to connect to: these are one-shot text jobs.
        p.arguments = ["-p", "--model", model, "--tools", "", "--no-session-persistence", "--strict-mcp-config",
                       "--disable-slash-commands", "--output-format", "text"]
        p.currentDirectoryURL = cwd
        p.environment = CLIEnvironment.environment
        let input = Pipe(), out = Pipe()
        p.standardInput = input
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var finished = false
        let finish: (String?) -> Void = { [weak self] text in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                done(self?.cancelled == true ? nil : text)
            }
        }
        p.terminationHandler = { proc in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            finish(proc.terminationStatus == 0 && text?.isEmpty == false ? text : nil)
        }
        do {
            try p.run()
            process = p
            // The prompt goes in on stdin: long batches would overflow the argument list.
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
    }

    /// The first JSON object in a reply, tolerating code fences and chatter around it.
    static func jsonObject(_ text: String) -> [String: Any]? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let data = String(text[a...b]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
