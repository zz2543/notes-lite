import AppKit
import TwainCore

/// A question an agent put to the user through `ask_user`.
struct AgentQuestion: Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    let agent: AgentKind
    let question: String
    let options: [String]
    let allowText: Bool
    var answer: String?
    var expired = false
}

extension AppModel {
    var proposalStore: ProposalStore? { vault.map { ProposalStore(vault: $0.root) } }

    // MARK: proposals

    /// `propose`: turns an agent's suggested content into a review. The file is left alone until
    /// the user accepts hunks; with `wait`, the agent hears back only then.
    func propose(_ call: CommandCall, reply: @escaping AppCommand.Reply) {
        do {
            guard let v = vault, let index else { throw RPCError(RPCError.noVault, "共笔没有打开任何库") }
            flushSave()
            index.refresh()
            let ref = call.params["note"]?.string ?? ""
            let rel = try index.resolve(ref) ?? Self.newNotePath(ref)
            if let existing = pending[rel] {
                throw RPCError(1006, "\(rel) 还有 \(existing.hunks.count) 处改动等用户审阅，等用户处理完再提交",
                               data: ["pendingProposal": JSONValue(existing.proposalID)])
            }
            let disk = v.diskContent(rel)
            let isNew = disk == nil
            let before = disk ?? ""
            let content = call.params["content"]?.string
            let edits = call.params["edits"]
            guard (content == nil) != (edits == nil || edits!.isNull) else {
                throw RPCError(RPCError.invalidParams, "content 和 edits 需要且只能给一个")
            }
            var after: String
            var anchors: [(ClosedRange<Int>, String)] = []
            if let content {
                after = content
            } else {
                guard !isNew else { throw RPCError(RPCError.invalidParams, "\(rel) 还不存在，新建笔记请用 content 给出全文") }
                (after, anchors) = try ProposalBuilder.apply(try ProposalBuilder.edits(edits!), to: before)
            }
            // Keep the file's trailing newline convention, so it doesn't show up as a change.
            if !isNew, before.hasSuffix("\n"), !after.hasSuffix("\n") { after += "\n" }
            let lineNotes: [(Int, String)] = (call.params["notes"]?.array ?? []).compactMap { n in
                guard let line = n["line"]?.int, let text = n["text"]?.string, !text.isEmpty else { return nil }
                return (line, text)
            }
            let s = call.session
            var p = Proposal(path: rel, agent: s?.agent.rawValue, session: s?.id.uuidString, automation: s?.automationID,
                             reason: call.params["reason"]?.string.flatMap { $0.isEmpty ? nil : $0 },
                             baseline: isNew ? [] : Markdown.lines(before), proposed: Markdown.lines(after), isNew: isNew)
            guard !p.hunks.isEmpty else {
                reply(.success(["path": .string(rel), "status": "unchanged"]))
                return
            }
            p.notes = ProposalBuilder.notes(hunks: p.hunks, anchors: anchors, lineNotes: lineNotes)
            proposalStore?.save(p)
            let counts = p.hunks.map { LineDiff.counts($0, base: p.baseline) }
            s?.items.append(SessionItem(kind: .change(rel: rel, plus: counts.reduce(0) { $0 + $1.plus },
                                                      minus: counts.reduce(0) { $0 + $1.minus })))
            emit("proposal.created", source: s.map(eventSource) ?? "external",
                 ["path": .string(rel), "proposal": .string(p.id), "hunks": JSONValue(p.hunks.count)])

            if reviewMode == .auto, s?.source != .automation {
                // The user chose to take agents' changes as they come.
                p.resolve(p.hunks.map { var h = $0; h.state = .accepted; return h }, feedback: [])
                v.forceWrite(rel, after)
                proposalStore?.save(p)
                if rel == activeRel { reloadEditor() }
                showToast("\(s?.agent.displayName ?? "Agent") 已写入 \((rel as NSString).lastPathComponent)")
                reply(.success(p.resultJSON))
                return
            }
            pending[rel] = review(from: p, session: s)
            let who = s?.agent.displayName ?? "Agent"
            showToast("\(who) 提议\(isNew ? "新建" : "修改") \((rel as NSString).lastPathComponent) · \(p.hunks.count) 处待审阅")
            if call.params["wait"]?.bool == true {
                proposalWaiters[p.id, default: []].append(reply)
            } else {
                reply(.success(["id": .string(p.id), "path": .string(rel), "status": "pending", "hunks": JSONValue(p.hunks.count)]))
            }
        } catch let e as RPCError {
            reply(.failure(e))
        } catch {
            reply(.failure(RPCError(RPCError.internalError, error.localizedDescription)))
        }
    }

