import AppKit
import Observation
import TwainCore
import SwiftUI

struct PendingReview {
    var rel: String
    /// nil when the writer was not an agent we could identify (another editor, sync…).
    let by: AgentKind?
    let source: SessionSource
    var baseline: [String]
    var proposed: [String]
    var hunks: [Hunk]
    var snapshot: String?
    /// Set for a proposal: the file still holds `baseline` and only accepted hunks get written.
    /// Nil for a change the agent already wrote, where rejecting restores the baseline.
    var proposalID: String?
    var reason: String?
    /// The agent's reason for each hunk, same indexes as `hunks`.
    var notes: [String?] = []
    /// The user's reason for rejecting each hunk.
    var feedback: [String?] = []
    /// The Twain session that made the change, for sending the review's outcome back.
    var sessionID: UUID?
    /// The proposal creates the note.
    var isNew = false

    var isProposal: Bool { proposalID != nil }

    var plus: Int { hunks.reduce(0) { $0 + LineDiff.counts($1, base: baseline).plus } }
    var minus: Int { hunks.reduce(0) { $0 + LineDiff.counts($1, base: baseline).minus } }
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
    /// Runs this vault command (`.twain/commands/<key>.md`) instead of inserting markup.
    var command: String?
    var icon: String?
    var id: String { key }

    static let all: [SlashItem] = [
        SlashItem(label: "一级标题", hint: "#", key: "h1", prefix: "# "),
        SlashItem(label: "二级标题", hint: "##", key: "h2", prefix: "## "),
        SlashItem(label: "三级标题", hint: "###", key: "h3", prefix: "### "),
        SlashItem(label: "列表", hint: "-", key: "list", prefix: "- "),
        SlashItem(label: "待办", hint: "- [ ]", key: "todo", prefix: "- [ ] "),
        SlashItem(label: "引用", hint: ">", key: "quote", prefix: "> "),
        SlashItem(label: "分割线", hint: "---", key: "hr", hr: true),
    ]

