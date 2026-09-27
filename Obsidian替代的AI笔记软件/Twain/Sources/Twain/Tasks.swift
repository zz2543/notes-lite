import AppKit
import TwainCore
import SwiftUI

// Twain has no modes. Everything an agent does is a task, and where it shows up follows from
// where it started: a rewrite of a passage comes back into that passage, a task for the vault
// runs in the background and returns through the pending queue, a conversation takes the middle
// of the window with its draft beside it.

/// What the middle of the window shows.
enum CenterDoc: Hashable {
    /// The open note (`activeRel`).
    case note
    /// A conversation, with its draft in the side panel.
    case thread(UUID)
    /// Every task, by where it stands.
    case tasks
}

/// Somewhere ⌘[ can go back to.
struct Place: Hashable {
    var doc: CenterDoc
    var rel: String?
}

/// How much of the vault a task from ⌘L covers.
enum TaskScope: String, CaseIterable, Identifiable {
    case selection, note, vault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: "选区"
        case .note: "当前笔记"
        case .vault: "整个库"
        }
    }

    var icon: String {
        switch self {
        case .selection: "text.quote"
        case .note: "doc.text"
        case .vault: "books.vertical"
        }
    }
}

/// A quote of the editor's selection, as the composer offers it.
struct SelectionQuote: Equatable {
    let rel: String
    let text: String
    let line: Int
}

/// A rewrite of one passage, shown in the page until the user takes it or not.
struct InlineEdit: Equatable {
    let sessionID: UUID
    let rel: String
    /// Where the passage was; `AppModel.locateInline` finds it again after edits around it.
    var range: NSRange
    let original: String
    let label: String
    var proposed: String?
    var failed: String?

    var running: Bool { proposed == nil && failed == nil }
}

/// The quick-action bar is up over this selection in the page.
struct SelectionBar: Equatable {
    var range: NSRange
}

/// Where a task stands.
enum SessionState: Int, Comparable {
    case asking, running, reviewing, failed, done

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .asking: "等你回答"
        case .running: "进行中"
        case .reviewing: "待审阅"
        case .failed: "出错"
        case .done: "已完成"
        }
    }

    var color: Color {
        switch self {
        case .asking: .orange
        case .running: .accentColor
        case .reviewing: .purple
        case .failed: .red
        case .done: .secondary
        }
    }

    var icon: String {
        switch self {
        case .asking: "questionmark.bubble.fill"
        case .running: "circle.dotted"
        case .reviewing: "doc.badge.clock.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .done: "checkmark.circle"
        }
    }
}

/// Everything waiting on the user, in the order the pending queue lists it.
struct Waiting {
    var questions: [AgentQuestion] = []
    var reviews: [PendingReview] = []
    var feedback: [(session: AgentSession, item: UUID, rel: String)] = []

    var count: Int { questions.count + reviews.count + feedback.count }
}

extension AppModel {
    // MARK: navigation

    var place: Place { Place(doc: center, rel: activeRel) }

    /// Goes somewhere the user asked to, so ⌘[ can come back.
    func go(_ p: Place) {
        taskBar = false
        inboxOpen = false
        guard p != place else { return }
        reviewReturn = nil
        backStack.append(place)
        if backStack.count > 50 { backStack.removeFirst() }
        forwardStack = []
        apply(p)
    }

    func goBack() {
        guard let p = backStack.popLast() else { return }
        forwardStack.append(place)
        reviewReturn = nil
        apply(p)
    }

    func goForward() {
        guard let p = forwardStack.popLast() else { return }
        backStack.append(place)
        reviewReturn = nil
        apply(p)
    }

    private func apply(_ p: Place) {
        if zen, p.doc != .note { toggleZen() }
        flushSave()
        showDiff = false
        selectionBar = nil
        center = p.doc
        switch p.doc {
        case let .thread(id):
            activeSessionID = id
            if let d = sessions.first(where: { $0.id == id })?.draftRel, exists(d), d != activeRel { open(d) }
        case .note, .tasks:
            if let rel = p.rel, rel != activeRel, exists(rel) { open(rel) }
        }
    }