    /// Where a proposal for a note that doesn't exist yet goes. Refuses paths outside the vault.
    static func newNotePath(_ ref: String) throws -> String {
        var rel = ref.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = rel.split(separator: "/")
        guard !rel.isEmpty, !parts.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else {
            throw RPCError(RPCError.invalidParams, "笔记路径不合法：\(ref)")
        }
        if !rel.lowercased().hasSuffix(".md") { rel += ".md" }
        return rel
    }

    func review(from p: Proposal, session: AgentSession?) -> PendingReview {
        PendingReview(rel: p.path, by: p.agent.flatMap(AgentKind.init(rawValue:)), source: session?.source ?? .terminal,
                      baseline: p.baseline, proposed: p.proposed, hunks: p.hunks, snapshot: nil, proposalID: p.id,
                      reason: p.reason, notes: p.notes, feedback: p.feedback, sessionID: session?.id, isNew: p.isNew)
    }

    /// Proposals still waiting from an earlier launch come back into the review queue.
    func loadProposals() {
        guard let v = vault, let store = proposalStore else { return }
        for var p in store.all() where p.status == .pending {
            let disk = v.diskContent(p.path)
            guard p.isNew ? disk == nil : disk.map(Markdown.lines) == p.baseline else {
                p.status = .stale
                p.resolvedAt = Date()
                store.save(p)
                continue
            }
            if pending[p.path] == nil { pending[p.path] = review(from: p, session: nil) }
        }
    }

    /// A proposal whose note changed underneath it: drop it and tell whoever waits.
    func markStale(_ r: PendingReview) {
        guard let id = r.proposalID, var p = proposalStore?.load(id) else { return }
        p.status = .stale
        p.resolvedAt = Date()
        proposalStore?.save(p)
        if pending[r.rel]?.proposalID == id { pending[r.rel] = nil }
        answerWaiters(p)
    }

    func answerWaiters(_ p: Proposal) {
        for w in proposalWaiters.removeValue(forKey: p.id) ?? [] { w(.success(p.resultJSON)) }
    }

    func setFeedback(_ i: Int, _ text: String) {
        guard let rel = activeRel, var p = pending[rel], p.hunks.indices.contains(i) else { return }
        if p.feedback.count < p.hunks.count { p.feedback += Array(repeating: nil, count: p.hunks.count - p.feedback.count) }
        p.feedback[i] = text.isEmpty ? nil : text
        pending[rel] = p
    }

