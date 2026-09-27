import TwainCore
import SwiftUI

/// The toolbar tools every page shares: what waits on the user, a new task, and ⌘K.
struct CommonTools: ToolbarContent {
    @Bindable var model: AppModel

    var body: some ToolbarContent {
        let n = model.waiting.count
        if n > 0 {
            ToolbarItem(placement: .primaryAction) {
                Button { model.inboxOpen.toggle() } label: {
                    Label("待处理 \(n)", systemImage: "tray.full").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .help("Agent 的问题和待审阅的改动 · 逐篇审阅 ⇧⌘R")
                .popover(isPresented: $model.inboxOpen, arrowEdge: .bottom) { InboxView(model: model) }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("新任务", systemImage: "sparkles", action: model.openTaskBar)
                .help("交给 agent 一件事 ⌘L")
            Button("命令面板", systemImage: "magnifyingglass", action: model.openPalette)
                .help("搜索笔记与命令 ⌘K")
        }
    }
}

/// Everything waiting on the user in one list: answer questions here, accept or open
/// reviews, send review feedback back. Reviews can also be walked one after another.
struct InboxView: View {
    @Bindable var model: AppModel

    var body: some View {
        let w = model.waiting
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("待处理").font(.headline)
                Spacer()
                if !w.reviews.isEmpty {
                    Button {
                        model.startReviewFlow()
                    } label: {
                        Label("逐篇审阅", systemImage: "arrow.right.circle.fill").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("一篇接一篇地审阅，处理完回到现在的位置 ⇧⌘R")
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if w.count == 0 {
                        Label("都处理完了", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(w.questions) { q in
                        VStack(alignment: .leading, spacing: 4) {
                            if let s = model.sessions.first(where: { $0.id == q.sessionID }) {
                                Text("\(s.agent.displayName) · \(s.title)").font(.caption).foregroundStyle(.secondary)
                            }
                            QuestionCard(model: model, question: q)
                        }
                    }
                    ForEach(w.reviews, id: \.rel) { r in ReviewRow(model: model, review: r) }
                    ForEach(w.feedback, id: \.item) { f in
                        HStack(spacing: 10) {
                            Image(systemName: "text.bubble").font(.title3).foregroundStyle(.secondary).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("审阅意见 · " + Self.name(f.rel)).fontWeight(.medium).lineLimit(1)
                                Text("还没有发回给 \(f.session.agent.displayName)").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("发回") { model.sendFeedback(f.item, in: f.session) }
                                .buttonStyle(.glassProminent)
                                .disabled(f.session.running)
                                .help("让 \(f.session.agent.displayName) 根据你的审阅意见重新修改")
                        }
                        .controlSize(.small)
                        .buttonBorderShape(.capsule)
                        .padding(10)
                        .contentCard()
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 480)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 400)
    }

    static func name(_ rel: String) -> String {
        ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

/// One note's pending changes: who made them, how big, and the two ways to settle them.
struct ReviewRow: View {
    @Bindable var model: AppModel
    let review: PendingReview

    var body: some View {
        let r = review
        HStack(spacing: 10) {
            Image(systemName: r.isProposal ? "doc.badge.ellipsis" : "doc.badge.clock")
                .font(.title3)
                .foregroundStyle(r.by.map(Theme.agentColor) ?? .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(InboxView.name(r.rel)).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 6) {
                    CountBadge(plus: r.plus, minus: r.minus)
                    Text("\(r.by?.displayName ?? "外部") \(r.isProposal ? "提议" : "改动") · \(r.hunks.count) 处")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("全部接受") { model.acceptAll(r.rel) }
                .buttonStyle(.glass)
                .help(r.isProposal ? "把这份提案全部写入文件" : "保留 agent 的全部改动")
            Button("审阅") { model.review(r.rel) }
                .buttonStyle(.glassProminent)
                .help("逐段审阅，处理完回到现在的位置")
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .padding(10)
        .contentCard()
    }
}