    private func exists(_ rel: String) -> Bool {
        guard let v = vault else { return false }
        return FileManager.default.fileExists(atPath: v.url(rel).path)
    }

    func showNote(_ rel: String?) { go(Place(doc: .note, rel: rel ?? activeRel)) }

    /// Any task opens as a conversation; from then on it has a draft to write into.
    func showThread(_ s: AgentSession) {
        s.isThread = true
        go(Place(doc: .thread(s.id), rel: s.draftRel.flatMap { exists($0) ? $0 : nil } ?? activeRel))
    }

    func showTasks() { go(Place(doc: .tasks, rel: activeRel)) }

    /// Shows a note the agent touched: beside a conversation in its panel, otherwise as the page.
    func peek(_ rel: String) {
        if centerSession != nil {
            open(rel)
            draftPanel = true
        } else {
            showNote(rel)
        }
    }

    /// The conversation in the middle, if that's what the middle shows.
    var centerSession: AgentSession? {
        if case let .thread(id) = center { return sessions.first { $0.id == id } }
        return nil
    }

    // MARK: side panel (⌘J)

    var sidePanelLabel: String {
        switch center {
        case .note: agentPanel ? "隐藏 Agent 旁注" : "显示 Agent 旁注"
        case .thread: draftPanel ? "隐藏草稿" : "显示草稿"
        case .tasks: "旁注"
        }
    }

    func toggleSidePanel() {
        if zen { toggleZen() }
        switch center {
        case .note: agentPanel.toggle()
        case .thread: draftPanel.toggle()
        case .tasks: break
        }
    }

    /// A run or a question wants to be seen. Beside a page that's the agent panel; a
    /// conversation already shows it.
    func revealAgent() {
        if zen { toggleZen() }
        if center == .note { agentPanel = true }
    }

    // MARK: follow

    /// The agent began writing `rel`. Beside a conversation the panel goes there, so the write
    /// happens in front of the user — unless they are mid-sentence in another note.
    func agentStartedWriting(_ rel: String) {
        guard followAgent, centerSession != nil, rel != activeRel, rel.lowercased().hasSuffix(".md"), !dirty,
              exists(rel) else { return }
        open(rel)
        draftPanel = true
    }

    // MARK: context shelf

    func updateSelectionPreview() {
        let ns = editorText as NSString
        let r = NSIntersectionRange(editorSelection, NSRange(location: 0, length: ns.length))
        var quote: SelectionQuote?
        if let rel = activeRel, r.length > 0 {
            let text = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { quote = SelectionQuote(rel: rel, text: text, line: EditorContext.position(r.location, in: ns).line) }
        }
        if quote != selectionPreview { selectionPreview = quote }
    }

    func pin(_ rel: String) {
        if !contextPins.contains(rel) { contextPins.append(rel) }
    }

    func unpin(_ rel: String) {
        contextPins.removeAll { $0 == rel }
    }

    /// The prompt as sent: what the user typed, then the notes they pinned and the quote they kept.
    func composedPrompt(_ prompt: String, quote: Bool? = nil) -> String {
        var extra: [String] = []
        let pins = contextPins.filter { $0 != activeRel }
        if !pins.isEmpty {
            extra.append("参考这些笔记：\n" + pins.map { "- " + $0 }.joined(separator: "\n"))
        }
        if quote ?? quoteSelection, let q = selectionPreview {
            let quoted = q.text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
            extra.append("我在 \(q.rel) 第 \(q.line) 行选中了这段：\n" + quoted)
        }
        return extra.isEmpty ? prompt : prompt + "\n\n" + extra.joined(separator: "\n\n")
    }

    // MARK: task bar (⌘L)

    func openTaskBar() {
        palette = false
        inboxOpen = false
        taskText = ""
        taskScope = selectionPreview != nil ? .selection : activeRel != nil ? .note : .vault
        taskThreadFirst = false
        taskBar = true
    }

    /// Talks a selected passage through: the task bar, scoped to the selection, opening a conversation.
    func discussSelection() {
        openTaskBar()
        taskScope = .selection
        taskThreadFirst = true
    }

