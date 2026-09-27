import SwiftUI
import TwainCore

/// AI summaries for note cards. Only notes without a current summary are sent, several per
/// call to a small model, within a daily budget — the answer to "won't this burn tokens?".
extension AppModel {
    private var summaryRunsKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "summaries.count." + f.string(from: Date())
    }

    var summariesToday: Int { UserDefaults.standard.integer(forKey: summaryRunsKey) }

    /// Notes that would get a new AI summary now, counted off the main thread.
    func countNotesWantingSummary(_ done: @escaping (Int) -> Void) {
        guard let v = vault else { return done(0) }
        let root = v.root
        DispatchQueue.global(qos: .utility).async {
            let index = VaultIndex(root: root)
            index.refresh()
            let store = SummaryStore(vault: root)
            let n = index.paths.filter { p in index.notes[p].map { Skim.wantsSummary($0, store: store) } ?? false }.count
            DispatchQueue.main.async { done(n) }
        }
    }

    /// Summarizes up to `limit` notes (default: what's left of today's budget), `only` when given.
    func summarizeNotes(only: [String]? = nil, limit: Int? = nil) {
        guard let v = vault, summarizing == nil else { return }
        let budget = max(0, summaryDailyLimit - summariesToday)
        let cap = min(limit ?? budget, only == nil ? budget : Int.max)
        guard cap > 0 else { showToast("今天的摘要额度（\(summaryDailyLimit) 篇）已用完"); return }
        let root = v.root
        summarizing = (0, 0)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let index = VaultIndex(root: root)
            index.refresh()
            let store = SummaryStore(vault: root)
            let wanted = (only ?? index.paths).filter { p in
                guard let n = index.notes[p] else { return false }
                return only != nil || Skim.wantsSummary(n, store: store)
            }
            let todo = Array(wanted.prefix(cap))
            let batches = stride(from: 0, to: todo.count, by: 12).map { Array(todo[$0..<min($0 + 12, todo.count)]) }
            DispatchQueue.main.async {
                guard let self else { return }
                if todo.isEmpty { self.summarizing = nil; self.showToast("所有笔记都已有最新摘要"); return }
                self.summarizing = (0, todo.count)
                // Three calls at a time: each spends seconds starting the CLI before the model works.
                let lanes = 3
                var queue = batches
                var running = 0
                func next() {
                    guard let b = queue.first else {
                        if running == 0 { self.finishSummaries() }
                        return
                    }
                    queue.removeFirst()
                    running += 1
                    self.runSummaryBatch(b, index: index, root: root) { ok in
                        running -= 1
                        if !ok { queue.removeAll() }
                        next()
                    }
                }
                for _ in 0..<min(lanes, batches.count) { next() }
            }
        }
    }

    private func finishSummaries() {
        let n = summarizing?.done ?? 0
        summarizing = nil
        tick += 1
        showToast(n > 0 ? "已为 \(n) 篇笔记生成摘要" : "生成摘要失败：没能从 claude 拿到可用的结果")
    }

    private func runSummaryBatch(_ batch: [String], index: VaultIndex, root: URL, done: @escaping (Bool) -> Void) {
        let body = batch.compactMap { rel -> String? in
            guard let n = index.notes[rel] else { return nil }
            var lines = n.lines
            if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { lines = Array(lines[(end + 1)...]) }
            let text = String(lines.joined(separator: "\n").prefix(1200))
            return "<note path=\"\(rel)\">\n\(text)\n</note>"
        }.joined(separator: "\n\n")
        let prompt = """
        下面是若干篇个人笔记（路径和开头部分）。为每篇写一句中文摘要，25 到 60 个字：说清它讲什么、能拿来做什么，\
        让人以后检索时一眼判断要不要细读。不要复述标题，不要用“本文”“这篇笔记”开头，不要编造笔记里没有的内容。
        只输出一个 JSON 对象，键是路径，值是摘要，不要任何其他文字。

        \(body)
        """
        ModelCall.ask(prompt, cwd: root, timeout: 150) { [weak self] reply in
            guard let self else { return }
            let store = SummaryStore(vault: root)
            var wrote = 0
            if let obj = reply.flatMap(ModelCall.jsonObject) {
                for rel in batch {
                    guard let s = obj[rel] as? String, let n = index.notes[rel] else { continue }
                    store.set(rel, text: s, source: "ai", hash: Skim.hash(n.lines))
                    wrote += 1
                }
            }
            UserDefaults.standard.set(self.summariesToday + wrote, forKey: self.summaryRunsKey)
            self.summarizing?.done += wrote
            done(wrote > 0)
        }
    }

    /// The open note's card, for the info popover.
    func activeCard() -> NoteCard? {
        guard let v = vault, let rel = activeRel, let index else { return nil }
        index.update(rel, text: editorText)
        guard let n = index.notes[rel] else { return nil }
        return Skim.card(n, store: SummaryStore(vault: v.root))
    }

    func saveSummary(_ text: String) {
        guard let v = vault, let rel = activeRel else { return }
        SummaryStore(vault: v.root).set(rel, text: text, source: "user", hash: Skim.hash(Markdown.lines(editorText)))
        tick += 1
        showToast(text.isEmpty ? "已清除摘要" : "已保存摘要")
    }
}

/// The open note at a glance: the card agents see first, with the summary editable.
struct NoteInfoPopover: View {
    @Bindable var model: AppModel
    @State private var card: NoteCard?
    @State private var draft = ""
    @State private var backlinks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let card {
                HStack {
                    Text(card.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text("\(card.words) 字").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("摘要").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(Self.sourceLabel(card.source)).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.fill.tertiary, in: .capsule)
                        Spacer()
                        if model.summarizing != nil { ProgressView().controlSize(.mini) }
                    }
                    TextField("一句话说明这篇笔记讲什么", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...5)
                        .padding(8)
                        .background(.fill.quinary, in: .rect(cornerRadius: Metrics.rowRadius, style: .continuous))
                        .disabled(card.source == "frontmatter")
                    if card.source == "frontmatter" {
                        Text("摘要来自笔记开头的 summary 字段，在正文里修改。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !card.tags.isEmpty {
                    Text(card.tags.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(Color(nsColor: Theme.NS.tag))
                }
                if !card.headings.isEmpty {
                    Text(card.headings.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Text("\(backlinks) 篇笔记链接到这里 · agent 检索时先读到的就是这张名片")
                    .font(.caption).foregroundStyle(.tertiary)
                HStack {
                    Button("用 AI 重写", systemImage: "sparkle") {
                        if let rel = model.activeRel { model.flushSave(); model.summarizeNotes(only: [rel]) }
                    }
                    .disabled(model.summarizing != nil || card.source == "frontmatter")
                    Spacer()
                    Button("保存") { model.saveSummary(draft); refresh() }
                        .buttonStyle(.glassProminent)
                        .disabled(draft == card.summary || card.source == "frontmatter")
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear(perform: refresh)
        .onChange(of: model.tick) { _, _ in refresh() }
    }

    private func refresh() {
        card = model.activeCard()
        draft = card?.summary ?? ""
        if let rel = model.activeRel, let index = model.index { backlinks = Set(index.backlinks(to: rel).map(\.rel)).count }
    }

    static func sourceLabel(_ s: String) -> String {
        ["auto": "自动提取", "ai": "AI 生成", "user": "你写的", "frontmatter": "frontmatter"][s] ?? s
    }
}
