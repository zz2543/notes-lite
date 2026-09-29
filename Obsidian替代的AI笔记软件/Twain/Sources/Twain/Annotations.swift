import AppKit
import SwiftUI
import TwainCore

/// AI review: an agent reads the note and leaves annotations beside the passages they concern.
/// Nothing is written into the note; each annotation is one small decision — accept the
/// suggested wording, dismiss it, or answer it — instead of one long rewrite to untangle.
extension AppModel {
    var annotationStore: AnnotationStore? { vault.map { AnnotationStore(vault: $0.root) } }

    /// Open annotations of the open note, in reading order.
    var visibleAnnotations: [Annotation] {
        editor.annotations.filter { $0.status == .open }
    }

    func loadAnnotations() {
        guard let rel = editor.activeRel, let store = annotationStore else { editor.annotations = []; return }
        let loaded = store.load(rel)
        if loaded != editor.annotations { editor.annotations = loaded }
    }

    private func saveAnnotations() {
        guard let rel = editor.activeRel else { return }
        annotationStore?.save(rel, editor.annotations)
    }

    /// Starts an AI review of the open note with the agent picked in the panel.
    func startAIReview(model: String? = nil) {
        guard let rel = editor.activeRel, vault != nil else { return }
        flushSave()
        let agent = agents.agentPick
        let s = AgentSession(agent: agent, source: .app, title: "AI 审阅 · " + NoteRef(rel: rel).title)
        s.extraTools = ["annotate"]
        s.readOnly = true
        agents.sessions.append(s)
        agents.activeSessionID = s.id
        let prompt = """
        请审阅笔记 \(rel)。先用 read_note 读全文，再用 annotate 工具在具体位置留下 3 到 8 条批注，每条对准一句或半句原文：
        - question：指出含糊、跳跃、自相矛盾的地方，用提问的方式引导我想清楚；
        - suggestion：给出具体的改写，放在 replacement 里，只替换 quote 那一小段；
        - fact：需要核实的事实、数据、引用；
        - structure：段落顺序、层级、缺失的部分；
        - praise：确实写得好的地方（最多一条）。
        不要修改文件，不要用 propose_edit。批注要短、具体、可执行，按在文中出现的顺序给出。最后用一两句话总结整体印象。
        """
        runAgent(prompt: prompt, agent: agent, model: model, in: s)
    }

    // MARK: user actions

    /// Puts the suggested wording in place of the quote (undoable in the editor) and closes the annotation.
    func acceptAnnotation(_ id: String) {
        guard let i = editor.annotations.firstIndex(where: { $0.id == id }) else { return }
        let a = editor.annotations[i]
        if let replacement = a.replacement {
            guard let r = Anchor.locate(a.quote, in: editor.editorText, line: a.line) else {
                showToast("原文已经改过，找不到“\(a.quote.prefix(12))…”")
                return
            }
            applyEditorEdit?(r, replacement)
        }
        editor.annotations[i].status = .accepted
        saveAnnotations()
        emit("annotation.resolved", source: "user", ["path": JSONValue(editor.activeRel), "id": .string(id), "status": "accepted"])
    }

    func dismissAnnotation(_ id: String) {
        guard let i = editor.annotations.firstIndex(where: { $0.id == id }) else { return }
        editor.annotations[i].status = .dismissed
        saveAnnotations()
        emit("annotation.resolved", source: "user", ["path": JSONValue(editor.activeRel), "id": .string(id), "status": "dismissed"])
    }

    func dismissAllAnnotations() {
        for i in editor.annotations.indices where editor.annotations[i].status == .open { editor.annotations[i].status = .dismissed }
        saveAnnotations()
    }

    /// The user answers an annotation; the agent that wrote it continues the same session to reply.
    func replyToAnnotation(_ id: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = editor.annotations.firstIndex(where: { $0.id == id }), let rel = editor.activeRel else { return }
        editor.annotations[i].replies.append(.init(from: "user", text: t))
        saveAnnotations()
        let a = editor.annotations[i]
        guard let sid = a.session, let s = agents.sessions.first(where: { $0.id.uuidString == sid }) else {
            showToast("写下这条批注的会话已经不在了，回复已保存")
            return
        }
        let prompt = """
        我在你对 \(rel) 的批注 \(a.id)（原文“\(a.quote)”）下回复：\(t)
        请用 annotate 的 reply_to=\(a.id) 回复我；如果要调整建议的改写，同时给出新的 replacement。
        """
        runAgent(prompt: prompt, agent: s.agent, in: s)
    }

