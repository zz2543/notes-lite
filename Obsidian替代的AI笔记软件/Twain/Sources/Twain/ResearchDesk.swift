import SwiftUI
import TwainCore

/// 问库: a question put to the whole vault (or a folder, or a tag), answered as cards on a desk.
/// Each card is short and cites its notes; the user pins, questions, strikes and assembles cards
/// into a draft note — the answer is built together, not read as one long reply.
struct ResearchDesk: Codable, Identifiable, Equatable {
    var id: String
    var question: String
    /// "" the whole vault, "folder:<path>" or "tag:<name>".
    var scope: String
    var cards: [ResearchCard]
    var draft: String?
    var session: String?
    var created: Date

    var scopeLabel: String {
        if scope.hasPrefix("folder:") { return "文件夹「\(scope.dropFirst(7))」" }
        if scope.hasPrefix("tag:") { return "标签 #\(scope.dropFirst(4))" }
        return "全库"
    }
}

extension AppModel {
    private var desksDir: URL? { vault?.root.appendingPathComponent(".twain/desks") }

    func loadDesks() {
        guard let dir = desksDir else { desks = []; return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        desks = files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? dec.decode(ResearchDesk.self, from: $0) } }
            .sorted { $0.created > $1.created }
    }

    func saveDesk(_ d: ResearchDesk) {
        guard let dir = desksDir else { return }
        if let i = desks.firstIndex(where: { $0.id == d.id }) { desks[i] = d } else { desks.insert(d, at: 0) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? enc.encode(d) { try? data.write(to: dir.appendingPathComponent(d.id + ".json"), options: .atomic) }
    }

    func deleteDesk(_ id: String) {
        guard let dir = desksDir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(id + ".json"))
        desks.removeAll { $0.id == id }
        if openDesk == id { openDesk = nil }
    }

    var currentDesk: ResearchDesk? { openDesk.flatMap { id in desks.first { $0.id == id } } }

    /// An empty desk to type a question into.
    func newDesk() {
        flushSave()
        let d = ResearchDesk(id: String(UUID().uuidString.prefix(8)).lowercased(), question: "", scope: "", cards: [],
                             draft: nil, session: nil, created: Date())
        saveDesk(d)
        openDesk = d.id
        selection = "desk:" + d.id
    }

    /// Sends the desk's question to the agent picked in the panel.
    func ask(desk id: String, question: String, scope: String, model: String? = nil) {
        guard var d = desks.first(where: { $0.id == id }) else { return }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        d.question = q
        d.scope = scope
        let s = AgentSession(agent: agentPick, source: .app, title: "问库 · " + String(q.prefix(12)))
        s.extraTools = ["cards"]
        s.readOnly = true
        s.deskID = d.id
        sessions.append(s)
        d.session = s.id.uuidString
        saveDesk(d)
        let range: String
        if scope.hasPrefix("folder:") { range = "只在文件夹「\(scope.dropFirst(7))」里找（skim 时带 folder）" }
        else if scope.hasPrefix("tag:") { range = "只看带标签 #\(scope.dropFirst(4)) 的笔记（skim 时带 tag）" }
        else { range = "整个笔记库" }
        let prompt = """
        问题：\(q)
        范围：\(range)。
        在范围内找资料回答这个问题：先用 skim 看笔记名片（可以带 query 缩小），再用 read_note 读相关的提纲和小节，只读需要的部分。
        每得到一个可靠的发现就用 cards 工具提交，每次 1 到 4 张，边找边交：claim 是结论，evidence 是原文证据（body 里引用原句），
        conflict 是资料之间的矛盾，open 是资料没有回答的问题。每张卡片必须带 sources（笔记路径和行号）。
        卡片要短：标题不超过 20 字，正文不超过 120 字。不要写成文章，不要修改任何文件。最后用一句话说明还缺什么资料。
        """
        runAgent(prompt: prompt, agent: s.agent, model: model, in: s)
        agentPanel = false
    }

    func cardsCommand(_ call: CommandCall) throws -> JSONValue {
        guard let s = call.session, let deskID = s.deskID, var d = desks.first(where: { $0.id == deskID }) else {
            throw RPCError(RPCError.invalidParams, "cards 只能在问库发起的会话里使用")
        }
        let (index, _) = try freshIndex()
        let cards = try ResearchCard.parse(call.params["items"]?.array ?? [], index: index, parent: nil)
        d.cards += cards
        saveDesk(d)
        emit("desk.cards", source: eventSource(for: s), ["desk": .string(d.id), "count": JSONValue(cards.count)])
        return ["desk": .string(d.id), "added": JSONValue(cards.count), "total": JSONValue(d.cards.count)]
    }

    func setCard(_ cardID: String, in deskID: String, _ state: ResearchCard.State) {
        guard var d = desks.first(where: { $0.id == deskID }), let i = d.cards.firstIndex(where: { $0.id == cardID }) else { return }
        d.cards[i].state = d.cards[i].state == state ? .new : state
        saveDesk(d)
    }

    /// Appends the card to the desk's draft note, creating the note on first use.
    func draftCard(_ cardID: String, in deskID: String) {
        guard let v = vault, var d = desks.first(where: { $0.id == deskID }),
              let i = d.cards.firstIndex(where: { $0.id == cardID }) else { return }
        if d.draft == nil || v.note(d.draft!) == nil {
            var name = d.question.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            name = String(name.prefix(30)).trimmingCharacters(in: .whitespaces)
            let rel = v.uniqueRel(title: name.isEmpty ? "研究草稿" : name, folder: "研究台")
            v.forceWrite(rel, "# \(d.question)\n")
            v.scan()
            d.draft = rel
        }
        guard let rel = d.draft else { return }
        if rel == activeRel { flushSave() }
        let before = v.diskContent(rel) ?? ""
        let text = before + (before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n") + d.cards[i].markdown
        v.forceWrite(rel, text)
        if rel == activeRel { reloadEditor() }
        d.cards[i].state = .drafted
        saveDesk(d)
        showToast("已收进草稿「\(NoteRef(rel: rel).title)」")
    }

    /// Asks about one card; the answer comes back as cards under it.
    func followUp(_ cardID: String, in deskID: String, question: String, model: String? = nil) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let d = desks.first(where: { $0.id == deskID }), let card = d.cards.first(where: { $0.id == cardID }),
              let sid = d.session, let s = sessions.first(where: { $0.id.uuidString == sid }) else {
            showToast("这张卡片所在的会话已经结束，重新提问吧")
            return
        }
        guard !s.running else { showToast("\(s.agent.displayName) 还在找资料，等它结束再追问"); return }
        let prompt = """
        关于卡片 \(card.id)「\(card.title)」：\(q)
        继续按同样的方式找资料，用 cards 回答，每张都填 parent=\(card.id)，同样带出处。
        """
        runAgent(prompt: prompt, agent: s.agent, model: model, in: s)
        agentPanel = false
    }
}

