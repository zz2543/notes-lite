import AppKit
import Observation
import PlumeCore
import SwiftUI

struct PendingReview {
    let rel: String
    /// nil when the writer was not an agent we could identify (another editor, sync…).
    let by: AgentKind?
    let source: SessionSource
    var baseline: [String]
    var proposed: [String]
    var hunks: [Hunk]
    var snapshot: String?

    var plus: Int { hunks.reduce(0) { $0 + $1.add.count } }
    var minus: Int { hunks.reduce(0) { $0 + $1.del } }
}

enum ReviewMode: String { case queue, auto }
enum SettingsTab: String { case editor, agent, keys }

struct SlashItem: Identifiable, Equatable {
    let label: String
    let hint: String
    let key: String
    var prefix: String = ""
    var hr = false
    var ai: AgentKind?
    var id: String { key }

    static let all: [SlashItem] = [
        SlashItem(label: "一级标题", hint: "#", key: "h1", prefix: "# "),
        SlashItem(label: "二级标题", hint: "##", key: "h2", prefix: "## "),
        SlashItem(label: "三级标题", hint: "###", key: "h3", prefix: "### "),
        SlashItem(label: "列表", hint: "-", key: "list", prefix: "- "),
        SlashItem(label: "待办", hint: "- [ ]", key: "todo", prefix: "- [ ] "),
        SlashItem(label: "引用", hint: ">", key: "quote", prefix: "> "),
        SlashItem(label: "分割线", hint: "---", key: "hr", hr: true),
        SlashItem(label: "让 Claude Code 续写", hint: "agent", key: "claude", ai: .claude),
        SlashItem(label: "让 Codex 整理本页", hint: "agent", key: "codex", ai: .codex),
    ]

    static func matching(_ line: String) -> [SlashItem]? {
        guard line.hasPrefix("/"), !line.contains(" ") else { return nil }
        let q = line.dropFirst().lowercased()
        let l = all.filter { q.isEmpty || $0.label.lowercased().contains(q) || $0.key.contains(q) }
        return l.isEmpty ? nil : l
    }
}

struct SlashState: Equatable {
    var items: [SlashItem]
    var selection: Int
    /// Top-left of the menu in editor-view coordinates (top-left origin).
    var anchor: CGPoint
}

@Observable
final class AppModel {
    // MARK: preferences
    var font: EditorFont = .serif { didSet { save("font", font.rawValue) } }
    var typewriter = true { didSet { save("typewriter", typewriter) } }
    var dim = true { didSet { save("dim", dim) } }
    var ghostOn = false { didSet { save("ghostOn", ghostOn); if !ghostOn { clearGhost() } } }
    var syncContext = true { didSet { save("syncCtx", syncContext); if syncContext { ensureContextFiles() } } }
    var watchTerminal = true { didSet { save("watchExt", watchTerminal); if !watchTerminal { dropTerminalSessions() } } }
    var gitSnapshot = true { didSet { save("snapshot", gitSnapshot) } }
    var reviewMode: ReviewMode = .queue { didSet { save("review", reviewMode.rawValue) } }
    var claudeOn = true { didSet { save("claudeOn", claudeOn) } }
    var codexOn = true { didSet { save("codexOn", codexOn) } }
    var editorWidth: CGFloat = 680

    // MARK: chrome
    var columnVisibility: NavigationSplitViewVisibility = .all
    var agentPanel = true
    var zen = false
    var palette = false
    var paletteQuery = ""
    var paletteSel = 0
    var settingsTab: SettingsTab = .editor
    var sidebarFilter = ""
    /// Sidebar list selection; choosing a row opens the note.
    var selection: String? {
        didSet { if let s = selection, s != activeRel { open(s) } }
    }
    @ObservationIgnored var openSettingsAction: (() -> Void)?
    @ObservationIgnored private var beforeZen: (NavigationSplitViewVisibility, Bool)?
    var onboardingStep: Int?
    var toast: String?
    var openFolders: Set<String> = []
    var showDiff = false
    var tick = 0