    /// Starts what the task bar holds: in the background, or as a conversation in the middle.
    func startTask(asThread: Bool) {
        let text = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, vault != nil else { return }
        var prompt = text
        switch taskScope {
        case .selection:
            prompt = composedPrompt(text, quote: true)
        case .note:
            prompt = composedPrompt(text + (activeRel.map { "\n\n范围：当前笔记 \($0)。" } ?? ""), quote: false)
        case .vault:
            prompt = composedPrompt(text + "\n\n范围：整个笔记库。", quote: false)
        }
        taskBar = false
        taskText = ""
        let s = AgentSession(agent: agentPick, source: .app, title: Self.title(for: text))
        s.isThread = asThread
        sessions.append(s)
        if asThread {
            showThread(s)
            runAgent(prompt: prompt, agent: s.agent, in: s)
        } else {
            runAgent(prompt: prompt, agent: s.agent, in: s, background: true)
            showToast("已开始「\(s.title)」· 需要你时会出现在「待处理」")
        }
    }

    /// A short title from what the user asked: the first line, cut at a sentence mark.
    static func title(for prompt: String) -> String {
        let line = prompt.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? prompt
        let cut = line.split(whereSeparator: { "。，,.！？!?；;".contains($0) }).first.map(String.init) ?? line
        let t = cut.trimmingCharacters(in: .whitespaces)
        return t.count > 16 ? String(t.prefix(16)) + "…" : (t.isEmpty ? "新任务" : t)
    }

    /// A title usable as a file name.
    static func safeTitle(_ raw: String) -> String {
        let t = raw.replacingOccurrences(of: "…", with: "")
            .components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix(".") ? "草稿" : t
    }

    // MARK: conversations and drafts

    /// A new, empty conversation in the middle of the window.
    func newThread() {
        let s = AgentSession(agent: agentPick, source: .app, title: "新对话")
        s.isThread = true
        sessions.append(s)
        contextPins = []
        showThread(s)
    }

    /// What a conversation's agent is told about its draft. Names the file before it exists,
    /// so "写进草稿" works from the first turn.
    func draftContext(_ s: AgentSession) -> String {
        guard s.isThread, !s.draftDone, let v = vault else { return "" }
        if s.draftRel == nil, s.title != "新对话" { s.draftRel = v.uniqueRel(title: Self.safeTitle(s.title), folder: "") }
        guard let rel = s.draftRel else { return "" }
        return "这段对话有一篇草稿笔记 \(rel)（\(exists(rel) ? "已有内容" : "还没有创建")）。用户让你写进草稿、整理成文或更新草稿时，"
            + "直接写这个文件，不存在就创建，草稿的修改不需要审阅。除非用户要求，不要改库里的其他笔记。"
    }

    /// Creates the draft if it isn't there yet and shows it beside the conversation.
    func beginDraft(_ s: AgentSession) {
        guard let v = vault else { return }
        if s.draftRel == nil { s.draftRel = v.uniqueRel(title: Self.safeTitle(s.title == "新对话" ? "草稿" : s.title), folder: "") }
        guard let rel = s.draftRel else { return }
        if !exists(rel) {
            let title = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
            v.forceWrite(rel, "# \(title)\n\n")
            v.scan()
            emit("note.created", source: "user", ["path": .string(rel)])
        }
        open(rel)
        draftPanel = true
        requestFocus(caret: (editorText as NSString).length)
    }

