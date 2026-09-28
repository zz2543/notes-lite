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
enum SettingsTab: String { case editor, agent, open, keys }

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

@MainActor @Observable
final class AppModel {
    // MARK: preferences
    var font: EditorFont = .serif { didSet { save("font", font.rawValue) } }
    var typewriter = true { didSet { save("typewriter", typewriter) } }
    var dim = true { didSet { save("dim", dim) } }
    /// How pasted pictures are named (`Attachments.swift`).
    var attachmentNaming: AttachmentNaming = .pasted { didSet { save("attachmentName", attachmentNaming.rawValue) } }
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
                activeSpace = nil
                openDesk = nil
                openDesk = String(s.dropFirst(5))
                return
            }
            if s.hasPrefix("space:") {
                openSpace(String(s.dropFirst(6)))
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

    /// Links, headings and tasks of the open vault, as of the last walk of the folder. Replaced
    /// (never changed in place) by each walk that found something new; commands that must see
    /// the disk as it is now use `withFreshIndex`.
    var index: VaultIndex?
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
    /// Local HTTP API for other apps (`HTTPGateway.swift`).
    var httpOn = true { didSet { save("httpOn", httpOn); if oldValue != httpOn { startHTTP() } } }
    var httpPort: UInt16 = HTTPGateway.defaultPort { didSet { save("httpPort", Int(httpPort)) } }
    @ObservationIgnored let http = HTTPGateway()
    /// Bumped whenever a data collection changes, so spaces redraw their charts.
    var dataVersion = 0
    /// Plugins in `.twain/plugins/` and the space shown in place of a note (`Spaces.swift`).
    var plugins: [Plugin] = []
    var activeSpace: String?
    var newSpaceSheet = false
    /// 问库 desks (`ResearchDesk.swift`) and the one shown in place of a note.
    var desks: [ResearchDesk] = []
    var openDesk: String?
    var writing: Set<String> = []

    /// The editor refreshes embedded notes when other notes change on disk.
    @ObservationIgnored var noteFilesChanged: (() -> Void)?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored private var ghostWork: DispatchWorkItem?
    @ObservationIgnored private let ghostCompleter = GhostCompleter()
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored var runSnapshots: [UUID: (snap: VaultSnapshot, git: String?)] = [:]
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
        refreshModels()
        // The CLIs rewrite their model lists as they update; pick that up whenever Twain comes back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshModels() }
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
        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick += 1 } })
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollTerminal() } })
    }

    // MARK: prefs

    private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: "pref." + key) }

    private func loadPrefs() {
        func b(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: "pref." + k) as? Bool ?? d }
        font = EditorFont(rawValue: defaults.string(forKey: "pref.font") ?? "") ?? .serif
        typewriter = b("typewriter", true)
        dim = b("dim", true)
        attachmentNaming = AttachmentNaming(rawValue: defaults.string(forKey: "pref.attachmentName") ?? "") ?? .pasted
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
        httpOn = b("httpOn", true)
        httpPort = UInt16(defaults.object(forKey: "pref.httpPort") as? Int ?? Int(HTTPGateway.defaultPort))
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
        let v = Vault(root: url)
        v.onFilesChanged = { [weak self] rels in self?.filesChanged(rels) }
        v.onIndex = { [weak self] fresh in
            guard let self, self.vault === v, fresh.generation != self.index?.generation || self.index == nil else { return }
            self.index = fresh
        }
        vault = v
        index = nil
        // Reads every note into the index off the main thread, so the first search, space or
        // agent call only has to check modification dates.
        v.refresh()
        ensureTwainFolder()
        loadPlugins()
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
        if syncContext { ensureContextFiles() } else { refreshContextSync() }
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
        importInbox()
    }

    static let welcomeNote = """
    # 欢迎使用共笔
    这个库就是磁盘上的一个文件夹，每篇笔记都是一个 **Markdown** 文件。
    ## 试试看
    - [ ] 输入 `/` 打开斜杠命令
    - [ ] 按 ⌘K 搜索笔记与命令
    - [ ] 按 ⌘J 打开 Agent 面板，让 Claude Code 或 Codex 修改这篇笔记
    - [ ] 在侧栏的「空间」里打开工作台，或新建日记、自律、子弹笔记、LLM Wiki 空间
    - [ ] 在「问库」里提一个问题，agent 会把找到的结论做成卡片
    > Agent 的每一次写入都会进入审阅，可以逐段接受或还原；让它审阅时，意见会作为批注出现在正文旁边。

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
    - `twain annotate <笔记> --items '[{"quote": 原文, "text": 批注, "kind": "suggestion"}]'`：审阅时在原文旁留批注，不改正文
    - `twain data add <集合> --record '{"hours": 7.5}'`、`twain data query <集合> --since 7d`：睡眠、运动、打卡等数据

    ## 读库的习惯
    - 找资料先 `skim`，看准了再 `read` 到需要的层级，不要一上来读全文
    - 改动一律走 `propose` 并写清理由；只是评论或提问就用 `annotate`
    - 笔记属于某个空间（日记、自律……）时，共笔会把那个空间的规则一并交给你，照做即可

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
        refreshContextSync()
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

    /// CLAUDE.md imports AGENTS.md. Kept up to date when either file changes, rather than read
    /// from disk each time the sidebar draws.
    private(set) var contextInSync = false

    func refreshContextSync() {
        let now: Bool = {
            guard let v = vault, let c = v.diskContent("CLAUDE.md") else { return false }
            return c.contains("@AGENTS.md") && FileManager.default.fileExists(atPath: v.url("AGENTS.md").path)
        }()
        if now != contextInSync { contextInSync = now }
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
        activeSpace = nil
        unreadable = Self.unreadableReason(v.url(rel))
        editorText = unreadable == nil ? v.read(rel) : ""
        oversizedDisplay = nil
        oversized = Self.hasOversizedLine(editorText)
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

    /// The open note has a line too long to typeset and edit smoothly: it is shown as plain,
    /// read-only text instead of risking a hang in the text system.
    var oversized = false { didSet { if !oversized { oversizedDisplay = nil } } }
    /// What the editor shows for an oversized note: the text with its huge lines clipped, since
    /// TextKit cannot typeset a paragraph of millions of characters. The file is never written from it.
    @ObservationIgnored var oversizedDisplay: String?
    static let oversizedLine = 100_000

    static func hasOversizedLine(_ text: String) -> Bool {
        guard text.utf8.count > oversizedLine else { return false }
        var run = 0
        for b in text.utf8 {
            if b == 0x0A { run = 0 } else { run += 1; if run > oversizedLine { return true } }
        }
        return false
    }

    /// The text the editor shows: the note, or its clipped display copy when it is oversized.
    var editorDisplayText: String {
        guard oversized else { return editorText }
        if let d = oversizedDisplay { return d }
        let d = Markdown.lines(editorText).map { line -> String in
            let n = (line as NSString).length
            guard n > 2000 else { return line }
            return (line as NSString).substring(to: 2000) + " …（此行还有 \(n - 2000) 个字符未显示）"
        }.joined(separator: "\n")
        oversizedDisplay = d
        return d
    }

    var editorReadOnly: Bool {
        guard let rel = activeRel, unreadable == nil, !oversized else { return true }
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
            oversizedDisplay = nil
            oversized = Self.hasOversizedLine(disk)
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
                v.noteRemoved(rel)
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
