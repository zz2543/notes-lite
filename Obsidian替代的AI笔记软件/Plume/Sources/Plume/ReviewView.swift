import PlumeCore
import SwiftUI

/// Reviewing an agent's write: the page with each change set in its own card.
/// Window-level actions (later, revert all, accept) live in the toolbar.
struct ReviewView: View {
    @Bindable var model: AppModel
    let review: PendingReview

    private enum Segment: Identifiable {
        case context(id: Int, lines: [String])
        case hunk(id: Int, index: Int, rows: [DiffRow])
        var id: Int {
            switch self {
            case let .context(id, _), let .hunk(id, _, _): id
            }
        }
    }

    /// Splits the flat row list into untouched runs and one block per hunk.
    private var segments: [Segment] {
        var out: [Segment] = []
        var buffer: [DiffRow] = []
        func flushContext() {
            let lines = buffer.compactMap { if case let .context(t) = $0 { t } else { nil } }
            if !lines.isEmpty { out.append(.context(id: out.count, lines: lines)) }
            buffer.removeAll()
        }
        for row in LineDiff.rows(base: review.baseline, hunks: review.hunks) {
            guard case let .bar(i) = row else { buffer.append(row); continue }
            let h = review.hunks[i]
            let own = (h.state == .accepted ? 0 : h.del) + (h.state == .rejected ? 0 : h.add.count)
            let take = min(own, buffer.count)
            let rows = Array(buffer.suffix(take))
            buffer.removeLast(take)
            flushContext()
            out.append(.hunk(id: out.count, index: i, rows: rows))
        }
        flushContext()
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(segments) { seg in
                    switch seg {
                    case let .context(_, lines):
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, t in
                                DiffLine(mark: " ", text: t, style: .context)
                            }
                        }
                    case let .hunk(_, index, rows):
                        HunkCard(model: model, index: index, hunk: review.hunks[index], rows: rows)
                    }
                }
            }
            .font(Font(model.font.nsFont(size: 15)))
            .frame(maxWidth: model.editorWidth + 60, alignment: .leading)
            .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
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
                Text("\(agentLabel(review.by)) \(review.source == .terminal ? "在终端中" : "在 Plume 中")修改了 \(name)")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    CountBadge(plus: review.plus, minus: review.minus)
                    Text("\(review.hunks.count) 处改动 · 文件已在磁盘上改动，还原会恢复到写入前的版本")
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
    let rows: [DiffRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case let .deleted(t): DiffLine(mark: "−", text: t, style: .deleted)
                    case let .added(t): DiffLine(mark: "+", text: t, style: .added)
                    case let .context(t): DiffLine(mark: " ", text: t, style: .context)
                    case .bar: EmptyView()
                    }
                }
            }
            .padding(6)
            Divider().opacity(0.6)
            footer
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .contentCard(radius: Metrics.cardRadius)
        .opacity(hunk.state == .pending ? 1 : 0.85)
        .animation(.snappy(duration: 0.2), value: hunk.state)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("改动 \(index + 1)")
                .font(.caption.weight(.medium))
            CountBadge(plus: hunk.add.count, minus: hunk.del)
            Spacer()
            if hunk.state == .pending {
                Button("还原", systemImage: "arrow.uturn.backward") { model.setHunk(index, .rejected) }
                    .buttonStyle(.glass)
                Button("接受", systemImage: "checkmark") { model.setHunk(index, .accepted) }
                    .buttonStyle(.glassProminent)
            } else {
                Label(hunk.state == .accepted ? "已接受" : "已还原",
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

private struct DiffLine: View {
    enum Style { case context, deleted, added }
    let mark: String
    let text: String
    let style: Style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(mark)
                .foregroundStyle(style == .added ? .green : style == .deleted ? .red : .clear)
                .frame(width: 20, alignment: .leading)
            Text(text.isEmpty ? " " : text)
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
