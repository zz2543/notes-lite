import SwiftUI
import TwainCore

/// A long-lived `claude -p` taking one question after another over stream-json: the CLI starts
/// once instead of per question, and the model remembers what it already said. Restarted after
/// a few turns so the conversation (and its cost) stays small.
final class LiveModel {
    private let model: String
    private let system: String
    private let cwd: URL
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var waiting: ((String?) -> Void)?
    private var turns = 0
    private let maxTurns = 10

    init(model: String = "haiku", system: String, cwd: URL) {
        self.model = model
        self.system = system
        self.cwd = cwd
    }

    var busy: Bool { waiting != nil }

    /// Starts the CLI ahead of the first question, so that one doesn't pay for the startup.
    func warm() { if process?.isRunning != true { restart() } }

    func ask(_ text: String, done: @escaping (String?) -> Void) {
        guard waiting == nil else { return done(nil) }
        if process?.isRunning != true || turns >= maxTurns { restart() }
        guard let input else { return done(nil) }
        waiting = done
        turns += 1
        let msg: JSONValue = ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": .string(text)]]]]
        var line = msg.encoded()
        line.append(0x0A)
        input.write(line)
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            // A stuck turn: give up on it and start fresh next time.
            guard let self, self.waiting != nil else { return }
            self.deliver(nil)
            self.stop()
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        input = nil
        turns = 0
        buffer = Data()
    }

    private func restart() {
        stop()
        guard let exe = CLIEnvironment.locate("claude") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--model", model, "--tools", "", "--strict-mcp-config", "--no-session-persistence",
                       "--disable-slash-commands", "--append-system-prompt", system]
        p.currentDirectoryURL = cwd
        p.environment = CLIEnvironment.environment
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            DispatchQueue.main.async { self?.consume(d) }
        }
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { if self?.waiting != nil { self?.deliver(nil) } } }
        do {
            try p.run()
            process = p
            input = inPipe.fileHandleForWriting
        } catch {
            process = nil
        }
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        for line in RPC.drainLines(&buffer) {
            guard let o = try? JSONDecoder().decode(JSONValue.self, from: line), o["type"]?.string == "result" else { continue }
            deliver(o["is_error"]?.bool == true ? nil : o["result"]?.string)
        }
    }

    private func deliver(_ text: String?) {
        let w = waiting
        waiting = nil
        w?(text)
    }
}

/// A margin remark from the writing companion.
struct CompanionTip: Equatable {
    enum Kind: String { case question, idea, gap }
    let kind: Kind
    let text: String
    let quote: String?
    let rel: String

    var label: String { ["question": "想一想", "idea": "换个角度", "gap": "可能漏了"][kind.rawValue] ?? "伴写" }
    var icon: String { ["question": "questionmark.circle", "idea": "lightbulb", "gap": "puzzlepiece"][kind.rawValue] ?? "sparkle" }
}

/// The writing companion: while you write, a small model occasionally leaves one short question,
/// angle or missing piece beside the page. It never writes into the note. Off by default; it
/// waits for a pause, for enough new text, and a minute between remarks.
extension AppModel {
    static let companionSystem = """
    你是坐在作者身边的写作伙伴，只在作者停下来时偶尔说一句。你的话显示在页边，作者可以忽略。
    规则：每次最多一条，不超过 40 个字；只说真正有帮助的——一个推动思考的问题、一个作者可能没想到的角度、或一个明显遗漏的要点；
    不要改写原文，不要夸奖，不要客套，不要重复你之前说过的意思。没有值得说的就跳过。
    只输出 JSON：{"kind":"question|idea|gap","text":"……","quote":"针对的原文片段（逐字，可省略）"}，或 {"skip":true}。
    """