    // MARK: agent commands

    func annotateCommand(_ call: CommandCall, index: VaultIndex, vault v: Vault) throws -> JSONValue {
        let rel = try VaultQueries.note(call.params, index: index, current: editor.activeRel)
        let store = AnnotationStore(vault: v.root)
        let s = call.session
        if let target = call.params["reply_to"]?.string {
            guard let text = call.params["text"]?.string, !text.isEmpty else { throw RPCError(RPCError.invalidParams, "回复需要 text") }
            var list = store.load(rel)
            guard let i = list.firstIndex(where: { $0.id == target }) else { throw RPCError(RPCError.notFound, "\(rel) 上没有批注 \(target)") }
            list[i].replies.append(.init(from: s?.agent.displayName ?? "agent", text: text))
            if let r = call.params["replacement"]?.string { list[i].replacement = r }
            list[i].status = .open
            store.save(rel, list)
            if rel == editor.activeRel { editor.annotations = list }
            return ["note": .string(rel), "replied": .string(target)]
        }
        guard let items = call.params["items"]?.array, !items.isEmpty else {
            throw RPCError(RPCError.invalidParams, "需要 items（新批注）或 reply_to + text（回复）")
        }
        let text = rel == editor.activeRel ? editor.editorText : (v.diskContent(rel) ?? "")
        let (added, missing) = try store.add(rel, text: text, items: items, agent: s?.agent.displayName, session: s?.id.uuidString)
        if rel == editor.activeRel { loadAnnotations() }
        if !added.isEmpty {
            s?.items.append(SessionItem(kind: .step(id: UUID().uuidString, text: "批注 \(added.count) 处 · \((rel as NSString).lastPathComponent)", running: false)))
            emit("annotation.created", source: s.map(eventSource) ?? "external", ["path": .string(rel), "count": JSONValue(added.count)])
            if rel != editor.activeRel { showToast("\(s?.agent.displayName ?? "Agent") 在 \((rel as NSString).lastPathComponent) 留下 \(added.count) 条批注") }
        }
        return ["note": .string(rel), "added": JSONValue(added.count), "ids": JSONValue(added.map(\.id)),
                "missing": JSONValue(missing)]
    }

    func annotationsCommand(_ call: CommandCall, index: VaultIndex, vault v: Vault) throws -> JSONValue {
        let rel = try VaultQueries.note(call.params, index: index, current: editor.activeRel)
        let all = call.params["all"]?.bool == true
        let list = AnnotationStore(vault: v.root).load(rel).filter { all || $0.status == .open }
        return ["note": .string(rel), "annotations": .array(list.map(\.json))]
    }
}

// MARK: - Rail

/// Annotation cards beside the text, each level with its passage. Lives inside the text view so
/// the cards scroll with the page for free; repositioned only when layout changes.
@MainActor
final class AnnotationRail {
    static let width: CGFloat = 300
    private var hosts: [String: NSHostingView<AnyView>] = [:]