    /// Appends a reply to the conversation's draft.
    func takeIntoDraft(_ text: String, _ s: AgentSession) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        if s.draftRel == nil || !exists(s.draftRel!) { beginDraft(s) } else if activeRel != s.draftRel { open(s.draftRel!) }
        guard activeRel == s.draftRel else { return }
        editorSelection = NSRange(location: 0, length: 0)
        insertIntoNote(body, quiet: true)
        draftPanel = true
        showToast("已收进草稿")
    }

    /// The draft becomes an ordinary note and opens as the page.
    func finishDraft(_ s: AgentSession) {
        guard let rel = s.draftRel, exists(rel) else { return }
        flushSave()
        s.draftDone = true
        showNote(rel)
        showToast("草稿已成为笔记 · 对话留在侧栏的任务里")
    }

    // MARK: replies into notes

    /// Puts a reply into the open note as its own block: after the paragraph holding the caret or
    /// selection, or at the end when the caret was never placed. It never splits a line.
    func insertIntoNote(_ text: String, quiet: Bool = false) {
        guard let rel = activeRel else { showToast("先打开一篇笔记"); return }
        guard !editorReadOnly else { showToast("Agent 正在写入这篇笔记，稍后再插入"); return }
        guard pending[rel] == nil else { showToast("这篇笔记有待审阅的改动，先处理审阅"); return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let ns = editorText as NSString
        var at = ns.length
        if editorSelection.location > 0 || editorSelection.length > 0 {
            // The last character of a selection, or the caret itself, picks the paragraph.
            let end = min(NSMaxRange(editorSelection), ns.length)
            let probe = editorSelection.length > 0 ? max(end - 1, 0) : end
            at = NSMaxRange(ns.paragraphRange(for: NSRange(location: min(probe, ns.length), length: 0)))
        }
        let before = ns.substring(to: at), after = ns.substring(from: at)
        let lead = before.isEmpty ? "" : before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        let trail = after.isEmpty || after.hasPrefix("\n") ? "\n" : "\n\n"
        editorText = ns.replacingCharacters(in: NSRange(location: at, length: 0), with: lead + body + trail)
        dirty = true
        editorVersion += 1
        scheduleSave()
        requestFocus(caret: at + ((lead + body) as NSString).length)
        if !quiet { showToast("已插入到 " + (activeNote?.displayName ?? rel)) }
    }

    /// Keeps a reply as a note of its own, titled by its first heading or by the task.
    func saveAsNote(_ text: String, session: AgentSession?) {
        guard let v = vault else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        flushSave()
        let first = body.components(separatedBy: "\n").first ?? ""
        let headed = first.hasPrefix("# ")
        var title = Self.safeTitle(headed ? String(first.dropFirst(2)) : (session?.title ?? "Agent 笔记"))
        if title == "新对话" || title == "新会话" { title = "Agent 笔记" }
        let content = headed ? body + "\n" : "# \(title)\n\n" + body + "\n"
        let rel = v.create(title: title, content: content)
        emit("note.created", source: "user", ["path": .string(rel)])
        showNote(rel)
        showToast("已存为 " + (rel as NSString).lastPathComponent)
    }

    // MARK: pending queue (⇧⌘R)

    var waiting: Waiting {
        var w = Waiting()
        w.questions = questions.values.filter { $0.answer == nil && !$0.expired }.sorted { $0.id.uuidString < $1.id.uuidString }
        w.reviews = pending.values.sorted { $0.rel < $1.rel }
        for s in sessions {
            for item in s.items {
                if case let .feedback(rel, _, false) = item.kind { w.feedback.append((s, item.id, rel)) }
            }
        }
        return w
    }

    /// Opens pending changes one note after another; when none are left, goes back to where the
    /// user was before the first.
    func startReviewFlow(at rel: String? = nil) {
        guard let first = rel ?? pending.keys.sorted().first else { showToast("没有待审阅的改动"); return }
        if reviewReturn == nil { reviewReturn = place }
        inboxOpen = false
        taskBar = false
        openReview(first)
    }

    private func openReview(_ rel: String) {
        if zen { toggleZen() }
        center = .note
        let sid = pending[rel]?.sessionID ?? sessions.last(where: { touched($0).contains(rel) })?.id
        if let sid { activeSessionID = sid }
        agentPanel = true
        open(rel)
        showDiff = true
    }

    func advanceReview() {
        if let next = pending.keys.sorted().first { openReview(next) } else { endReviewFlow(done: true) }
    }

    /// Leaves the flow and goes back; `done` when the queue ran empty rather than "later".
    func endReviewFlow(done: Bool) {
        showDiff = false
        guard let back = reviewReturn else { return }
        reviewReturn = nil
        apply(back)
        showToast(done ? "改动都审阅完了，回到刚才的位置" : "稍后再审阅 · 还有 \(pending.count) 篇")
    }

    /// "2 / 3" in the review toolbar.
    var reviewProgress: (index: Int, total: Int)? {
        guard reviewReturn != nil, let rel = activeRel else { return nil }
        let keys = pending.keys.sorted()
        guard let i = keys.firstIndex(of: rel) else { return nil }
        return (i + 1, keys.count)
    }

    /// Opens one note's changes in the review flow.
    func review(_ rel: String) { startReviewFlow(at: rel) }

    /// Accepts every change to `rel` without opening it.
    func acceptAll(_ rel: String) { finishReview(all: nil, rel: rel) }

    // MARK: tasks handed out from the page

    /// Hands one open task to an agent in the background. The agent ticks it off when done.
    func delegateTask(rel: String, line: Int, text: String) {
        let key = "\(rel):\(line)"
        let s = AgentSession(agent: agentPick, source: .app, title: Self.title(for: text))
        sessions.append(s)
        delegatedTasks[key] = s.id
        runAgent(prompt: "完成 \(rel) 第 \(line) 行的待办：「\(text)」。做完后把它勾选为已完成；需要我决定的地方先问我。",
                 agent: s.agent, in: s, background: true)
        showToast("已交给 \(s.agent.displayName) · 完成后出现在「待处理」")
    }

    /// The session working on the open note's task at `line`, while it runs.
    func delegation(rel: String, line: Int) -> AgentSession? {
        guard let id = delegatedTasks["\(rel):\(line)"] else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: inline rewrites

    static let inlineContext = "你在帮用户改写笔记里的一段文字。只输出改好之后的文字本身：不要任何解释，不要加引号、标题或代码块，"
        + "不要读取或修改任何文件。保持原文的语言和 Markdown 格式。"

    static let inlineActions: [(label: String, icon: String, instruction: String)] = [
        ("精简", "arrow.down.right.and.arrow.up.left", "把这段文字精简：保留全部信息，去掉重复和空话"),
        ("扩写", "arrow.up.left.and.arrow.down.right", "把这段文字扩写得更充分：补上论证、例子或细节，不要编造事实"),
        ("改写", "wand.and.stars", "把这段文字改写得更清楚、更顺"),
        ("列要点", "list.bullet", "把这段文字整理成 Markdown 要点列表"),
    ]

    /// Rewrites the selected passage; the result shows up in place.
    func startInline(label: String, instruction: String) {
        guard let rel = activeRel, !editorReadOnly, pending[rel] == nil else { return }
        let ns = editorText as NSString
        let r = NSIntersectionRange(editorSelection, NSRange(location: 0, length: ns.length))
        let original = ns.substring(with: r)
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        rejectInline()
        let s = AgentSession(agent: agentPick, source: .app, title: label + "：" + Self.title(for: original))
        s.inline = true
        sessions.append(s)
        selectionBar = nil
        inline = InlineEdit(sessionID: s.id, rel: rel, range: r, original: original, label: label)
        let line = EditorContext.position(r.location, in: ns).line
        if !launch(s, prompt: "\(instruction)。\n\n原文（\(rel) 第 \(line) 行）：\n\(original)") {
            inline = nil
        }
    }

    func retryInline() {
        guard var ie = inline, let s = sessions.first(where: { $0.id == ie.sessionID }), !s.running else { return }
        ie.proposed = nil
        ie.failed = nil
        inline = ie
        if !launch(s, prompt: "再换一种写法。同样只输出改好之后的文字本身。") { inline = nil }
    }

    /// Hands the rewrite to the editor, which applies it as one undoable edit.
    func acceptInline() {
        guard let ie = inline, ie.proposed != nil else { return }
        guard ie.rel == activeRel else { inline = nil; return }
        NotificationCenter.default.post(name: .twainApplyInline, object: nil)
    }

    func rejectInline() {
        guard let ie = inline else { return }
        if let s = sessions.first(where: { $0.id == ie.sessionID }), s.running { stopAgent(s) }
        inline = nil
    }

    /// Opens the rewrite's conversation beside the page, to ask for something more specific.
    func discussInline() {
        guard let ie = inline else { return }
        activeSessionID = ie.sessionID
        agentPanel = true
    }

    /// Where the passage is now: where it was if unchanged, else its nearest occurrence.
    func locateInline(in text: String) -> NSRange? {
        guard let ie = inline, ie.rel == activeRel else { return nil }
        let ns = text as NSString
        if NSMaxRange(ie.range) <= ns.length, ns.substring(with: ie.range) == ie.original { return ie.range }
        var best: NSRange?
        var search = NSRange(location: 0, length: ns.length)
        while true {
            let r = ns.range(of: ie.original, options: [], range: search)
            if r.location == NSNotFound { break }
            if best == nil || abs(r.location - ie.range.location) < abs(best!.location - ie.range.location) { best = r }
            search = NSRange(location: NSMaxRange(r), length: ns.length - NSMaxRange(r))
        }
        return best
    }

    private func inlineFinished(_ s: AgentSession) {
        guard var ie = inline, ie.sessionID == s.id else { return }
        if let reply = Self.lastReply(s) {
            ie.proposed = Self.cleanRewrite(reply)
        } else {
            let err = s.items.last.flatMap { if case let .error(t) = $0.kind { return t } else { return nil } }
            ie.failed = err ?? "\(s.agent.displayName) 没有给出结果"
        }
        inline = ie
    }

    /// The agent's last reply of the latest turn.
    static func lastReply(_ s: AgentSession) -> String? {
        for item in s.items.reversed() {
            switch item.kind {
            case let .agent(t): return t
            case .user: return nil
            default: continue
            }
        }
        return nil
    }

    /// Strips what models wrap a bare rewrite in anyway: code fences and quote marks.
    static func cleanRewrite(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            var lines = t.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.hasPrefix("```") == true { lines.removeLast() }
            t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("「", "」"), ("“", "”"), ("\"", "\"")] where t.hasPrefix(open) && t.hasSuffix(close) && t.count > 2 {
            let inner = String(t.dropFirst().dropLast())
            if !inner.contains(open) { t = inner }
        }
        return t
    }

    // MARK: run lifecycle

    /// After every run: inline rewrites get their result; background tasks say they're done.
    func runFinished(_ s: AgentSession) {
        if s.inline {
            inlineFinished(s)
            return
        }
        let visible = centerSession === s || (center == .note && agentPanel && activeSession === s)
        if !visible, state(of: s) == .done, touched(s).isEmpty {
            showToast("「\(s.title)」已完成")
        }
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    // MARK: sessions

    /// Notes the session changed, in the order it changed them.
    func touched(_ s: AgentSession) -> [String] {
        var seen = Set<String>()
        return s.items.compactMap {
            if case let .change(rel, _, _) = $0.kind, seen.insert(rel).inserted { return rel }
            return nil
        }
    }

    func openQuestions(_ s: AgentSession) -> [AgentQuestion] {
        questions.values.filter { $0.sessionID == s.id && $0.answer == nil && !$0.expired }
    }

    func state(of s: AgentSession) -> SessionState {
        if !openQuestions(s).isEmpty { return .asking }
        if s.running { return .running }
        if touched(s).contains(where: { pending[$0] != nil }) { return .reviewing }
        if case .error = s.items.last?.kind { return .failed }
        return .done
    }

    /// Tasks worth listing: ones that did or are doing something. Finished rewrites of a
    /// passage live on in the page, not in the list.
    var listedSessions: [AgentSession] {
        sessions.filter { s in
            (!s.items.isEmpty || s.running || s.isThread) && !(s.inline && !s.running && inline?.sessionID != s.id)
        }
        .sorted { a, b in
            let sa = state(of: a), sb = state(of: b)
            return sa != sb ? sa < sb : a.started > b.started
        }
    }

    /// One line of what the session last said or did.
    func lastLine(_ s: AgentSession) -> String? {
        for item in s.items.reversed() {
            switch item.kind {
            case let .agent(t), let .step(_, t, _), let .error(t):
                if let line = t.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    return line.trimmingCharacters(in: CharacterSet(charactersIn: "#> ").union(.whitespaces))
                }
            case let .user(t):
                return t.components(separatedBy: "\n").first
            default: continue
            }
        }
        return nil
    }
}

extension Notification.Name {
    static let twainApplyInline = Notification.Name("twainApplyInline")
}