    func companionTextChanged() {
        guard prefs.companionOn else { return }
        companionWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.companionPause() }
        companionWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: w)
    }

    private func companionPause() {
        guard prefs.companionOn, let v = vault, let rel = editor.activeRel, activeNote?.isHTML != true, !agents.writing.contains(rel) else { return }
        let now = Date()
        guard now.timeIntervalSince(companionLast) > 50 else { return }
        companionCalls = companionCalls.filter { now.timeIntervalSince($0) < 3600 }
        guard companionCalls.count < 30 else { return }
        let ns = editor.editorText as NSString
        let caret = min(editor.editorSelection.location, ns.length)
        // Enough new writing since the last remark, measured by how the note grew.
        guard abs(ns.length - companionLength) >= 40 || companionLength == 0 && ns.length > 80 else { return }
        let start = max(0, caret - 1500)
        let recent = ns.substring(with: NSRange(location: start, length: caret - start))
        guard recent.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 else { return }
        let ctx = EditorContext.describe(text: editor.editorText, selection: NSRange(location: caret, length: 0))
        let path = (ctx["headingPath"]?.array ?? []).compactMap(\.string).joined(separator: " › ")
        let prompt = """
        笔记《\(NoteRef(rel: rel).title)》\(path.isEmpty ? "" : "，光标在「\(path)」这一节")。作者刚写到这里：
        <recent>
        \(recent)
        </recent>
        """
        companionLast = now
        companionLength = ns.length
        companionCalls.append(now)
        if companionModel == nil { companionModel = LiveModel(system: Self.companionSystem, cwd: v.root) }
        editor.companionThinking = true
        companionModel?.ask(prompt) { [weak self] reply in
            guard let self else { return }
            self.editor.companionThinking = false
            guard self.editor.activeRel == rel, let reply, let obj = ModelCall.jsonObject(reply),
                  obj["skip"] as? Bool != true, let text = obj["text"] as? String, !text.isEmpty else { return }
            let kind = CompanionTip.Kind(rawValue: obj["kind"] as? String ?? "") ?? .question
            self.editor.companionTip = CompanionTip(kind: kind, text: text, quote: (obj["quote"] as? String).flatMap { $0.isEmpty ? nil : $0 }, rel: rel)
        }
    }

    /// Keeps the remark as an annotation on its passage (or on the caret's paragraph).
    func keepCompanionTip() {
        guard let tip = editor.companionTip, tip.rel == editor.activeRel, let store = annotationStore else { return }
        let ns = editor.editorText as NSString
        var quote = tip.quote.flatMap { Anchor.locate($0, in: editor.editorText, line: nil) != nil ? $0 : nil }
        if quote == nil {
            var r = ns.lineRange(for: NSRange(location: min(editor.editorSelection.location, ns.length), length: 0))
            if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
            quote = String(ns.substring(with: r).suffix(40))
        }
        let kind: Annotation.Kind = tip.kind == .gap ? .structure : .question
        _ = try? store.add(tip.rel, text: editor.editorText, items: [["quote": .string(quote ?? ""), "text": .string(tip.text), "kind": .string(kind.rawValue)]],
                           agent: "伴写", session: nil)
        loadAnnotations()
        editor.companionTip = nil
    }

    func warmCompanion() {
        guard prefs.companionOn, let v = vault else { return }
        if companionModel == nil { companionModel = LiveModel(system: Self.companionSystem, cwd: v.root) }
        companionModel?.warm()
    }

    func toggleCompanion() {
        prefs.companionOn.toggle()
        if !prefs.companionOn { companionModel?.stop(); companionModel = nil; editor.companionTip = nil }
        else { warmCompanion() }
        showToast(prefs.companionOn ? "伴写已开启：停笔片刻时，页边会偶尔出现一句提问或思路" : "伴写已关闭")
    }
}

/// The companion's remark, floating at the top right of the page.
struct CompanionBubble: View {
    @Bindable var model: AppModel
    let tip: CompanionTip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: tip.icon).foregroundStyle(.tint)
                Text("伴写 · " + tip.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { model.editor.companionTip = nil } label: { Image(systemName: "xmark").font(.caption2.weight(.semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
            Text(tip.text).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack(spacing: 6) {
                Button("留作批注", systemImage: "text.bubble") { model.keepCompanionTip() }
                Button("问 agent", systemImage: "bubble.left.and.text.bubble.right") {
                    model.chrome.agentPanel = true
                    model.agents.agentInput = tip.text
                    model.editor.companionTip = nil
                }
            }
            .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
        }
        .padding(12)
        .frame(width: 280)
        .floatingGlass(radius: Metrics.cardRadius)
    }
}