    /// `all`: accept or reject everything; nil accepts whatever is still undecided.
    func finishReview(all: HunkState?) {
        guard let v = vault, let rel = activeRel, let r = pending[rel] else { return }
        let hunks = r.hunks.map { h -> Hunk in
            var h = h
            if let all { h.state = all } else if h.state == .pending { h.state = .accepted }
            return h
        }
        let accepted = hunks.filter { $0.state == .accepted }.count
        let name = (rel as NSString).lastPathComponent

        if r.isProposal {
            // Only apply onto the text the proposal was made against.
            let disk = v.diskContent(rel)
            guard r.isNew ? disk == nil : disk.map(Markdown.lines) == r.baseline else {
                markStale(r)
                showDiff = false
                showToast("\(name) 在提案之后被改过，这份提案已作废")
                return
            }
        }
        let result = LineDiff.apply(hunks, to: r.baseline).joined(separator: "\n")
        if !(r.isNew && accepted == 0) { v.forceWrite(rel, result) }
        pending[rel] = nil
        showDiff = false
        if r.isNew, accepted > 0 { v.scan(); emit("note.created", source: "user", ["path": .string(rel)]) }
        if activeRel == rel { reloadEditor() }

        // Keep the outcome: agents learn from it (`twain reviews`) and waiters get their answer.
        var record = r.proposalID.flatMap { proposalStore?.load($0) }
            ?? Proposal(path: rel, agent: r.by?.rawValue, session: r.sessionID?.uuidString, baseline: r.baseline,
                        proposed: r.proposed, notes: r.notes)
        if record.hunks.count != hunks.count { record.hunks = r.hunks }
        record.resolve(hunks, feedback: r.feedback)
        if r.by != nil || r.isProposal { proposalStore?.save(record) }
        answerWaiters(record)
        emit("review.resolved", source: "user", ["path": .string(rel), "status": .string(record.status.rawValue),
                                                 "accepted": JSONValue(accepted), "rejected": JSONValue(hunks.count - accepted),
                                                 "proposal": JSONValue(r.proposalID)])

        if let sid = r.sessionID, let s = sessions.first(where: { $0.id == sid }), s.source != .terminal,
           let message = record.feedbackMessage() {
            s.items.append(SessionItem(kind: .feedback(rel: rel, message: message, sent: false)))
        }
        if r.isNew, accepted == 0 {
            showToast("没有新建 \(name)")
        } else if accepted > 0 {
            showToast("已写入 \(name) · 接受 \(accepted) 处" + (r.snapshot.map { " · 快照 " + $0 } ?? ""))
        } else {
            showToast(r.isProposal ? "已拒绝全部提议，\(name) 没有改动" : "已还原到 agent 写入前的版本")
        }
    }

    /// Shows the file as it is on disk now, e.g. after a review wrote it.
    func reloadEditor() {
        guard let v = vault, let rel = activeRel else { return }
        editorText = v.read(rel)
        dirty = false
        editorVersion += 1
    }

    /// Sends a review's outcome back to the session that made the change, as its next turn.
    func sendFeedback(_ itemID: UUID, in s: AgentSession) {
        guard let i = s.items.firstIndex(where: { $0.id == itemID }), case let .feedback(rel, message, false) = s.items[i].kind else { return }
        guard !s.running else { showToast("\(s.agent.displayName) 还在运行，等它结束再发送"); return }
        s.items[i].kind = .feedback(rel: rel, message: message, sent: true)
        if s.source == .automation {
            launch(s, prompt: message)
        } else {
            runAgent(prompt: message, agent: s.agent, in: s)
        }
    }

    // MARK: questions

    /// `ask`: shows the question in the asking session and answers when the user does,
    /// or with `answered: false` when time runs out or the agent goes away.
    func ask(_ call: CommandCall, reply: @escaping AppCommand.Reply) {
        let text = call.params["question"]?.string ?? ""
        let options = (call.params["options"]?.array ?? []).compactMap(\.string).filter { !$0.isEmpty }
        let s = call.session ?? activeSession ?? {
            let n = AgentSession(agent: agentPick, source: .terminal, title: "外部 agent")
            sessions.append(n)
            return n
        }()
        let q = AgentQuestion(id: UUID(), sessionID: s.id, agent: s.agent, question: text, options: options,
                              allowText: options.isEmpty || call.params["text"]?.bool == true)
        questions[q.id] = q
        questionReplies[q.id] = reply
        s.items.append(SessionItem(kind: .question(q.id)))
        activeSessionID = s.id
        if zen { toggleZen() }
        agentPanel = true
        showToast("\(s.agent.displayName) 有一个问题等你回答")
        NSApp.requestUserAttention(.informationalRequest)

        let timeout = TimeInterval(max(5, call.params["timeout"]?.int ?? 600))
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.expire(q.id, why: "timeout") }
        call.connection?.onClose { [weak self] in self?.expire(q.id, why: "gone") }
    }

    func answer(_ id: UUID, _ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var q = questions[id], q.answer == nil, !q.expired else { return }
        q.answer = text
        questions[id] = q
        questionReplies.removeValue(forKey: id)?(.success(["answered": true, "answer": .string(text)]))
    }

    private func expire(_ id: UUID, why: String) {
        guard var q = questions[id], q.answer == nil, !q.expired else { return }
        q.expired = true
        questions[id] = q
        questionReplies.removeValue(forKey: id)?(.success(["answered": false, "reason": .string(why)]))
    }
}