    /// Markup items, then `commands` (the vault's own agent commands).
    static func matching(_ line: String, commands: [UserCommand] = []) -> [SlashItem]? {
        guard line.hasPrefix("/"), !line.contains(" ") else { return nil }
        let q = line.dropFirst().lowercased()
        let extra = commands.map { c in
            SlashItem(label: c.title, hint: "/" + c.key, key: "cmd." + c.key, ai: c.agent, command: c.key, icon: c.icon)
        }
        let l = (all + extra).filter { q.isEmpty || $0.label.lowercased().contains(q) || $0.key.lowercased().contains(q) }
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
    /// Give runs Twain's MCP tools (propose_edit, ask_user, …) besides the `twain` command.
    var mcpOn = true { didSet { save("mcpOn", mcpOn) } }
    /// Master switch for `.twain/automations/`.
    var automationsOn = true { didSet { save("automationsOn", automationsOn) } }
    var automationDailyLimit = 20 { didSet { save("automationLimit", automationDailyLimit) } }
    /// AI summaries a day at most (each is one note in a batched call to a small model).
    var summaryDailyLimit = 100 { didSet { save("summaryLimit", summaryDailyLimit) } }
    /// Progress of an AI summary run.
    var summarizing: (done: Int, total: Int)?
    var noteInfoOpen = false
    /// The writing companion (`Companion.swift`): off unless the user turns it on.
    var companionOn = false { didSet { save("companion", companionOn) } }
    var companionTip: CompanionTip?
    var companionThinking = false
    @ObservationIgnored var companionWork: DispatchWorkItem?
    @ObservationIgnored var companionLast = Date.distantPast
    @ObservationIgnored var companionLength = 0
    @ObservationIgnored var companionCalls: [Date] = []
    @ObservationIgnored var companionModel: LiveModel?
    /// Model per agent; "" means whatever the CLI is configured to use.
    var agentModel: [AgentKind: String] = [:] {
        didSet { for k in AgentKind.allCases { save("model." + k.rawValue, agentModel[k] ?? "") } }
    }
    /// Thinking level per agent; "" means the CLI's own default for the chosen model.
    var agentEffort: [AgentKind: String] = [:] {
        didSet { for k in AgentKind.allCases { save("effort." + k.rawValue, agentEffort[k] ?? "") } }
    }
    var editorWidth: CGFloat = 680

    // MARK: chrome
    var columnVisibility: NavigationSplitViewVisibility = .all
    var agentPanel = true
    var modelPickerOpen = false
    var zen = false
    var palette = false
    var paletteQuery = ""
    var paletteSel = 0
    var settingsTab: SettingsTab = .editor
    var sidebarFilter = ""
    /// The sidebar row whose name is being edited in place.
    var renaming: String?
    /// Sidebar list selection; choosing a row opens the note.
    var selection: String? {
        didSet {
            guard let s = selection, s != activeRel else { return }
            if s.hasPrefix("desk:") {
                flushSave()
                openDesk = String(s.dropFirst(5))
                return
            }
            if s.hasPrefix("dir:") {
                // A folder without a folder note: selecting it just opens or closes it.
                let f = String(s.dropFirst(4))
                if openFolders.contains(f) { openFolders.remove(f) } else { openFolders.insert(f) }
                return
            }
            open(s)
        }
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
    var editorVersion = 0 { didSet { recountWords(now: true) } }
    var dirty = false
    var focusRequest: (caret: Int, token: Int)?
    /// The editor's selection (UTF-16), read by agents through `twain context`. Not observed:
    /// nothing on screen depends on it.
    @ObservationIgnored var editorSelection = NSRange(location: 0, length: 0) {
        didSet {
            guard editorSelection != oldValue else { return }
            selectionChanged()
            DispatchQueue.main.async { [weak self] in self?.adoptHeadingTitle() }
        }
    }
    var ghost = ""
    var slash: SlashState?
    /// Annotations on the open note (`Annotations.swift`).
    var annotations: [Annotation] = []
    var selectedAnnotation: String?
    /// Set by the editor: replace a range as an undoable edit, or select one.
    @ObservationIgnored var applyEditorEdit: ((NSRange, String) -> Void)?
    @ObservationIgnored var selectEditorRange: ((NSRange) -> Void)?

    /// Links, headings and tasks of the open vault, for agents' queries.
    @ObservationIgnored var index: VaultIndex?
    /// Answers the `twain` command; nil until started or when another Twain already answers.
    @ObservationIgnored var server: AgentServer?
    /// Agents waiting (`propose --wait`) for the user to finish reviewing a proposal, by proposal id.
    @ObservationIgnored var proposalWaiters: [String: [AppCommand.Reply]] = [:]
    /// Questions agents asked, by id; answered ones stay so the transcript can show the answer.
    var questions: [UUID: AgentQuestion] = [:]
    @ObservationIgnored var questionReplies: [UUID: AppCommand.Reply] = [:]
    /// `twain watch` clients: the events each wants (nil: all but the opt-in ones) and where to send them.
    @ObservationIgnored var subscribers: [UUID: (events: Set<String>?, send: (Data) -> Void)] = [:]
    @ObservationIgnored var selectionEventWork: DispatchWorkItem?
    /// The vault's own commands and automations, from `.twain/`.
    var userCommands: [UserCommand] = []
    var automations: [Automation] = []
    @ObservationIgnored var automationTimers: [String: DispatchWorkItem] = [:]

    // MARK: agents
    var cli: [AgentKind: CLIInfo] = [:]
    var sessions: [AgentSession] = []
    var activeSessionID: UUID?
    var agentInput = ""
    var agentPick: AgentKind = .claude
    var modelChoices: [AgentKind: [AgentModel]] = [:]
    /// What each CLI runs when Twain passes no model, when we can tell.
    var modelFallback: [AgentKind: String] = [:]
    var effortFallback: [AgentKind: String] = [:]
    var modelsListedBy: [AgentKind: String] = [:]
    var pending: [String: PendingReview] = [:] {
        didSet { if pipelineRuns.values.contains(where: { $0.status == .waitingReview }) { pipelineReviewsChanged() } }
    }
    /// The vault's pipelines (`.twain/pipelines/`) and the runs in progress (`Pipelines.swift`).
    var pipelines: [Pipeline] = []
    var pipelineRuns: [UUID: PipelineRun] = [:]
    /// 问库 desks (`ResearchDesk.swift`) and the one shown in place of a note.
    var desks: [ResearchDesk] = []
    var openDesk: String?
    var writing: Set<String> = []

    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored private var ghostWork: DispatchWorkItem?
    @ObservationIgnored private let ghostCompleter = GhostCompleter()
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var runSnapshots: [UUID: (snap: VaultSnapshot, git: String?)] = [:]
    @ObservationIgnored var typed: [(Date, Int)] = []
    @ObservationIgnored var netTyped = 0
    @ObservationIgnored private var focusToken = 0

    private let defaults = UserDefaults.standard

    init() {
        LegacyPlume.migrateDefaults()
        LegacyPlume.migrateTool()
        loadPrefs()
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, CLIEnvironment.detect($0)) })
            DispatchQueue.main.async { self.cli = found }
        }
        refreshModels()
        // The CLIs rewrite their model lists as they update; pick that up whenever Twain comes back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshModels()
        }
        #if DEBUG
        // A scratch vault for snapshots and manual checks; never saved as the user's vault.
        let snapshotVault = ProcessInfo.processInfo.environment["TWAIN_SNAPSHOT_VAULT"]
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
        mcpOn = b("mcpOn", true)
        automationsOn = b("automationsOn", true)
        automationDailyLimit = defaults.object(forKey: "pref.automationLimit") as? Int ?? 20
        summaryDailyLimit = defaults.object(forKey: "pref.summaryLimit") as? Int ?? 100
        companionOn = b("companion", false)
        agentModel = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map {
            ($0, defaults.string(forKey: "pref.model." + $0.rawValue) ?? "")
        })
        agentEffort = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map {
            ($0, defaults.string(forKey: "pref.effort." + $0.rawValue) ?? "")
        })
    }

    // MARK: vault

    static var defaultVaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Vault")
    }

    func openVault(_ url: URL) {
        flushSave()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        LegacyPlume.migrateVault(url)
        let v = Vault(root: url)
        v.onFilesChanged = { [weak self] rels in self?.filesChanged(rels) }
        vault = v
        index = VaultIndex(root: v.root)
        ensureTwainFolder()
        v.onTwainFilesChanged = { [weak self] paths in
            if paths.contains(where: { $0.hasPrefix(".twain/commands") || $0.hasPrefix(".twain/automations") }) { self?.loadVaultConfig() }
            self?.twainFilesChanged(paths)
        }
        loadVaultConfig()
        #if DEBUG
        if ProcessInfo.processInfo.environment["TWAIN_SNAPSHOT_VAULT"] == nil {
            defaults.set(v.rootPath, forKey: "vaultPath")
        }
        #else
        defaults.set(v.rootPath, forKey: "vaultPath")
        #endif
        pending = [:]
        writing = []
        loadProposals()
        sessions.removeAll { $0.source == .terminal }
        if syncContext { ensureContextFiles() }
        if v.notes.filter({ !$0.isAgentFile }).isEmpty {
            _ = v.create(title: "欢迎使用共笔", content: Self.welcomeNote)
        }
        openFolders = Set(v.folders.filter { !$0.contains("/") })
        let first = v.notes.first { !$0.isAgentFile && $0.folder.isEmpty } ?? v.notes.first { !$0.isAgentFile } ?? v.notes.first
        activeRel = nil
        if let first { open(first.rel) }
        pollTerminal()
        companionModel?.stop()
        companionModel = nil
        warmCompanion()
        openDesk = nil
        loadDesks()
    }

    static let welcomeNote = """
    # 欢迎使用共笔
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

    ## 共笔命令
    在库目录里可以运行 `twain`（`twain help` 查看全部）：
    - `twain context`：用户当前打开的笔记、选中的文字、光标所在标题
    - `twain skim [--folder 文件夹] [词]`：先看笔记“名片”（标题、标签、一句话摘要），不读正文
    - `twain read <笔记> --level 1|2|3 [--section 标题]`：按层级读，名片 → 提纲 → 正文或某一节
    - `twain search <词>`、`twain backlinks <笔记>`、`twain tasks`：搜索、反链、全库待办
    - `twain open <笔记> --line N`：在共笔里打开给用户看
    - `twain propose <笔记> --content - --reason 理由`：提交修改，用户逐段审阅后才写入
    - `twain ask "问题" --options A,B`：拿不准时直接问用户
    - `twain reviews`：用户最近接受和拒绝了哪些修改、为什么

    """

    static let claudeTemplate = """
    # CLAUDE.md
    @AGENTS.md
    > 由共笔维护，与 AGENTS.md 同源。请直接编辑 [[AGENTS]]。

    """

    /// AGENTS.md is the single source; CLAUDE.md only imports it.
    func ensureContextFiles() {
        guard let v = vault else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: v.url("AGENTS.md").path) { v.forceWrite("AGENTS.md", Self.agentsTemplate) }
        if !fm.fileExists(atPath: v.url("CLAUDE.md").path) { v.forceWrite("CLAUDE.md", Self.claudeTemplate) }
        v.scan()
    }

    /// `.twain/` marks the folder as a vault for the `twain` command and holds Twain's own files.
    func ensureTwainFolder() {
        guard let v = vault else { return }
        let dir = v.root.appendingPathComponent(".twain")
        let ignore = dir.appendingPathComponent(".gitignore")
        guard !FileManager.default.fileExists(atPath: ignore.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Commands and automations belong with the vault; proposals and caches do not.
        try? "proposals/\nindex/\n".write(to: ignore, atomically: true, encoding: .utf8)
    }

    var contextInSync: Bool {
        guard let v = vault, let c = v.diskContent("CLAUDE.md") else { return false }
        return c.contains("@AGENTS.md") && FileManager.default.fileExists(atPath: v.url("AGENTS.md").path)
    }

    var activeNote: NoteRef? { activeRel.flatMap { vault?.note($0) } ?? activeRel.map { NoteRef(rel: $0) } }

    // MARK: editor

    func open(_ rel: String, focus: Bool = false) {
        guard let v = vault else { return }
        if rel != activeRel {
            flushSave()
            adoptHeadingTitle(leaving: true)
        }
        activeRel = rel
        openDesk = nil
        unreadable = Self.unreadableReason(v.url(rel))
        editorText = unreadable == nil ? v.read(rel) : ""
        if unreadable != nil { v.acknowledge(rel, content: nil) }
        editorSelection = NSRange(location: 0, length: 0)
        if pending[rel] == nil { showDiff = false }
        dirty = false
        clearGhost()
        slash = nil
        editorVersion += 1
        palette = false
        selectedAnnotation = nil
        loadAnnotations()
        if selection != rel { selection = rel }
        if focus { requestFocus(caret: (editorText as NSString).length) }
        revealInSidebar(rel)
        emit("note.opened", source: "user", ["path": .string(rel)])
    }

    func revealInSidebar(_ rel: String) {
        var folder = (rel as NSString).deletingLastPathComponent
        while !folder.isEmpty {
            openFolders.insert(folder)
            folder = (folder as NSString).deletingLastPathComponent
        }
    }

    func requestFocus(caret: Int) {
        // The editor applies it on the next turn; agents asking right away see it already.
        editorSelection = NSRange(location: min(caret, (editorText as NSString).length), length: 0)
        focusToken += 1
        focusRequest = (caret, focusToken)
    }

    /// HTML notes show their source in the editor instead of the rendered page.
    var htmlSource = false

    /// Why the open file can't be shown as text (binary, far too large); nil when it can.
    var unreadable: String?

    static func unreadableReason(_ u: URL) -> String? {
        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 8 * 1024 * 1024 { return "这个文件有 \(size / 1024 / 1024) MB，超出了编辑器能流畅打开的大小。" }
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        let head = h.readData(ofLength: 8192)
        if head.contains(0) { return "这个文件含有二进制内容（例如全是空字节），不是文本笔记，可能已经损坏。" }
        return nil
    }

    var editorReadOnly: Bool {
        guard let rel = activeRel, unreadable == nil else { return true }
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
        recountWords()
        companionTextChanged()
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
            emit("note.saved", source: "user", ["path": .string(rel)])
        case let .conflict(disk):
            // Someone else wrote the file after we last read it: theirs wins, ours goes to review.
            let mine = editorText
            v.acknowledge(rel, content: disk)
            pending[rel] = PendingReview(rel: rel, by: nil, source: .terminal,
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
        emit("note.created", source: "user", ["path": .string(rel)])
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

    // MARK: rename

    /// Edits the open note's name in its sidebar row.
    func beginRename() {
        guard let rel = activeRel, vault?.note(rel) != nil else { return }
        palette = false
        sidebarFilter = ""
        if zen { toggleZen() }
        columnVisibility = .all
        revealInSidebar(rel)
        renaming = rel
    }

    /// Renames the note's file and the `[[links]]` pointing at it. False when it didn't happen
    /// (the reason is shown), so an inline editor can stay open.
    @discardableResult
    func renameNote(_ rel: String, to title: String) -> Bool {
        guard let v = vault else { return false }
        if writing.contains(rel) { showToast("Agent 正在写入这篇笔记，稍后再改名"); return false }
        if rel == activeRel { flushSave() }
        let old = NoteRef(rel: rel).title
        let new: String
        do { new = try v.rename(rel, to: title) } catch {
            showToast(error.localizedDescription)
            return false
        }
        guard new != rel else { return true }
        if var p = pending.removeValue(forKey: rel) { p.rel = new; pending[new] = p }
        carryNoteData(from: rel, to: new)
        if activeRel == rel { activeRel = new }
        if selection == rel { selection = new }
        let name = NoteRef(rel: new).title
        let links = relinkNotes(from: old, to: name)
        emit("note.renamed", source: "user", ["path": .string(new), "from": .string(rel)])
        showToast(links > 0 ? "已重命名为「\(name)」，并更新了 \(links) 处链接" : "已重命名为「\(name)」")
        return true
    }

    /// Points `[[old]]` links at `new`, unless another note still answers to `old`.
    func relinkNotes(from old: String, to new: String) -> Int {
        guard let v = vault, v.note(titled: old) == nil else { return 0 }
        var total = 0
        for n in v.notes where pending[n.rel] == nil && !writing.contains(n.rel) {
            let text = n.rel == activeRel ? editorText : v.diskContent(n.rel) ?? ""
            let (out, count) = Markdown.renamingWikiLinks(in: text, from: old, to: new)
            guard count > 0, case .ok = v.write(n.rel, out) else { continue }
            total += count
            if n.rel == activeRel {
                editorText = out
                editorVersion += 1
            }
        }
        return total
    }

    /// A note still named 未命名 takes its first heading as its name once the caret leaves
    /// that heading, or the note is closed.
    func adoptHeadingTitle(leaving: Bool = false) {
        guard let v = vault, let rel = activeRel, !writing.contains(rel), pending[rel] == nil,
              Self.isUntitled(NoteRef(rel: rel).title),
              let heading = Markdown.titleHeading(editorText), !Self.isUntitled(heading) else { return }
        let firstLine = (editorText.prefix { $0 != "\n" } as Substring).utf16.count
        guard leaving || editorSelection.location > firstLine else { return }
        var name = heading.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name.removeFirst() }
        guard !name.isEmpty else { return }
        let folder = (rel as NSString).deletingLastPathComponent
        renameNote(rel, to: NoteRef(rel: v.uniqueRel(title: name, folder: folder)).title)
    }

    /// Twain's own files under `.twain/` changed (plugins, data drops); extended by later features.
    func twainFilesChanged(_ paths: Set<String>) {
        if paths.contains(where: { $0.hasPrefix(".twain/annotations") }) { loadAnnotations() }
        if paths.contains(where: { $0.hasPrefix(".twain/pipelines") }) { loadPipelines() }
    }

    /// What Twain keeps about a note outside it (summary, annotations) follows the note when it moves.
    func carryNoteData(from old: String, to new: String) {
        guard let v = vault, old != new else { return }
        SummaryStore(vault: v.root).rename(old, to: new)
        AnnotationStore(vault: v.root).rename(old, to: new)
    }

    func selectAnnotation(_ id: String) {
        selectedAnnotation = id
        guard let a = annotations.first(where: { $0.id == id }), let r = Anchor.locate(a.quote, in: editorText, line: a.line) else { return }
        selectEditorRange?(r)
    }

    static func isUntitled(_ title: String) -> Bool {
        title.range(of: #"^未命名( \d+)?$"#, options: .regularExpression) != nil
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

    /// Re-reads each CLI's model list and defaults off the main thread.
    func refreshModels() {
        DispatchQueue.global(qos: .userInitiated).async {
            let models = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, CLIEnvironment.models($0)) })
            DispatchQueue.main.async {
                let choices = models.mapValues(\.choices)
                if choices != self.modelChoices { self.modelChoices = choices }
                self.modelFallback = models.compactMapValues(\.fallback)
                self.effortFallback = models.compactMapValues(\.fallbackEffort)
                self.modelsListedBy = models.compactMapValues(\.listedBy)
            }
        }
    }

    func models(_ k: AgentKind) -> [AgentModel] { modelChoices[k] ?? k.builtinModels }

    /// Set when the model list came from a newer client than the CLI Twain runs, e.g. the Codex app.
    func staleCLIWarning(_ k: AgentKind) -> String? {
        guard let listed = modelsListedBy[k], let cliVersion = cli[k]?.version,
              versionIsOlder(cliVersion, than: listed) else { return nil }
        return "模型列表来自 \(k.displayName) \(listed)，而共笔调用的 \(cliVersion) 较旧，新模型可能无法运行。升级 \(k.executable) 命令行后即可使用。"
    }

    /// Human name for a model id; "" is the CLI default.
    func modelName(_ id: String, for k: AgentKind) -> String {
        if id.isEmpty { return modelFallback[k].map { "默认（\(modelName($0, for: k))）" } ?? "默认" }
        return models(k).find(id)?.name ?? id
    }

    /// The name of the model the next run uses, without the "默认（…）" wrapper.
    func modelLabel(_ k: AgentKind) -> String {
        let id = agentModel[k] ?? ""
        if id.isEmpty, let f = modelFallback[k] { return modelName(f, for: k) }
        return modelName(id, for: k)
    }

    /// The model the next run of `k` uses, if it's one we know.
    func currentModel(_ k: AgentKind) -> AgentModel? {
        let id = agentModel[k] ?? ""
        return models(k).find(id.isEmpty ? modelFallback[k] ?? "" : id)
    }

    /// Thinking levels the next run's model offers. Unknown model: the common levels.
    func effortLevels(_ k: AgentKind) -> [String] {
        currentModel(k)?.efforts ?? ["low", "medium", "high", "xhigh", "max"]
    }

    /// The level Twain passes on the command line: the user's pick, fitted to the model; "" to leave it to the CLI.
    func effortArgument(_ k: AgentKind) -> String {
        let pick = agentEffort[k] ?? ""
        guard !pick.isEmpty else { return "" }
        return Effort.clamp(pick, to: effortLevels(k)) ?? ""
    }

    /// The level the next run actually thinks at, as far as we can tell.
    func effectiveEffort(_ k: AgentKind) -> String? {
        let levels = effortLevels(k)
        guard !levels.isEmpty else { return nil }
        let arg = effortArgument(k)
        if !arg.isEmpty { return arg }
        if let f = effortFallback[k] { return Effort.clamp(f, to: levels) }
        return currentModel(k)?.defaultEffort
    }

    /// Starts a run the user asked for. `target` continues that session (sending review feedback
    /// back, say); otherwise the active session is reused when it fits, or a new one begins.
    func runAgent(prompt: String, agent: AgentKind, model: String? = nil, effort: String? = nil, in target: AgentSession? = nil) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, vault != nil else { return }
        var session = target ?? activeSession
        if let t = target, t.running {
            showToast("\(t.agent.displayName) 还在运行，等它结束再发送")
            return
        }
        if target == nil, session == nil || session!.source != .app || session!.agent != agent || session!.running {
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
        launch(s, prompt: prompt, model: model, effort: effort)
    }

    /// Runs `prompt` in `s`, resuming the CLI's own session when there is one. Automation
    /// sessions run read-only: their only way to change a note is a proposal.
    @discardableResult
    func launch(_ s: AgentSession, prompt: String, model: String? = nil, effort: String? = nil) -> Bool {
        let agent = s.agent
        guard let v = vault else { return false }
        guard agentEnabled(agent) else { showToast(agent.displayName + " 已在设置中停用"); return false }
        guard let exe = cli[agent]?.path ?? CLIEnvironment.locate(agent.executable) else {
            showToast("没有找到 " + agent.executable + " 命令")
            return false
        }
        flushSave()
        clearGhost()
        s.items.append(SessionItem(kind: .user(prompt)))
        s.running = true
        let model = model ?? agentModel[agent] ?? ""
        let effort = effort ?? effortArgument(agent)
        s.model = model.isEmpty ? modelFallback[agent] : model
        s.effort = effort.isEmpty ? effectiveEffort(agent) : effort
        let readOnly = s.source == .automation || s.readOnly

        let proc = AgentProcess(kind: agent)
        s.process = proc
        let root = v.root, rels = v.notes.map(\.rel), takeGit = gitSnapshot && !readOnly
        // The snapshot reads every note (and may commit to git): never on the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let git = takeGit ? Git.snapshot(root, message: "Twain: snapshot before \(agent.displayName)") : nil
            let snap = VaultSnapshot.take(root: root, rels: rels)
            DispatchQueue.main.async {
                guard let self, s.process === proc, s.running else { return }
                self.runSnapshots[s.id] = (snap, git)
                self.start(s, proc: proc, exe: exe, prompt: prompt, model: model, effort: effort, readOnly: readOnly)
            }
        }
        return true
    }

    private func start(_ s: AgentSession, proc: AgentProcess, exe: String, prompt: String, model: String, effort: String, readOnly: Bool) {
        guard let v = vault else { return }
        let agent = s.agent
        let tool = TwainTool.prepare()
        var env = ["TWAIN_SESSION": s.id.uuidString]
        if !s.extraTools.isEmpty { env["TWAIN_MCP_EXTRA"] = s.extraTools.joined(separator: ",") }
        if let tool { env["PATH"] = tool.path }
        if let server { env["TWAIN_SOCK"] = server.path }
        let mcp: AgentArguments.MCP? = mcpOn && tool != nil
            ? AgentArguments.MCP(command: TwainTool.managedLink.path, env: env.filter { $0.key != "PATH" }) : nil
        // Claude Code gives up on a tool call after its own default; questions may wait longer.
        if mcp != nil { env["MCP_TOOL_TIMEOUT"] = "900000" }
        let context = agentContext(tool: tool != nil, mcp: mcp != nil, readOnly: readOnly)
        let args = AgentArguments.build(kind: agent, prompt: prompt, context: context, root: v.rootPath,
                                        resume: s.cliSessionID, model: model, effort: effort, socket: server?.path,
                                        version: cli[agent]?.version, mcp: mcp, readOnly: readOnly)
        emit("session.started", source: eventSource(for: s), ["session": .string(s.id.uuidString), "agent": .string(agent.rawValue)])
        do {
            try proc.start(executable: exe, arguments: args, cwd: v.root, env: env, onEvents: { [weak self, weak s] events in
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
                self.emit("session.finished", source: self.eventSource(for: s),
                          ["session": .string(s.id.uuidString), "agent": .string(agent.rawValue), "status": JSONValue(Int(status))])
            })
        } catch {
            s.items.append(SessionItem(kind: .error("无法启动 \(exe)：\(error.localizedDescription)")))
            s.running = false
            s.process = nil
            runSnapshots[s.id] = nil
        }
    }

    /// What every run is told about Twain, beyond the user's prompt.
    func agentContext(tool: Bool, mcp: Bool, readOnly: Bool) -> String {
        let noteRel = activeRel ?? ""
        var parts = ["你在共笔笔记库中工作，当前目录就是库的根目录，库里的笔记都是 Markdown 文件。"]
        if !noteRel.isEmpty, !readOnly { parts.append("用户当前打开的笔记是 \(noteRel)，“这篇笔记”“当前笔记”指的就是它。") }
        if mcp {
            parts.append("共笔提供了一组工具（twain 服务器）：context 查看用户选中的文字和光标所在标题；"
                + "找资料时先用 skim 看笔记名片（标题、标签、一句话摘要），看准了再用 read_note 按层级读（1 名片、2 提纲、3 正文或某一节），不要一上来就通读全库；"
                + "search、backlinks、tasks 查询笔记库；propose_edit 提交修改，改动进入用户的逐段审阅，每处都要写明理由；ask_user 在拿不准时直接问用户；open 把笔记打开给用户看。")
        } else if tool {
            parts.append("可以运行 `twain` 命令：`twain context` 查看用户选中的文字和光标位置，`twain skim` 先看笔记名片、`twain read <笔记> --level 2` 按层级读，"
                + "`twain search`、`twain backlinks`、`twain tasks` 查询笔记库，"
                + "`twain propose <笔记> --content - --reason 理由` 提交修改供用户审阅，`twain ask \"问题\"` 向用户提问；`twain help` 列出全部命令。")
        }
        if readOnly {
            parts.append("这是自动化任务，你不能直接修改文件：所有修改都必须用 propose_edit（或 twain propose）提交，逐处写明理由，由用户审阅。")
        } else {
            parts.append(mcp || tool ? "修改笔记优先用 propose_edit 提交；也可以直接修改文件，共笔会把改动交给用户审阅。"
                                     : "直接修改文件即可，共笔会把改动交给用户审阅。")
        }
        parts.append("遵守 AGENTS.md 中的约定。")
        return parts.joined()
    }

    func stopAgent(_ s: AgentSession) {
        guard let p = s.process else { return }
        if p.pid == 0 {
            // Still taking the snapshot: the CLI never started.
            s.process = nil
            s.running = false
            s.items.append(SessionItem(kind: .error("已停止")))
        } else {
            p.stop()
        }
    }

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
        guard let snap = runSnapshots.removeValue(forKey: s.id) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let changes = snap.snap.changes()
            DispatchQueue.main.async { self?.applyRun(s, changes: changes, git: snap.git) }
        }
    }

    private func applyRun(_ s: AgentSession, changes: [(rel: String, before: String?, after: String?)], git: String?) {
        guard let v = vault else { return }
        v.scan()
        var changed: [String] = []
        for c in changes {
            // Skip files that only Twain itself saved during the run.
            guard let after = c.after, after != v.knownContent(c.rel) else { continue }
            changed.append(c.rel)
            let base = pending[c.rel]?.baseline ?? Markdown.lines(v.knownContent(c.rel) ?? c.before ?? "")
            queueReview(rel: c.rel, baseline: base, proposed: after, by: s.agent, source: s.source, snapshot: git, session: s)
            emit("note.changed", source: eventSource(for: s), ["path": .string(c.rel)])
        }
        for rel in writing where !changed.contains(rel) { v.acknowledge(rel, content: v.diskContent(rel)) }
        writing.removeAll()
        if let rel = activeRel, changed.contains(rel) || dirty == false {
            reloadActiveFromDisk()
        }
        if let first = changed.first {
            let name = (first as NSString).lastPathComponent
            let more = changed.count > 1 ? " 等 \(changed.count) 个文件" : ""
            let auto = reviewMode == .auto && s.source != .automation
            showToast(auto ? "\(s.agent.displayName) 已写入 \(name)\(more)" : "\(s.agent.displayName) 修改了 \(name)\(more) · 待审阅")
        }
        pipelineSessionFinished(s)
    }

    private func queueReview(rel: String, baseline: [String], proposed: String, by: AgentKind?,
                             source: SessionSource, snapshot: String?, session: AgentSession?) {
        guard let v = vault else { return }
        v.acknowledge(rel, content: proposed)
        let after = Markdown.lines(proposed)
        let hunks = LineDiff.hunks(from: baseline, to: after)
        let counts = hunks.map { LineDiff.counts($0, base: baseline) }
        let plus = counts.reduce(0) { $0 + $1.plus }, minus = counts.reduce(0) { $0 + $1.minus }
        let item = SessionItem(kind: .change(rel: rel, plus: plus, minus: minus))
        if let session {
            if session.source == .terminal { session.changeItems.append(item) }
            session.items.append(item)
        }
        // A proposal for this note no longer matches the file the agent just wrote.
        if let old = pending[rel], old.isProposal { markStale(old) }
        if hunks.isEmpty || (reviewMode == .auto && session?.source != .automation) {
            pending[rel] = nil
            return
        }
        pending[rel] = PendingReview(rel: rel, by: by, source: source, baseline: baseline, proposed: after,
                                     hunks: hunks, snapshot: snapshot, sessionID: session?.id)
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

    /// Changes that did not come from Twain's own writes.
    private func filesChanged(_ rels: [String]) {
        guard let v = vault else { return }
        let appRunning = sessions.contains { $0.source == .app && $0.running }
        var outside: [String] = []
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
            outside.append(rel)
        }
        guard !outside.isEmpty else { return }
        // Who wrote it? Only a terminal agent whose transcript shows the write gets the credit;
        // anything else (another editor, sync) is loaded as is, without a review.
        let root = v.rootPath
        let terminals = watchTerminal ? sessions.filter { $0.source == .terminal && $0.alive }.compactMap { s in
            s.transcript.map { (id: s.id, url: $0, agent: s.agent) }
        } : []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var writer: [String: UUID] = [:]
            for t in terminals {
                let recent = TerminalWatcher.recentWrites(transcript: t.url, agent: t.agent, root: root)
                for rel in outside where writer[rel] == nil {
                    let abs = (root as NSString).appendingPathComponent(rel)
                    let name = (rel as NSString).lastPathComponent
                    if recent.paths.contains(abs) || recent.paths.contains(rel) || recent.steps.contains(where: { $0.contains(name) }) {
                        writer[rel] = t.id
                    }
                }
            }
            DispatchQueue.main.async { self?.applyOutsideChanges(outside, writer: writer) }
        }
    }

    private func applyOutsideChanges(_ rels: [String], writer: [String: UUID]) {
        guard let v = vault else { return }
        var reloaded: [String] = []
        for rel in rels {
            let disk = v.diskContent(rel)
            if disk == v.knownContent(rel) { continue }
            let term = writer[rel].flatMap { id in sessions.first { $0.id == id } }
            emit(disk == nil ? "note.deleted" : "note.changed", source: term.map(eventSource) ?? "external", ["path": .string(rel)])
            guard let disk else {
                v.acknowledge(rel, content: nil)
                pending[rel] = nil
                if rel == activeRel, let next = v.notes.first { open(next.rel) }
                continue
            }
            if let term {
                let base = pending[rel]?.baseline ?? Markdown.lines(v.knownContent(rel) ?? "")
                queueReview(rel: rel, baseline: base, proposed: disk, by: term.agent, source: .terminal, snapshot: nil, session: term)
                if pending[rel] != nil {
                    showToast("\(term.agent.displayName) 在终端中修改了 \((rel as NSString).lastPathComponent) · 待审阅")
                }
            } else {
                v.acknowledge(rel, content: disk)
                reloaded.append(rel)
            }
            if rel == activeRel {
                if dirty { flushSave() } else { reloadActiveFromDisk() }
            }
        }
        if reloaded.contains(where: { $0 == activeRel }) {
            showToast("「\(((activeRel ?? "") as NSString).lastPathComponent)」在其他程序中被修改，已载入新内容")
        }
    }

    // MARK: review

    var activePending: PendingReview? { activeRel.flatMap { pending[$0] } }

    func setHunk(_ i: Int, _ state: HunkState) {
        guard let rel = activeRel, var p = pending[rel], p.hunks.indices.contains(i) else { return }
        p.hunks[i].state = state
        pending[rel] = p
    }

    // MARK: terminal sessions

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

    /// Words in the open note, recounted a moment after typing stops rather than on every key.
    var wordCount = 0
    @ObservationIgnored private var countWork: DispatchWorkItem?

    func recountWords(now: Bool = false) {
        countWork?.cancel()
        let text = editorText
        let w = DispatchWorkItem { [weak self] in
            let n = Markdown.countWords(Markdown.lines(text))
            DispatchQueue.main.async { if self?.wordCount != n { self?.wordCount = n } }
        }
        countWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + (now ? 0 : 0.4), execute: w)
    }

    var stats: String {
        _ = tick
        let words = wordCount
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
                self.emit("note.deleted", source: "user", ["path": .string(rel)])
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
