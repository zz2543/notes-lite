import PlumeCore
import SwiftUI

/// Reviewing an agent's write: the page with each change set in its own card.
/// Window-level actions (later, revert all, accept) live in the toolbar.
struct ReviewView: View {
    @Bindable var model: AppModel
    let review: PendingReview

    /// First lines of unchanged runs the reader has unfolded.
    @State private var expanded: Set<Int> = []

    private var blocks: [DiffBlock] {
        LineDiff.blocks(base: review.baseline, hunks: review.hunks, context: 3, expanded: expanded)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case let .context(rows):
                        VStack(alignment: .leading, spacing: 0) {
                            DiffRows(rows: rows) { line in
                                withAnimation(.snappy(duration: 0.2)) { _ = expanded.insert(line) }
                            }
                        }
                    case let .hunk(index, rows):
                        HunkCard(model: model, index: index, hunk: review.hunks[index],
                                 counts: LineDiff.counts(review.hunks[index], base: review.baseline), rows: rows,
                                 note: index < review.notes.count ? review.notes[index] : nil,
                                 feedback: index < review.feedback.count ? review.feedback[index] : nil,
                                 asksWhy: review.by != nil, proposal: review.isProposal)
                    }
                }
            }
            .font(Font(model.font.nsFont(size: 15)))
            .frame(maxWidth: model.editorWidth + 60, alignment: .leading)
            .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onChange(of: review.rel) { expanded = [] }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        let name = ((model.activeRel ?? "") as NSString).lastPathComponent
        let tint = review.by.map(Theme.agentColor) ?? .secondary
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: review.by.map(Theme.agentSymbol) ?? "doc.badge.clock")
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(tint.opacity(0.15)), in: .circle)
            VStack(alignment: .leading, spacing: 5) {
                Text(title(name))
                    .font(.title3.weight(.semibold))
                if let reason = review.reason {
                    Text(reason).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    CountBadge(plus: review.plus, minus: review.minus)
                    Text("\(review.hunks.count) 处改动 · " + (review.isProposal
                        ? "还没有写入文件，只有接受的部分会写入"
                        : "文件已在磁盘上改动，还原会恢复到写入前的版本"))
                        .foregroundStyle(.secondary)
                    if let s = review.snapshot {
                        Label("快照 " + s.prefix(7), systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                            .help("写入前的 git 快照")
                    }
                }
                .font(.caption)
            }
        }
        .padding(.bottom, 8)
    }
}

extension ReviewView {
    func title(_ name: String) -> String {
        let who = agentLabel(review.by)
        if review.isProposal { return review.isNew ? "\(who) 提议新建 \(name)" : "\(who) 提议修改 \(name)" }
        let place = review.source == .terminal ? "在终端中" : review.source == .automation ? "在自动化中" : "在 Plume 中"
        return "\(who) \(place)修改了 \(name)"
    }
}

struct CountBadge: View {
    let plus: Int
    let minus: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("+\(plus)").foregroundStyle(.green)
            Text("−\(minus)").foregroundStyle(.red)
        }
        .font(.caption.monospacedDigit().weight(.medium))
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(.fill.tertiary, in: .capsule)
    }
}

private struct HunkCard: View {
    @Bindable var model: AppModel
    let index: Int
    let hunk: Hunk
    let counts: (plus: Int, minus: Int)
    let rows: [DiffRow]
    /// Why the agent made this change, when it said.
    var note: String?
    /// Why the user rejected it, when they said.
    var feedback: String?
    /// Offer a reason field on rejection: only an agent can learn from it.
    var asksWhy = true
    /// Proposals are rejected; changes already written are reverted.
    var proposal = false
    @State private var why = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let note {
                Label {
                    Text(note).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb").foregroundStyle(.secondary)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                DiffRows(rows: rows)
            }
            .padding(6)
            Divider().opacity(0.6)
            footer
                .padding(.horizontal, 12).padding(.vertical, 8)
            if hunk.state == .rejected, asksWhy {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("原因").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("为什么不要这处改动？写下来 agent 下次就知道（可选）", text: $why, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                }
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.rowRadius, style: .continuous))
                .padding(.horizontal, 10).padding(.bottom, 10)
                .onAppear { why = feedback ?? "" }
                .onChange(of: why) { _, v in model.setFeedback(index, v) }
            }
        }
        .contentCard(radius: Metrics.cardRadius)
        .opacity(hunk.state == .pending ? 1 : 0.85)
        .animation(.snappy(duration: 0.2), value: hunk.state)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("改动 \(index + 1)")
                .font(.caption.weight(.medium))
            CountBadge(plus: counts.plus, minus: counts.minus)
            Spacer()
            if hunk.state == .pending {
                Button(proposal ? "拒绝" : "还原", systemImage: "arrow.uturn.backward") { model.setHunk(index, .rejected) }
                    .buttonStyle(.glass)
                Button("接受", systemImage: "checkmark") { model.setHunk(index, .accepted) }
                    .buttonStyle(.glassProminent)
            } else {
                Label(hunk.state == .accepted ? "已接受" : proposal ? "已拒绝" : "已还原",
                      systemImage: hunk.state == .accepted ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                    .font(.caption)
                    .foregroundStyle(hunk.state == .accepted ? .green : .secondary)
                Button("撤销") { model.setHunk(index, .pending) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
    }
}

private struct DiffRows: View {
    let rows: [DiffRow]
    var unfold: (Int) -> Void = { _ in }

    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            switch row {
            case let .deleted(t, changed): DiffLine(mark: "−", text: t, changed: changed, style: .deleted)
            case let .added(t, changed): DiffLine(mark: "+", text: t, changed: changed, style: .added)
            case let .context(t): DiffLine(mark: " ", text: t, style: .context)
            case let .gap(line, count): FoldedLines(count: count) { unfold(line) }
            case .bar: EmptyView()
            }
        }
    }
}

/// Unchanged lines tucked away between changes; clicking brings them back.
private struct FoldedLines: View {
    let count: Int
    let unfold: () -> Void

    var body: some View {
        Button(action: unfold) {
            Label("\(count) 行未改动", systemImage: "arrow.up.and.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(.fill.quaternary, in: .rect(cornerRadius: 6, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("展开未改动的内容")
        .padding(.horizontal, 10).padding(.vertical, 4)
    }
}

private struct DiffLine: View {
    enum Style { case context, deleted, added }
    let mark: String
    let text: String
    var changed: [Range<Int>] = []
    let style: Style

    /// The line with the words that differ from its paired line picked out.
    private var marked: AttributedString {
        var s = AttributedString(text.isEmpty ? " " : text)
        guard !changed.isEmpty, !text.isEmpty else { return s }
        let chars = s.characters
        let tint = style == .added ? Color.green.opacity(0.32) : Color.red.opacity(0.24)
        for r in changed where r.upperBound <= chars.count {
            let lo = chars.index(chars.startIndex, offsetBy: r.lowerBound)
            let hi = chars.index(lo, offsetBy: r.count)
            s[lo..<hi].backgroundColor = tint
        }
        return s
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(mark)
                .foregroundStyle(style == .added ? .green : style == .deleted ? .red : .clear)
                .frame(width: 20, alignment: .leading)
            Text(marked)
                .strikethrough(style == .deleted, color: .red.opacity(0.5))
                .foregroundStyle(style == .context ? AnyShapeStyle(.secondary) : style == .deleted ? AnyShapeStyle(.red.opacity(0.85)) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background {
            if style != .context {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(style == .added ? Color.green.opacity(0.13) : Color.red.opacity(0.09))
            }
        }
    }
}
