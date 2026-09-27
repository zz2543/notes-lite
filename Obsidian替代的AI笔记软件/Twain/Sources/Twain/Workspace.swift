import TwainCore
import SwiftUI

/// What holds the middle of the window.
///
/// - write: the page leads; the agent waits in the inspector.
/// - agent: the conversation leads; the page it works on sits beside it and follows its writes.
/// - desk: no single page or conversation — every run, question, review and open task at once.
enum Workspace: String, CaseIterable, Identifiable {
    case write, agent, desk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .write: "写作"
        case .agent: "Agent"
        case .desk: "工作台"
        }
    }

    var icon: String {
        switch self {
        case .write: "doc.text"
        case .agent: "bubble.left.and.text.bubble.right"
        case .desk: "square.grid.2x2"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .write: "1"
        case .agent: "2"
        case .desk: "3"
        }
    }

    var hint: String { "⌘" + String(key.character) }
}

/// A quote of the editor's selection, as the composer offers it.
struct SelectionQuote: Equatable {
    let rel: String
    let text: String
    let line: Int
}

/// Where a session stands, from the desk's point of view.
enum SessionState {
    case asking, running, reviewing, failed, done

    var label: String {
        switch self {
        case .asking: "等你回答"
        case .running: "运行中"
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
}

/// The three-way switch in the middle of the toolbar.
struct WorkspacePicker: View {
    @Bindable var model: AppModel

    var body: some View {
        Picker("工作区", selection: Binding(get: { model.workspace }, set: { model.setWorkspace($0) })) {
            ForEach(Workspace.allCases) { w in
                Label(w.title, systemImage: w.icon).tag(w)
                    .help("\(w.title) \(w.hint)")
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .labelsHidden()
        .fixedSize()
    }
}

// MARK: - Model

extension AppModel {
    func setWorkspace(_ w: Workspace) {
        palette = false
        if zen { toggleZen() }
        guard w != workspace else { return }
        flushSave()
        withAnimation(.snappy(duration: 0.25)) { workspace = w }
    }

    /// A run or a question wants to be seen. The desk already lists both, so it stays put.
    func revealAgent() {
        if zen { toggleZen() }
        if workspace == .write { agentPanel = true }
    }

    /// A note was opened on purpose; in the agent workspace that means showing the page panel.
    func revealNote() {
        if workspace == .agent { notePanel = true }
    }

    /// Opens a note's pending changes. From the desk this moves to the agent workspace, so the
    /// review sits beside the conversation that produced it.
    func review(_ rel: String) {
        if zen { toggleZen() }
        if workspace == .desk { setWorkspace(.agent) }
        if let s = sessions.first(where: { touched($0).contains(rel) }) { activeSessionID = s.id }
        open(rel)
        showDiff = true
        revealNote()
    }

    // MARK: side panel (⌘J)

    var sidePanelShown: Bool {
        switch workspace {
        case .write: agentPanel
        case .agent: notePanel
        case .desk: false
        }
    }

    var sidePanelLabel: String {
        switch workspace {
        case .write: agentPanel ? "隐藏 Agent 面板" : "显示 Agent 面板"
        case .agent: notePanel ? "隐藏笔记面板" : "显示笔记面板"
        case .desk: "Agent 面板"
        }
    }

    func toggleSidePanel() {
        if zen { toggleZen() }
        switch workspace {
        case .write: agentPanel.toggle()
        case .agent: notePanel.toggle()
        case .desk: break
        }
    }

    // MARK: follow

    /// The agent began writing `rel`. In the agent workspace the page panel goes there, so the
    /// write happens in front of the user — unless they are mid-sentence on another note.
    func agentStartedWriting(_ rel: String) {
        guard followAgent, workspace == .agent, rel != activeRel, rel.lowercased().hasSuffix(".md"), !dirty,
              let v = vault, FileManager.default.fileExists(atPath: v.url(rel).path) else { return }
        open(rel)
        notePanel = true
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
    func composedPrompt(_ prompt: String) -> String {
        var extra: [String] = []
        let pins = contextPins.filter { $0 != activeRel }
        if !pins.isEmpty {
            extra.append("参考这些笔记：\n" + pins.map { "- " + $0 }.joined(separator: "\n"))
        }
        if quoteSelection, let q = selectionPreview {
            let quoted = q.text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
            extra.append("我在 \(q.rel) 第 \(q.line) 行选中了这段：\n" + quoted)
        }
        return extra.isEmpty ? prompt : prompt + "\n\n" + extra.joined(separator: "\n\n")
    }

    // MARK: replies into notes

    /// Puts a reply into the open note as its own block: after the paragraph holding the caret or
    /// selection, or at the end when the caret was never placed. It never splits a line.
    func insertIntoNote(_ text: String) {
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
        revealNote()
        showToast("已插入到 " + (activeNote?.displayName ?? rel))
    }

    /// Keeps a reply as a note of its own, titled by its first heading or by the session.
    func saveAsNote(_ text: String, session: AgentSession?) {
        guard let v = vault else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        flushSave()
        let first = body.components(separatedBy: "\n").first ?? ""
        let headed = first.hasPrefix("# ")
        let raw = headed ? String(first.dropFirst(2)) : (session?.title ?? "Agent 笔记")
        var title = raw.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if title.isEmpty || title == "新会话" { title = "Agent 笔记" }
        let content = headed ? body + "\n" : "# \(title)\n\n" + body + "\n"
        let rel = v.create(title: title, content: content)
        emit("note.created", source: "user", ["path": .string(rel)])
        open(rel)
        revealNote()
        showToast("已存为 " + (rel as NSString).lastPathComponent)
    }

    // MARK: desk

    /// Starts `prompt` in a fresh session without leaving the current workspace.
    func dispatch(_ prompt: String, agent: AgentKind) {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, vault != nil else { return }
        let s = AgentSession(agent: agent, source: .app, title: String(p.prefix(14)))
        sessions.append(s)
        runAgent(prompt: p, agent: agent, in: s)
    }

    /// Hands one open task to an agent, in its own session.
    func delegate(_ t: VaultIndex.TaskHit, agent: AgentKind) {
        dispatch("完成 \(t.rel) 第 \(t.task.line) 行的待办：「\(t.task.text)」。做完后把它勾选为已完成；需要我决定的地方先用 ask_user 问我。",
                 agent: agent)
        showToast("已交给 \(agent.displayName) · 在工作台跟进")
    }

    /// Accepts every change to `rel` without opening the review.
    func acceptAll(_ rel: String) {
        open(rel)
        finishReview(all: nil)
    }

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
