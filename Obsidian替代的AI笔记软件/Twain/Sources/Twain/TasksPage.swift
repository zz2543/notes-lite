import TwainCore
import SwiftUI

/// Every task by where it stands. Opened from the sidebar's task list when it runs long.
struct TasksPage: View {
    @Bindable var model: AppModel

    var body: some View {
        let all = model.listedSessions
        let groups: [(SessionState, [AgentSession])] = [SessionState.asking, .running, .reviewing, .failed, .done].compactMap { st in
            let items = all.filter { model.state(of: $0) == st }
            return items.isEmpty ? nil : (st, items)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("任务").font(.largeTitle.weight(.semibold))
                    Text("\(all.count)").font(.title3).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("新对话", systemImage: "bubble.left.and.text.bubble.right", action: model.newThread)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    Button("新任务", systemImage: "sparkles", action: model.openTaskBar)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                }
                if all.isEmpty {
                    ContentUnavailableView("还没有任务", systemImage: "sparkles",
                                           description: Text("按 ⌘L 交给 agent 一件事；在笔记里选中一段，可以直接让它改写。"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
                ForEach(groups, id: \.0) { st, items in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: st.icon).foregroundStyle(st.color)
                            Text(st.label).font(.headline)
                            Text("\(items.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        ForEach(items) { s in TaskRow(model: model, session: s) }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("任务")
        .navigationSubtitle(model.vault?.name ?? "")
        .toolbar { CommonTools(model: model) }
    }
}

/// One task: who, what, where it stands, what it last said and which notes it touched.
struct TaskRow: View {
    @Bindable var model: AppModel
    let session: AgentSession

    var body: some View {
        let state = model.state(of: session)
        let touched = model.touched(session)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.source == .terminal ? "apple.terminal" : session.source == .automation ? "bolt.circle" : Theme.agentSymbol(session.agent))
                .foregroundStyle(Theme.agentColor(session.agent))
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.title).fontWeight(.medium).lineLimit(1)
                    if session.isThread { Image(systemName: "bubble.left.and.text.bubble.right").font(.caption).foregroundStyle(.tertiary) }
                    Spacer(minLength: 4)
                    Text(session.started, style: .relative).font(.caption).foregroundStyle(.tertiary)
                    StateBadge(state: state)
                }
                if let line = model.lastLine(session) {
                    Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if !touched.isEmpty {
                    Label(touched.map(InboxView.name).joined(separator: "、"), systemImage: "doc.text")
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            if session.running, session.source == .app {
                Button("停止", systemImage: "stop.fill") { model.stopAgent(session) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("停止")
            }
        }
        .padding(12)
        .contentCard()
        .contentShape(.rect)
        .onTapGesture { model.showThread(session) }
        .help("打开这个任务的对话")
    }
}

struct StateBadge: View {
    let state: SessionState

    var body: some View {
        HStack(spacing: 4) {
            if state == .running { ProgressView().controlSize(.mini) }
            Text(state.label)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(state.color)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(state.color.opacity(0.12), in: .capsule)
    }
}