// MARK: - Views

struct ResearchDeskView: View {
    @Bindable var model: AppModel
    let desk: ResearchDesk
    @State private var question = ""
    @State private var scope = ""
    @State private var filter: ResearchCard.Kind?
    @State private var showDiscarded = false

    private var session: AgentSession? { desk.session.flatMap { id in model.sessions.first { $0.id.uuidString == id } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if desk.cards.isEmpty {
                    empty
                } else {
                    filters
                    let tops = visible.filter { card in card.parent == nil || !desk.cards.contains { $0.id == card.parent } }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(tops) { c in
                            CardView(model: model, deskID: desk.id, card: c, replies: visible.filter { $0.parent == c.id },
                                     canFollowUp: session?.running == false)
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 70).padding(.bottom, 90)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaBar(edge: .bottom) { draftBar }
        .onAppear { question = desk.question; scope = desk.scope }
        .onChange(of: desk.id) { _, _ in question = desk.question; scope = desk.scope }
    }

    private var visible: [ResearchCard] {
        desk.cards.filter { c in
            (showDiscarded || c.state != .discarded) && (filter == nil || c.kind == filter)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("问库", systemImage: "rectangle.stack.badge.person.crop").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("问你的笔记一个问题…", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1...3)
                    .onSubmit(send)
                scopeMenu
                Button(desk.cards.isEmpty ? "提问" : "重新提问", systemImage: "arrow.up") { send() }
                    .buttonStyle(.glassProminent)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || session?.running == true)
            }
            HStack(spacing: 8) {
                if session?.running == true {
                    ProgressView().controlSize(.small)
                    Text("\(model.agentPick.displayName) 正在找资料 · 已有 \(desk.cards.count) 张卡片").foregroundStyle(.secondary)
                } else if !desk.cards.isEmpty {
                    Text("\(desk.scopeLabel) · \(desk.cards.count) 张卡片 · 钉住有用的，划掉没用的，收进草稿").foregroundStyle(.secondary)
                } else {
                    Text("答案会是一组带出处的卡片：结论、证据、分歧、待解问题").foregroundStyle(.secondary)
                }
                Spacer()
                if let s = session { Button("查看过程") { model.activeSessionID = s.id; model.agentPanel = true }.buttonStyle(.borderless) }
            }
            .font(.callout)
        }
    }