    /// Lays the cards out next to their anchors, pushing each below the one above when they'd overlap.
    func layout(in tv: TwainTextView, model: AppModel, anchors: [String: NSRange], selected: String?) {
        let list = model.visibleAnnotations
        let ids = Set(list.map(\.id))
        for (id, h) in hosts where !ids.contains(id) { h.removeFromSuperview(); hosts[id] = nil }
        guard !list.isEmpty, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let x = tv.bounds.width - Self.width + 4
        let w = Self.width - 24
        var nextY: CGFloat = 0
        let sorted = list.sorted { (anchors[$0.id]?.location ?? .max) < (anchors[$1.id]?.location ?? .max) }
        for a in sorted {
            var y = nextY
            if let r = anchors[a.id] {
                let gr = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                lm.ensureLayout(forGlyphRange: gr)
                y = lm.boundingRect(forGlyphRange: gr, in: tc).minY + tv.textContainerOrigin.y - 4
            }
            y = max(y, nextY)
            // A fixed width lets the text wrap before the height is measured.
            let card = AnyView(AnnotationCard(model: model, annotation: a, orphan: anchors[a.id] == nil, selected: selected == a.id)
                .frame(width: w))
            let isNew = hosts[a.id] == nil
            let host = hosts[a.id] ?? {
                let h = NSHostingView(rootView: card)
                h.sizingOptions = [.intrinsicContentSize]
                h.wantsLayer = true
                tv.addSubview(h)
                hosts[a.id] = h
                return h
            }()
            host.rootView = card
            host.layoutSubtreeIfNeeded()
            let h = ceil(max(host.intrinsicContentSize.height, host.fittingSize.height))
            let frame = CGRect(x: x, y: y, width: w, height: h)
            if isNew || Motion.reduce {
                host.frame = frame
                if isNew, !Motion.reduce {
                    host.alphaValue = 0
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = Motion.standardDuration
                        host.animator().alphaValue = 1
                    }
                }
            } else if abs(host.frame.minY - frame.minY) > 0.5 || abs(host.frame.height - frame.height) > 0.5 {
                // Text above it grew or shrank: the card glides along with its passage.
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Motion.quickDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    host.animator().frame = frame
                }
            } else {
                host.frame = frame
            }
            nextY = y + h + 10
        }
    }

    func clear() {
        for h in hosts.values { h.removeFromSuperview() }
        hosts = [:]
    }
}

struct AnnotationCard: View {
    @Bindable var model: AppModel
    let annotation: Annotation
    let orphan: Bool
    let selected: Bool
    @State private var replying = false
    @State private var draft = ""

    var body: some View {
        let a = annotation
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: Self.icon(a.kind)).foregroundStyle(Self.tint(a.kind))
                Text(a.kind.label).font(.caption.weight(.semibold)).foregroundStyle(Self.tint(a.kind))
                if orphan { Text("原文已改动").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Button { model.dismissAnnotation(a.id) } label: { Image(systemName: "xmark").font(.caption2.weight(.semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary).help("忽略这条批注")
            }
            Text(a.text).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let r = a.replacement {
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.quote).strikethrough().foregroundStyle(.secondary).lineLimit(3)
                    Text(r).foregroundStyle(.primary).lineLimit(6)
                }
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 8, style: .continuous))
            }
            ForEach(Array(a.replies.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top, spacing: 6) {
                    Text(r.from == "user" ? "你" : r.from).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(r.text).font(.caption).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            if replying {
                HStack(spacing: 6) {
                    TextField("回复这条批注…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).font(.callout).lineLimit(1...4)
                        .onSubmit(send)
                    Button("发送", systemImage: "arrow.up", action: send)
                        .labelStyle(.iconOnly).buttonStyle(.glassProminent).buttonBorderShape(.circle)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(6)
                .background(.fill.quaternary, in: .rect(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: 6) {
                if a.replacement != nil {
                    Button("采纳", systemImage: "checkmark") { model.acceptAnnotation(a.id) }
                        .buttonStyle(.glassProminent).disabled(orphan)
                } else {
                    Button("知道了", systemImage: "checkmark") { model.acceptAnnotation(a.id) }.buttonStyle(.glass)
                }
                Button("回复", systemImage: "arrowshape.turn.up.left") { replying.toggle() }.buttonStyle(.glass)
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .buttonBorderShape(.capsule)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? Self.tint(a.kind).opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: selected ? 1.5 : 0.5))
        .shadow(color: .black.opacity(selected ? 0.12 : 0.05), radius: selected ? 10 : 4, y: 2)
        .contentShape(.rect)
        .onTapGesture { model.selectAnnotation(a.id) }
    }

    private func send() {
        model.replyToAnnotation(annotation.id, draft)
        draft = ""
        replying = false
    }

    static func icon(_ k: Annotation.Kind) -> String {
        switch k {
        case .question: "questionmark.bubble"
        case .suggestion: "pencil.line"
        case .fact: "magnifyingglass"
        case .structure: "list.bullet.indent"
        case .praise: "hand.thumbsup"
        }
    }

    static func tint(_ k: Annotation.Kind) -> Color {
        switch k {
        case .question: .purple
        case .suggestion: .green
        case .fact: .orange
        case .structure: .blue
        case .praise: .pink
        }
    }
}