    // MARK: vault & editor
    var vault: Vault?
    var activeRel: String?
    var editorText = ""
    /// Bumped whenever the model replaces the editor's text (note switch, disk reload).
    var editorVersion = 0
    var dirty = false
    var focusRequest: (caret: Int, token: Int)?
    var ghost = ""
    var slash: SlashState?

    // MARK: agents
    var cli: [AgentKind: CLIInfo] = [:]
    var sessions: [AgentSession] = []
    var activeSessionID: UUID?
    var agentInput = ""
    var agentPick: AgentKind = .claude
    var pending: [String: PendingReview] = [:]
    var writing: Set<String> = []

    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored private var ghostWork: DispatchWorkItem?
    @ObservationIgnored private let ghostCompleter = GhostCompleter()
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var runSnapshots: [UUID: (files: [String: String], git: String?)] = [:]
    @ObservationIgnored var typed: [(Date, Int)] = []
    @ObservationIgnored var netTyped = 0
    @ObservationIgnored private var focusToken = 0

    private let defaults = UserDefaults.standard

    init() {
        loadPrefs()
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, CLIEnvironment.detect($0)) })
            DispatchQueue.main.async { self.cli = found }
        }
        #if DEBUG
        let snapshotVault = ProcessInfo.processInfo.environment["PLUME_SNAPSHOT"] == nil
            ? nil : ProcessInfo.processInfo.environment["PLUME_SNAPSHOT_VAULT"]
        #else
        let snapshotVault: String? = nil
        #endif
        if let path = snapshotVault ?? defaults.string(forKey: "vaultPath"), FileManager.default.fileExists(atPath: path) {
            openVault(URL(fileURLWithPath: path))
        }
        if !defaults.bool(forKey: "onboarded") || vault == nil { onboardingStep = 0 }
        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick += 1 })
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.pollTerminal() })
    }

    // MARK: prefs

    private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: "pref." + key) }

    private func loadPrefs() {
        func b(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: "pref." + k) as? Bool ?? d }
        font = EditorFont(rawValue: defaults.string(forKey: "pref.font") ?? "") ?? .serif
        typewriter = b("typewriter", true)
        dim = b("dim", true)
        ghostOn = b("ghostOn", false)
        syncContext = b("syncCtx", true)
        watchTerminal = b("watchExt", true)
        gitSnapshot = b("snapshot", true)
        reviewMode = ReviewMode(rawValue: defaults.string(forKey: "pref.review") ?? "") ?? .queue
        claudeOn = b("claudeOn", true)
        codexOn = b("codexOn", true)
    }

    // MARK: vault

    static var defaultVaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Vault")
    }

    func openVault(_ url: URL) {
        flushSave()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let v = Vault(root: url)
        v.onFilesChanged = { [weak self] rels in self?.filesChanged(rels) }
        vault = v
        #if DEBUG
        if ProcessInfo.processInfo.environment["PLUME_SNAPSHOT_VAULT"] == nil {
            defaults.set(v.rootPath, forKey: "vaultPath")
        }
        #else
        defaults.set(v.rootPath, forKey: "vaultPath")
        #endif
        pending = [:]
        writing = []
        sessions.removeAll { $0.source == .terminal }
        if syncContext { ensureContextFiles() }
        if v.notes.filter({ !$0.isAgentFile }).isEmpty {
            _ = v.create(title: "欢迎使用 Plume", content: Self.welcomeNote)
        }
        openFolders = Set(v.folders.filter { !$0.contains("/") })
        let first = v.notes.first { !$0.isAgentFile && $0.folder.isEmpty } ?? v.notes.first { !$0.isAgentFile } ?? v.notes.first
        activeRel = nil
        if let first { open(first.rel) }
        pollTerminal()
    }

    static let welcomeNote = """
    # 欢迎使用 Plume
    这个库就是磁盘上的一个文件夹，每篇笔记都是一个 **Markdown** 文件。
    ## 试试看
    - [ ] 输入 `/` 打开斜杠命令
    - [ ] 按 ⌘K 搜索笔记与命令
    - [ ] 按 ⌘J 打开 Agent 面板，让 Claude Code 或 Codex 修改这篇笔记
    > Agent 的每一次写入都会进入审阅，可以逐段接受或还原。

    """

    static let agentsTemplate = """
    # AGENTS.md
    这个库是我的个人笔记。所有 agent 请遵守：
    - 只修改被要求的文件，保持纯 Markdown
    - 链接统一使用 [[双链]] 语法
    - 新的想法追加到 [[收件箱]]
    - 不要改动 `日记/` 下的内容

    """

    static let claudeTemplate = """
    # CLAUDE.md
    @AGENTS.md
    > 由 Plume 维护，与 AGENTS.md 同源。请直接编辑 [[AGENTS]]。

    """

    /// AGENTS.md is the single source; CLAUDE.md only imports it.
    func ensureContextFiles() {
        guard let v = vault else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: v.url("AGENTS.md").path) { v.forceWrite("AGENTS.md", Self.agentsTemplate) }
        if !fm.fileExists(atPath: v.url("CLAUDE.md").path) { v.forceWrite("CLAUDE.md", Self.claudeTemplate) }
        v.scan()
    }

    var contextInSync: Bool {
        guard let v = vault, let c = v.diskContent("CLAUDE.md") else { return false }
        return c.contains("@AGENTS.md") && FileManager.default.fileExists(atPath: v.url("AGENTS.md").path)
    }

    var activeNote: NoteRef? { activeRel.flatMap { vault?.note($0) } ?? activeRel.map { NoteRef(rel: $0) } }

    // MARK: editor

    func open(_ rel: String, focus: Bool = false) {
        guard let v = vault else { return }
        if rel != activeRel { flushSave() }
        activeRel = rel
        editorText = v.read(rel)
        if pending[rel] == nil { showDiff = false }
        dirty = false
        clearGhost()
        slash = nil
        editorVersion += 1
        palette = false
        if selection != rel { selection = rel }
        if focus { requestFocus(caret: (editorText as NSString).length) }
        revealInSidebar(rel)
    }

    func revealInSidebar(_ rel: String) {
        var folder = (rel as NSString).deletingLastPathComponent
        while !folder.isEmpty {
            openFolders.insert(folder)
            folder = (folder as NSString).deletingLastPathComponent
        }
    }

    func requestFocus(caret: Int) {
        focusToken += 1
        focusRequest = (caret, focusToken)
    }

    var editorReadOnly: Bool {
        guard let rel = activeRel else { return true }
        return writing.contains(rel)
    }

    func editorDidChange(_ text: String) {
        // NSTextView can notify after a model-driven reload. It is not a user edit,
        // so it must not accept a pending agent review or schedule another save.
        guard text != editorText else { return }
        let delta = (text as NSString).length - (editorText as NSString).length
        if delta > 0 && delta < 20 { typed.append((Date(), delta)) }
        netTyped += delta
        editorText = text
        dirty = true
        if let rel = activeRel, pending[rel] != nil {
            // Editing a file under review keeps the agent's version as the new base.
            pending[rel] = nil
            showDiff = false
            showToast("已保留 agent 的改动并继续编辑")
        }
        scheduleSave()
    }

    func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.flushSave() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    func flushSave() {
        saveWork?.cancel()
        guard dirty, let v = vault, let rel = activeRel else { return }
        if writing.contains(rel) { return }
        switch v.write(rel, editorText) {
        case .ok:
            dirty = false
        case let .conflict(disk):
            // Someone else wrote the file after we last read it: theirs wins, ours goes to review.
            let mine = editorText
            v.acknowledge(rel, content: disk)
            pending[rel] = PendingReview(rel: rel, by: mostRecentTerminalSession()?.agent, source: .terminal,
                                         baseline: Markdown.lines(mine), proposed: Markdown.lines(disk),
                                         hunks: LineDiff.hunks(from: Markdown.lines(mine), to: Markdown.lines(disk)), snapshot: nil)
            editorText = disk
            dirty = false
            editorVersion += 1
            showToast("文件在外部被修改，已载入磁盘上的版本")
        }
    }

    func toggleTask(line: Int) {
        var lines = Markdown.lines(editorText)
        guard lines.indices.contains(line) else { return }
        lines[line] = Markdown.toggleTask(lines[line])
        editorText = lines.joined(separator: "\n")
        dirty = true
        editorVersion += 1
        scheduleSave()
    }

    func newNote() {
        guard let v = vault else { return }
        flushSave()
        let rel = v.create(title: "未命名", content: "# 未命名\n")
        palette = false
        open(rel)
        requestFocus(caret: ("# 未命名\n" as NSString).length)
    }

    func openByTitle(_ title: String) {
        guard let v = vault else { return }
        if let n = v.note(titled: title) { open(n.rel); return }
        flushSave()
        let head = "# " + title + "\n"
        let rel = v.create(title: title, content: head)
        open(rel)
        requestFocus(caret: (head as NSString).length)
        showToast("已创建 " + (rel as NSString).lastPathComponent)
    }

    // MARK: ghost text

    func textPaused(paragraph: String, caretAtEnd: Bool, lineIndex: Int) {
        ghostWork?.cancel()
        ghost = ""
        guard ghostOn, caretAtEnd, Markdown.blockType(paragraph) == .p, paragraph.count > 6,
              !paragraph.hasPrefix("/"), paragraph.last?.isWhitespace == false,
              cli[.claude]?.found == true, let v = vault else { return }
        let before = Markdown.lines(editorText).prefix(lineIndex).suffix(12).joined(separator: "\n")
        let w = DispatchWorkItem { [weak self] in
            self?.ghostCompleter.complete(paragraph: paragraph, context: before, cwd: v.root) { text in
                guard let self, self.currentParagraphForGhost == paragraph else { return }
                self.ghost = text
            }
        }
        ghostWork = w
        currentParagraphForGhost = paragraph
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: w)
    }

    @ObservationIgnored var currentParagraphForGhost: String?

    func clearGhost() {
        ghostWork?.cancel()
        ghostCompleter.cancel()
        currentParagraphForGhost = nil
        if !ghost.isEmpty { ghost = "" }
    }

    // MARK: toast

    func showToast(_ m: String) {
        toastWork?.cancel()
        toast = m
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: w)
    }

    // MARK: agents

    var activeSession: AgentSession? {
        sessions.first { $0.id == activeSessionID } ?? sessions.first
    }

    func agentEnabled(_ k: AgentKind) -> Bool { k == .claude ? claudeOn : codexOn }

    func runAgent(prompt: String, agent: AgentKind) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, let v = vault else { return }
        guard agentEnabled(agent) else { showToast(agent.displayName + " 已在设置中停用"); return }
        guard let exe = cli[agent]?.path ?? CLIEnvironment.locate(agent.executable) else {
            showToast("没有找到 " + agent.executable + " 命令")
            return
        }
        flushSave()
        clearGhost()

        var session = activeSession
        if session == nil || session!.source != .app || session!.agent != agent || session!.running {
            let s = AgentSession(agent: agent, source: .app, title: String(prompt.prefix(10)))
            sessions.append(s)
            session = s
        }
        let s = session!
        if s.title == "新会话" { s.title = String(prompt.prefix(10)) }
        activeSessionID = s.id
        if zen { toggleZen() }
        agentPanel = true
        agentInput = ""
        s.items.append(SessionItem(kind: .user(prompt)))
        s.running = true

        let git = gitSnapshot ? Git.snapshot(v.root, message: "Plume: snapshot before \(agent.displayName)") : nil
        runSnapshots[s.id] = (v.snapshotAll(), git)

        let noteRel = activeRel ?? ""
        let context = "你在 Plume 笔记库中工作，当前目录就是库的根目录，库里的笔记都是 Markdown 文件。" +
            (noteRel.isEmpty ? "" : "用户当前打开的笔记是 \(noteRel)，“这篇笔记”“当前笔记”指的就是它。") +
            "遵守 AGENTS.md 中的约定。直接修改文件即可，Plume 会把改动交给用户审阅。"
        let args = AgentProcess.arguments(kind: agent, prompt: prompt, context: context, root: v.rootPath,
                                          resume: s.cliSessionID)
        let proc = AgentProcess(kind: agent)
        s.process = proc
        do {
            try proc.start(executable: exe, arguments: args, cwd: v.root, onEvents: { [weak self, weak s] events in
                guard let self, let s else { return }
                for w in s.apply(events) {
                    let rel = v.relative(w)
                    self.writing.insert(rel)
                }
            }, onExit: { [weak self, weak s] status, stderr, sawFinish in
                guard let self, let s else { return }
                if status != 0 && !sawFinish {
                    let msg = stderr.split(separator: "\n").suffix(3).joined(separator: "\n")
                    s.items.append(SessionItem(kind: .error(msg.isEmpty ? "\(agent.executable) 退出，状态码 \(status)" : msg)))
                }
                s.settleSteps()
                s.running = false
                s.process = nil
                self.finishRun(s)
            })
        } catch {
            s.items.append(SessionItem(kind: .error("无法启动 \(exe)：\(error.localizedDescription)")))
            s.running = false
            runSnapshots[s.id] = nil
        }
    }

    func stopAgent(_ s: AgentSession) { s.process?.stop() }

    #if DEBUG
    /// Mimics an agent run without calling a CLI: snapshot, write to disk, finish.
    func debugSimulateRun(rel: String, append: String) {
        guard let v = vault else { return }
        let s = AgentSession(agent: .claude, source: .app, title: "模拟")
        sessions.append(s)
        activeSessionID = s.id
        s.running = true
        runSnapshots[s.id] = (v.snapshotAll(), nil)
        writing.insert(rel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? ((v.diskContent(rel) ?? "") + append).write(to: v.url(rel), atomically: true, encoding: .utf8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                s.running = false
                self.finishRun(s)
            }
        }
    }
    #endif

    /// Compares the vault with the snapshot taken before the run and queues each changed file.
    private func finishRun(_ s: AgentSession) {
        guard let v = vault, let snap = runSnapshots.removeValue(forKey: s.id) else { return }
        v.scan()
        let rels = Set(snap.files.keys).union(v.notes.map(\.rel))
        var changed: [String] = []
        for rel in rels.sorted() {
            let before = snap.files[rel]
            let after = v.diskContent(rel)
            // Skip files that only Plume itself saved during the run.
            guard before != after, let after, after != v.knownContent(rel) else { continue }
            changed.append(rel)
            let base = pending[rel]?.baseline ?? Markdown.lines(v.knownContent(rel) ?? before ?? "")
            queueReview(rel: rel, baseline: base,
                        proposed: after, by: s.agent, source: .app, snapshot: snap.git, session: s)
        }
        for rel in writing where !changed.contains(rel) { v.acknowledge(rel, content: v.diskContent(rel)) }
        writing.removeAll()
        if let rel = activeRel, changed.contains(rel) || dirty == false {
            reloadActiveFromDisk()
        }
        if let first = changed.first {
            let name = (first as NSString).lastPathComponent
            let more = changed.count > 1 ? " 等 \(changed.count) 个文件" : ""
            showToast(reviewMode == .auto ? "\(s.agent.displayName) 已写入 \(name)\(more)" : "\(s.agent.displayName) 修改了 \(name)\(more) · 待审阅")
        }
    }

    private func queueReview(rel: String, baseline: [String], proposed: String, by: AgentKind?,
                             source: SessionSource, snapshot: String?, session: AgentSession?) {
        guard let v = vault else { return }
        v.acknowledge(rel, content: proposed)
        let after = Markdown.lines(proposed)
        let hunks = LineDiff.hunks(from: baseline, to: after)
        let plus = hunks.reduce(0) { $0 + $1.add.count }, minus = hunks.reduce(0) { $0 + $1.del }
        let item = SessionItem(kind: .change(rel: rel, plus: plus, minus: minus))
        if let session {
            if session.source == .terminal { session.changeItems.append(item) }
            session.items.append(item)
        }
        if hunks.isEmpty || reviewMode == .auto {
            pending[rel] = nil
            return
        }
        pending[rel] = PendingReview(rel: rel, by: by, source: source, baseline: baseline, proposed: after,
                                     hunks: hunks, snapshot: snapshot)
    }

    private func reloadActiveFromDisk() {
        guard let v = vault, let rel = activeRel else { return }
        let disk = v.read(rel)
        if disk != editorText {
            editorText = disk
            editorVersion += 1
        }
        dirty = false
    }

    /// Changes that did not come from Plume's own writes.
    private func filesChanged(_ rels: [String]) {
        guard let v = vault else { return }
        let appRunning = sessions.contains { $0.source == .app && $0.running }
        for rel in rels {
            let disk = v.diskContent(rel)
            if disk == v.knownContent(rel) { continue }
            if rel == activeRel, dirty, !appRunning {
                // Unsaved edits meet an outside write: the save path turns it into a review.
                flushSave()
                continue
            }
            if appRunning {
                writing.insert(rel)
                continue
            }
            guard let disk else {
                // Deleted.
                v.acknowledge(rel, content: nil)
                pending[rel] = nil
                if rel == activeRel, let next = v.notes.first { open(next.rel) }
                continue
            }
            let base = pending[rel]?.baseline ?? Markdown.lines(v.knownContent(rel) ?? "")
            if watchTerminal, let term = mostRecentTerminalSession() {
                queueReview(rel: rel, baseline: base, proposed: disk, by: term.agent, source: .terminal,
                            snapshot: nil, session: term)
                if pending[rel] != nil {
                    showToast("\(term.agent.displayName) 在终端中修改了 \((rel as NSString).lastPathComponent) · 待审阅")
                }
            } else {
                v.acknowledge(rel, content: disk)
            }
            if rel == activeRel {
                if dirty {
                    flushSave()
                } else {
                    reloadActiveFromDisk()
                }
            }
        }
    }

    // MARK: review

    var activePending: PendingReview? { activeRel.flatMap { pending[$0] } }

    func setHunk(_ i: Int, _ state: HunkState) {
        guard let rel = activeRel, var p = pending[rel], p.hunks.indices.contains(i) else { return }
        p.hunks[i].state = state
        pending[rel] = p
    }

    /// `all`: accept or reject everything; nil accepts whatever is still undecided.
    func finishReview(all: HunkState?) {
        guard let v = vault, let rel = activeRel, let p = pending[rel] else { return }
        let hunks = p.hunks.map { h -> Hunk in
            var h = h
            if let all { h.state = all } else if h.state == .pending { h.state = .accepted }
            return h
        }
        let result = LineDiff.apply(hunks, to: p.baseline).joined(separator: "\n")
        let accepted = hunks.filter { $0.state == .accepted }.count
        v.forceWrite(rel, result)
        pending[rel] = nil
        showDiff = false
        editorText = result
        dirty = false
        editorVersion += 1
        let name = (rel as NSString).lastPathComponent
        if accepted > 0 {
            showToast("已写入 \(name) · 接受 \(accepted) 处" + (p.snapshot.map { " · 快照 " + $0 } ?? ""))
        } else {
            showToast("已还原到 agent 写入前的版本")
        }
    }

    // MARK: terminal sessions

    func mostRecentTerminalSession() -> AgentSession? {
        sessions.filter { $0.source == .terminal && $0.alive }.max { $0.lastActivity < $1.lastActivity }
    }

    private func dropTerminalSessions() {
        sessions.removeAll { $0.source == .terminal }
        if activeSession == nil { activeSessionID = sessions.first?.id }
    }

    func pollTerminal() {
        guard watchTerminal, let v = vault else { return }
        let root = v.rootPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = TerminalWatcher.scan(root: root)
            let transcripts = found.map { f in
                (f, f.agent == .claude ? TerminalWatcher.claudeTranscript(cwd: f.cwd) : TerminalWatcher.codexTranscript(cwd: f.cwd))
            }
            var parsed: [Int32: (URL, Date, [AgentEvent])] = [:]
            let known = DispatchQueue.main.sync { [weak self] in
                Dictionary(uniqueKeysWithValues: (self?.sessions ?? []).compactMap { s in s.pid.map { ($0, s.transcriptStamp) } })
            }
            for (f, u) in transcripts {
                guard let u, let m = TerminalWatcher.modified(u) else { continue }
                if let stamp = known[f.pid], stamp == m { continue }
                parsed[f.pid] = (u, m, TerminalWatcher.events(transcript: u, agent: f.agent, root: root))
            }
            DispatchQueue.main.async { self?.applyTerminalScan(found, parsed) }
        }
    }

    private func applyTerminalScan(_ found: [TerminalWatcher.Found], _ parsed: [Int32: (URL, Date, [AgentEvent])]) {
        let pids = Set(found.map(\.pid))
        for s in sessions where s.source == .terminal {
            s.alive = s.pid.map(pids.contains) ?? false
            s.running = s.alive && Date().timeIntervalSince(s.lastActivity) < 15
        }
        for f in found where !sessions.contains(where: { $0.pid == f.pid }) {
            let s = AgentSession(agent: f.agent, source: .terminal, title: "终端会话")
            s.pid = f.pid
            sessions.insert(s, at: 0)
            if activeSessionID == nil { activeSessionID = s.id }
        }
        for (pid, (u, stamp, events)) in parsed {
            guard let s = sessions.first(where: { $0.pid == pid }) else { continue }
            s.transcript = u
            s.transcriptStamp = stamp
            s.items = []
            s.title = "终端会话"
            s.apply(events)
            s.settleSteps()
            s.items += s.changeItems
            if let firstUser = s.items.first(where: { if case .user = $0.kind { return true }; return false }),
               case let .user(t) = firstUser.kind {
                s.title = String(t.prefix(10))
            }
        }
        // Forget terminal sessions that ended and never touched the vault.
        sessions.removeAll { $0.source == .terminal && !$0.alive && $0.changeItems.isEmpty && $0.id != activeSessionID }
    }

    func newSession() {
        let s = AgentSession(agent: agentPick, source: .app, title: "新会话")
        sessions.append(s)
        activeSessionID = s.id
    }

    // MARK: stats

    var stats: String {
        _ = tick
        let lines = Markdown.lines(editorText)
        let words = Markdown.countWords(lines)
        let now = Date()
        let pace = typed.filter { now.timeIntervalSince($0.0) < 60 }.reduce(0) { $0 + $1.1 }
        var s = "\(words.formatted()) 字 · 约 \(max(1, Int(ceil(Double(words) / 400)))) 分钟"
        if netTyped > 0 { s += " · 本次 +\(netTyped)" }
        if pace > 0 { s += " · \(pace) 字/分" }
        return s
    }

    // MARK: chrome actions

    func toggleZen() {
        palette = false
        if zen {
            zen = false
            if let (cols, agent) = beforeZen { columnVisibility = cols; agentPanel = agent }
            beforeZen = nil
        } else {
            beforeZen = (columnVisibility, agentPanel)
            zen = true
            columnVisibility = .detailOnly
            agentPanel = false
        }
    }

    func toggleSidebar() { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }
    func toggleAgent() {
        if zen { toggleZen() }
        agentPanel.toggle()
    }
    func openPalette() { palette = true; paletteQuery = ""; paletteSel = 0 }
    func openSettings(_ tab: SettingsTab) {
        settingsTab = tab
        openSettingsAction?()
    }

    func reviewNext() {
        guard let rel = activeRel.flatMap({ pending[$0] != nil ? $0 : nil }) ?? pending.keys.sorted().first else { return }
        if zen { toggleZen() }
        open(rel)
        showDiff = true
    }

    func trash(_ rel: String) {
        guard let v = vault else { return }
        NSWorkspace.shared.recycle([v.url(rel)]) { _, _ in
            DispatchQueue.main.async {
                v.scan()
                self.pending[rel] = nil
                if rel == self.activeRel, let next = v.notes.first { self.open(next.rel) }
            }
        }
    }

    func finishOnboarding() {
        defaults.set(true, forKey: "onboarded")
        onboardingStep = nil
        if vault == nil { openVault(Self.defaultVaultURL) }
        let lines = Markdown.lines(editorText)
        let caret = lines.count > 1 ? (lines[0] as NSString).length + 1 + (lines[1] as NSString).length : (editorText as NSString).length
        requestFocus(caret: caret)
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择库"
        panel.message = "选择一个存放 Markdown 笔记的文件夹"
        panel.directoryURL = vault?.root ?? Self.defaultVaultURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let u = panel.url { openVault(u) }
    }

    func revealVault() {
        guard let v = vault else { return }
        NSWorkspace.shared.activateFileViewerSelecting([v.root])
    }
}
