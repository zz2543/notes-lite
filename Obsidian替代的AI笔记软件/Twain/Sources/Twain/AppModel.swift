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
    // The state, by part of the window (AppState.swift). The parts are fixed; what changes is inside them.
    @ObservationIgnored let prefs = Preferences()
    @ObservationIgnored let chrome = ChromeState()
    @ObservationIgnored let editor = EditorState()
    @ObservationIgnored let agents = AgentState()

    /// Progress of an AI summary run.
    var summarizing: (done: Int, total: Int)?
    @ObservationIgnored var companionWork: DispatchWorkItem?
    @ObservationIgnored var companionLast = Date.distantPast
    @ObservationIgnored var companionLength = 0
    @ObservationIgnored var companionCalls: [Date] = []
    @ObservationIgnored var companionModel: LiveModel?
    @ObservationIgnored var openSettingsAction: (() -> Void)?
    @ObservationIgnored private var beforeZen: (NavigationSplitViewVisibility, Bool)?
    /// Bumped when a daily counter or an approval stored in UserDefaults changes, so what shows
    /// them redraws then (and only then).
    var countersVersion = 0
    /// The local HTTP API as last reported by its listener.
    var httpStatus = HTTPStatus()

    // MARK: vault
    var vault: Vault?
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
    @ObservationIgnored var questionReplies: [UUID: AppCommand.Reply] = [:]
    /// `twain watch` clients: the events each wants (nil: all but the opt-in ones) and where to send them.
    @ObservationIgnored var subscribers: [UUID: (events: Set<String>?, send: (Data) -> Void)] = [:]
    @ObservationIgnored var selectionEventWork: DispatchWorkItem?
    /// The vault's own commands and automations, from `.twain/`.
    var userCommands: [UserCommand] = []
    var automations: [Automation] = []
    @ObservationIgnored var automationTimers: [String: DispatchWorkItem] = [:]
    @ObservationIgnored let http = HTTPGateway()
    /// Bumped whenever a data collection changes, so spaces redraw their charts.
    var dataVersion = 0
    /// Plugins in `.twain/plugins/` (`Spaces.swift`).
    var plugins: [Plugin] = []
    /// 问库 desks (`ResearchDesk.swift`).
    var desks: [ResearchDesk] = []

    /// The editor refreshes embedded notes when other notes change on disk.
    @ObservationIgnored var noteFilesChanged: (() -> Void)?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored private var ghostWork: DispatchWorkItem?
    @ObservationIgnored private let ghostCompleter = GhostCompleter()
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored var runSnapshots: [UUID: (snap: VaultSnapshot, git: String?)] = [:]
    @ObservationIgnored private var focusToken = 0

    private let defaults = UserDefaults.standard

    /// What choosing a sidebar row does.
    private func select(_ s: String) {
        guard s != editor.activeRel else { return }
        if s.hasPrefix("desk:") {
            flushSave()
            chrome.activeSpace = nil
            chrome.openDesk = nil
            chrome.openDesk = String(s.dropFirst(5))
            return
        }
        if s.hasPrefix("space:") {
            openSpace(String(s.dropFirst(6)))
            return
        }
        if s.hasPrefix("dir:") {
            // A folder without a folder note: selecting it just opens or closes it.
            let f = String(s.dropFirst(4))
            if chrome.openFolders.contains(f) { chrome.openFolders.remove(f) } else { chrome.openFolders.insert(f) }
            return
        }
        open(s)
    }

    /// The parts' reactions that reach beyond themselves.
    private func connectParts() {
        prefs.changed = { [weak self] change in
            guard let self else { return }
            switch change {
            case .ghost: if !self.prefs.ghostOn { self.clearGhost() }
            case .syncContext: if self.prefs.syncContext { self.ensureContextFiles() }
            case .watchTerminal: if !self.prefs.watchTerminal { self.dropTerminalSessions() }
            case .http: self.startHTTP()
            }
        }
        chrome.selected = { [weak self] s in self?.select(s) }
        editor.versionChanged = { [weak self] in self?.recountWords(now: true) }
        editor.selectionChanged = { [weak self] in
            self?.selectionChanged()
            DispatchQueue.main.async { [weak self] in self?.adoptHeadingTitle() }
        }
        agents.pendingChanged = { [weak self] in
            guard let self, self.agents.pipelineRuns.values.contains(where: { $0.status == .waitingReview }) else { return }
            self.pipelineReviewsChanged()
        }
    }

    init() {
        connectParts()
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, CLIEnvironment.detect($0)) })
            DispatchQueue.main.async { self.agents.cli = found }
        }
        refreshModels()
        // The CLIs rewrite their model lists as they update; pick that up whenever Twain comes back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshModels()
                // A new day resets the daily counters.
                self?.countersVersion += 1
            }
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
        if !defaults.bool(forKey: "onboarded") || vault == nil { chrome.onboardingStep = 0 }
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollTerminal() } })
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
        agents.pending = [:]
        agents.writing = []
        loadProposals()
        if agents.sessions.contains(where: { $0.source == .terminal }) { agents.sessions.removeAll { $0.source == .terminal } }
        if prefs.syncContext { ensureContextFiles() } else { refreshContextSync() }
        if v.notes.filter({ !$0.isAgentFile }).isEmpty {
            _ = v.create(title: "欢迎使用共笔", content: Self.welcomeNote)
        }
        chrome.openFolders = Set(v.folders.filter { !$0.contains("/") })
        let first = v.notes.first { !$0.isAgentFile && $0.folder.isEmpty } ?? v.notes.first { !$0.isAgentFile } ?? v.notes.first
        editor.activeRel = nil
        if let first { open(first.rel) }
        pollTerminal()
        companionModel?.stop()
        companionModel = nil
        warmCompanion()
        chrome.openDesk = nil
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

    var activeNote: NoteRef? { editor.activeRel.flatMap { vault?.note($0) } ?? editor.activeRel.map { NoteRef(rel: $0) } }

    // MARK: editor

    func open(_ rel: String, focus: Bool = false) {
        guard let v = vault else { return }
        if rel != editor.activeRel {
            flushSave()
            adoptHeadingTitle(leaving: true)
        }
        editor.activeRel = rel
        chrome.openDesk = nil
        chrome.activeSpace = nil
        // A note iCloud has moved off this Mac is downloaded in the background: reading it here
        // would block until the download finishes. Local notes are read right away, so
        // switching between them never shows an empty page first.
        let evicted = Self.isEvicted(v.url(rel))
        editor.downloading = evicted ? rel : nil
        editor.unreadable = evicted ? nil : Self.unreadableReason(v.url(rel))
        editor.editorText = editor.unreadable == nil && !evicted ? v.read(rel) : ""
        if evicted { fetchEvicted(rel) }
        editor.oversizedDisplay = nil
        editor.oversized = Self.hasOversizedLine(editor.editorText)
        if editor.unreadable != nil { v.acknowledge(rel, content: nil) }
        editor.editorSelection = NSRange(location: 0, length: 0)
        if agents.pending[rel] == nil { editor.showDiff = false }
        editor.dirty = false
        clearGhost()
        editor.slash = nil
        editor.editorVersion += 1
        chrome.palette = false
        editor.selectedAnnotation = nil
        loadAnnotations()
        if chrome.selection != rel { chrome.selection = rel }
        if focus { requestFocus(caret: (editor.editorText as NSString).length) }
        revealInSidebar(rel)
        emit("note.opened", source: "user", ["path": .string(rel)])
    }

    func revealInSidebar(_ rel: String) {
        var folder = (rel as NSString).deletingLastPathComponent
        var missing: [String] = []
        while !folder.isEmpty {
            if !chrome.openFolders.contains(folder) { missing.append(folder) }
            folder = (folder as NSString).deletingLastPathComponent
        }
        // Inserting into an observed set notifies even when the folder is already open, and
        // the whole sidebar tree depends on it: change it only when something opens.
        if !missing.isEmpty { chrome.openFolders.formUnion(missing) }
    }

    func requestFocus(caret: Int) {
        // The editor applies it on the next turn; agents asking right away see it already.
        editor.editorSelection = NSRange(location: min(caret, (editor.editorText as NSString).length), length: 0)
        focusToken += 1
        editor.focusRequest = (caret, focusToken)
    }



    static func isEvicted(_ u: URL) -> Bool {
        guard let s = try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus else { return false }
        return s == .notDownloaded
    }

    /// Downloads the note and shows it, unless another note was opened meanwhile.
    private func fetchEvicted(_ rel: String) {
        guard let v = vault else { return }
        let u = v.url(rel)
        try? FileManager.default.startDownloadingUbiquitousItem(at: u)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let deadline = Date().addingTimeInterval(60)
            while Self.isEvicted(u), Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            let why = Self.unreadableReason(u)
            let text = why == nil ? try? String(contentsOf: u, encoding: .utf8) : nil
            DispatchQueue.main.async {
                guard let self, self.editor.activeRel == rel, self.editor.downloading == rel else { return }
                self.editor.downloading = nil
                guard let text else {
                    self.editor.unreadable = why ?? "没能从 iCloud 下载这篇笔记。"
                    return
                }
                v.acknowledge(rel, content: text)
                self.editor.editorText = text
                self.editor.oversizedDisplay = nil
                self.editor.oversized = Self.hasOversizedLine(text)
                self.editor.editorVersion += 1
                self.loadAnnotations()
            }
        }
    }

    static func unreadableReason(_ u: URL) -> String? {
        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 8 * 1024 * 1024 { return "这个文件有 \(size / 1024 / 1024) MB，超出了编辑器能流畅打开的大小。" }
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        let head = h.readData(ofLength: 8192)
        if head.contains(0) { return "这个文件含有二进制内容（例如全是空字节），不是文本笔记，可能已经损坏。" }
        return nil
    }

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
        guard editor.oversized else { return editor.editorText }
        if let d = editor.oversizedDisplay { return d }
        let d = Markdown.lines(editor.editorText).map { line -> String in
            let n = (line as NSString).length
            guard n > 2000 else { return line }
            return (line as NSString).substring(to: 2000) + " …（此行还有 \(n - 2000) 个字符未显示）"
        }.joined(separator: "\n")
        editor.oversizedDisplay = d
        return d
    }

    var editorReadOnly: Bool {
        guard let rel = editor.activeRel, editor.unreadable == nil, editor.downloading == nil, !editor.oversized else { return true }
        return agents.writing.contains(rel)
    }

    /// The model changes the open note's text as if it were typed (a task checked from a space).
    func editorDidChange(_ text: String) {
        // NSTextView can notify after a model-driven reload. It is not a user edit,
        // so it must not accept a pending agent review or schedule another save.
        guard text != editor.editorText else { return }
        let delta = (text as NSString).length - (editor.editorText as NSString).length
        editor.editorText = text
        textChanged(delta: delta)
    }

    /// The user typed in the editor, changing its length by `delta` (UTF-16). The text itself
    /// stays in the editor until something reads `editor.editorText`.
    func editorEdited(delta: Int) {
        editor.textEdited()
        textChanged(delta: delta)
    }

    private func textChanged(delta: Int) {
        if delta > 0 && delta < 20 { editor.typed.append((Date(), delta)) }
        editor.netTyped += delta
        if !editor.dirty { editor.dirty = true }
        recountWords()
        companionTextChanged()
        if let rel = editor.activeRel, agents.pending[rel] != nil {
            // Editing a file under review keeps the agent's version as the new base.
            agents.pending[rel] = nil
            editor.showDiff = false
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
        guard editor.dirty, let v = vault, let rel = editor.activeRel else { return }
        if agents.writing.contains(rel) { return }
        switch v.write(rel, editor.editorText) {
        case .ok:
            editor.dirty = false
            emit("note.saved", source: "user", ["path": .string(rel)])
        case let .conflict(disk):
            // Someone else wrote the file after we last read it: theirs wins, ours goes to review.
            let mine = editor.editorText
            v.acknowledge(rel, content: disk)
            agents.pending[rel] = PendingReview(rel: rel, by: nil, source: .terminal,
                                         baseline: Markdown.lines(mine), proposed: Markdown.lines(disk),
                                         hunks: LineDiff.hunks(from: Markdown.lines(mine), to: Markdown.lines(disk)), snapshot: nil)
            editor.editorText = disk
            editor.oversizedDisplay = nil
            editor.oversized = Self.hasOversizedLine(disk)
            editor.dirty = false
            editor.editorVersion += 1
            showToast("文件在外部被修改，已载入磁盘上的版本")
        }
    }

    func toggleTask(line: Int) {
        var lines = Markdown.lines(editor.editorText)
        guard lines.indices.contains(line) else { return }
        lines[line] = Markdown.toggleTask(lines[line])
        editor.editorText = lines.joined(separator: "\n")
        editor.dirty = true
        editor.editorVersion += 1
        scheduleSave()
    }

    func newNote() {
        guard let v = vault else { return }
        flushSave()
        let rel = v.create(title: "未命名", content: "# 未命名\n")
        emit("note.created", source: "user", ["path": .string(rel)])
        chrome.palette = false
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
        editor.ghost = ""
        guard prefs.ghostOn, caretAtEnd, Markdown.blockType(paragraph) == .p, paragraph.count > 6,
              !paragraph.hasPrefix("/"), paragraph.last?.isWhitespace == false,
              agents.cli[.claude]?.found == true, let v = vault else { return }
        let before = Markdown.lines(editor.editorText).prefix(lineIndex).suffix(12).joined(separator: "\n")
        let w = DispatchWorkItem { [weak self] in
            self?.ghostCompleter.complete(paragraph: paragraph, context: before, cwd: v.root) { text in
                guard let self, self.currentParagraphForGhost == paragraph else { return }
                self.editor.ghost = text
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
        if !editor.ghost.isEmpty { editor.ghost = "" }
    }

    // MARK: toast

    func showToast(_ m: String) {
        toastWork?.cancel()
        chrome.toast = m
        let w = DispatchWorkItem { [weak self] in self?.chrome.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: w)
    }


    // MARK: stats

    @ObservationIgnored private var countWork: DispatchWorkItem?

    func recountWords(now: Bool = false) {
        countWork?.cancel()
        // The text is taken once typing pauses, not on every key.
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.editor.editorText
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let n = Markdown.countWords(Markdown.lines(text))
                DispatchQueue.main.async { if self?.editor.wordCount != n { self?.editor.wordCount = n } }
            }
        }
        countWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (now ? 0 : 0.4), execute: w)
    }

    /// Words, reading time and typing pace. The pace looks at the last minute, so the status pill
    /// redraws it on a timer of its own.
    var stats: String {
        let words = editor.wordCount
        let now = Date()
        let pace = editor.typed.filter { now.timeIntervalSince($0.0) < 60 }.reduce(0) { $0 + $1.1 }
        var s = "\(words.formatted()) 字 · 约 \(max(1, Int(ceil(Double(words) / 400)))) 分钟"
        if editor.netTyped > 0 { s += " · 本次 +\(editor.netTyped)" }
        if pace > 0 { s += " · \(pace) 字/分" }
        return s
    }

    // MARK: chrome actions

    func toggleZen() {
        chrome.palette = false
        if chrome.zen {
            chrome.zen = false
            if let (cols, agent) = beforeZen { chrome.columnVisibility = cols; chrome.agentPanel = agent }
            beforeZen = nil
        } else {
            beforeZen = (chrome.columnVisibility, chrome.agentPanel)
            chrome.zen = true
            chrome.columnVisibility = .detailOnly
            chrome.agentPanel = false
        }
    }

    func toggleAgent() {
        if chrome.zen { toggleZen() }
        chrome.agentPanel.toggle()
    }
    func openPalette() { chrome.palette = true; chrome.paletteQuery = ""; chrome.paletteSel = 0 }
    func openSettings(_ tab: SettingsTab) {
        chrome.settingsTab = tab
        openSettingsAction?()
    }

    func reviewNext() {
        guard let rel = editor.activeRel.flatMap({ agents.pending[$0] != nil ? $0 : nil }) ?? agents.pending.keys.sorted().first else { return }
        if chrome.zen { toggleZen() }
        open(rel)
        editor.showDiff = true
    }

    func trash(_ rel: String) {
        guard let v = vault else { return }
        NSWorkspace.shared.recycle([v.url(rel)]) { _, _ in
            DispatchQueue.main.async {
                v.noteRemoved(rel)
                self.agents.pending[rel] = nil
                self.emit("note.deleted", source: "user", ["path": .string(rel)])
                if rel == self.editor.activeRel, let next = v.notes.first { self.open(next.rel) }
            }
        }
    }

    func finishOnboarding() {
        defaults.set(true, forKey: "onboarded")
        chrome.onboardingStep = nil
        if vault == nil { openVault(Self.defaultVaultURL) }
        let lines = Markdown.lines(editor.editorText)
        let caret = lines.count > 1 ? (lines[0] as NSString).length + 1 + (lines[1] as NSString).length : (editor.editorText as NSString).length
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