    private var scopeMenu: some View {
        Menu {
            Button("全库") { scope = "" }
            Menu("文件夹") {
                ForEach(model.vault?.folders ?? [], id: \.self) { f in Button(f) { scope = "folder:" + f } }
            }
            Menu("标签") {
                ForEach(model.index.map { idx in Array(Set(idx.notes.values.flatMap(\.outline.tags))).sorted() } ?? [], id: \.self) { t in
                    Button("#" + t) { scope = "tag:" + t }
                }
            }
        } label: {
            Label(ResearchDesk(id: "", question: "", scope: scope, cards: [], draft: nil, session: nil, created: Date()).scopeLabel,
                  systemImage: "scope")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
    }

    private var filters: some View {
        HStack(spacing: 6) {
            chip("全部", nil)
            ForEach(ResearchCard.Kind.allCases, id: \.self) { k in chip(k.label, k) }
            Spacer()
            Toggle("显示划掉的", isOn: $showDiscarded).toggleStyle(.checkbox).font(.caption)
        }
    }

    private func chip(_ label: String, _ kind: ResearchCard.Kind?) -> some View {
        let n = kind.map { k in desk.cards.filter { $0.kind == k && $0.state != .discarded }.count }
            ?? desk.cards.filter { $0.state != .discarded }.count
        let on = filter == kind
        return Button { filter = kind } label: {
            Text("\(label) \(n)").font(.caption.weight(on ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(on ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("试试这样问").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            ForEach(["我对这个主题的看法前后有过哪些变化？", "这些笔记里有哪些互相矛盾的地方？", "关于这件事，我还缺哪些资料？"], id: \.self) { s in
                Button(s) { question = s }.buttonStyle(.glass).buttonBorderShape(.capsule)
            }
        }
        .padding(.top, 20)
    }

    private var draftBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            if let rel = desk.draft {
                let n = desk.cards.filter { $0.state == .drafted }.count
                Text("草稿：\(NoteRef(rel: rel).title) · 已收进 \(n) 张卡片").lineLimit(1)
                Spacer()
                Button("打开草稿") { model.open(rel) }.buttonStyle(.glassProminent)
            } else {
                Text("收进草稿的卡片会按顺序写进一篇新笔记（研究台/）").foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassCapsule()
        .padding(Metrics.floatInset)
    }

    private func send() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, session?.running != true else { return }
        model.ask(desk: desk.id, question: q, scope: scope)
    }
}

private struct CardView: View {
    @Bindable var model: AppModel
    let deskID: String
    let card: ResearchCard
    let replies: [ResearchCard]
    let canFollowUp: Bool
    @State private var asking = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content(card, main: true)
            ForEach(replies) { r in
                Divider()
                content(r, main: false)
            }
            if asking {
                HStack(spacing: 6) {
                    TextField("追问这张卡片…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).font(.callout).lineLimit(1...3).onSubmit(send)
                    Button("追问", systemImage: "arrow.up", action: send)
                        .labelStyle(.iconOnly).buttonStyle(.glassProminent).buttonBorderShape(.circle)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(6)
                .background(.fill.quaternary, in: .rect(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: 4) {
                iconButton(card.state == .pinned ? "pin.fill" : "pin", card.state == .pinned ? "取消钉住" : "钉住") {
                    model.setCard(card.id, in: deskID, .pinned)
                }
                iconButton(card.state == .drafted ? "checkmark.circle.fill" : "text.badge.plus", "收进草稿") {
                    model.draftCard(card.id, in: deskID)
                }
                iconButton("bubble.left.and.text.bubble.right", "追问") { asking.toggle() }
                    .disabled(!canFollowUp)
                Spacer()
                iconButton(card.state == .discarded ? "arrow.uturn.backward" : "xmark", card.state == .discarded ? "恢复" : "划掉") {
                    model.setCard(card.id, in: deskID, .discarded)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(card.state == .pinned ? Self.tint(card.kind).opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.5),
                          lineWidth: card.state == .pinned ? 1.5 : 0.5))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .opacity(card.state == .discarded ? 0.45 : 1)
    }

    @ViewBuilder
    private func content(_ c: ResearchCard, main: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(c.kind.label).font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Self.tint(c.kind), in: .capsule)
                if !main { Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary) }
            }
            Text(c.title).font(main ? .headline : .subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if !c.body.isEmpty {
                Text(c.body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if !c.sources.isEmpty {
                FlowSources(sources: c.sources) { s in
                    model.open(s.path)
                    if let line = s.line { model.requestFocus(caret: CommandRegistry.offset(ofLine: line, in: model.editorText)) }
                }
            }
        }
    }

    private func iconButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 26, height: 22) }
            .buttonStyle(.borderless).help(help)
    }

    private func send() {
        model.followUp(card.id, in: deskID, question: draft)
        draft = ""
        asking = false
    }

    static func tint(_ k: ResearchCard.Kind) -> Color {
        switch k {
        case .claim: .blue
        case .evidence: .green
        case .conflict: .orange
        case .open: .purple
        }
    }
}

/// Source chips that wrap onto new lines.
private struct FlowSources: View {
    let sources: [ResearchCard.Source]
    let open: (ResearchCard.Source) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(sources, id: \.self) { s in
                Button { open(s) } label: {
                    Label(NoteRef(rel: s.path).title + (s.line.map { ":\($0)" } ?? ""), systemImage: "doc.text")
                        .font(.caption).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.fill.tertiary, in: .capsule)
                }
                .buttonStyle(.plain)
                .help(s.path)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing
            row = max(row, sz.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            row = max(row, sz.height)
        }
    }
}
