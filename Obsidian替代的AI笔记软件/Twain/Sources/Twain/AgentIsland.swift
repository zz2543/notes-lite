import TwainCore
import SwiftUI

/// While an agent works and the Agent panel is closed, a small capsule above the status pill
/// says what it is doing: one glyph that moves, one line that rolls from "正在读取…" to
/// "正在写入…". When the work ends the same capsule turns into a check and a few seconds
/// later folds away. Clicking it opens the panel on that conversation.
struct AgentIsland: View {
    @Bindable var model: AppModel
    @State private var finished: AgentKind?
    @State private var lastRunning: AgentKind = .claude
    @State private var clearWork: DispatchWorkItem?

    private var live: [AgentSession] { model.agents.sessions.filter { $0.running && $0.source == .app } }

    var body: some View {
        let live = live
        let hidden = model.chrome.agentPanel
        let kind = live.first?.agent ?? finished
        ZStack(alignment: .trailing) {
            if !hidden, let kind {
                Button { open(live.first) } label: { label(live, kind) }
                    .buttonStyle(.plain)
                    .hoverGlassCapsule(tint: Theme.agentColor(kind).opacity(0.1), interactive: true)
                    .padding(.bottom, 8)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .motion(Motion.morph, value: live.isEmpty)
        .motion(Motion.morph, value: hidden)
        .onChange(of: live.map(\.id)) { old, new in
            if let a = live.first?.agent { lastRunning = a }
            guard new.isEmpty, !old.isEmpty else { return }
            let who = model.agents.sessions.first { $0.id == old.first }?.agent ?? lastRunning
            withMotion(Motion.morph) { finished = who }
            Motion.feedback(.done)
            clearWork?.cancel()
            let w = DispatchWorkItem { withMotion(Motion.morph) { finished = nil } }
            clearWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
        }
        .onChange(of: hidden) { _, h in if h { finished = nil } }
    }

    private func label(_ live: [AgentSession], _ kind: AgentKind) -> some View {
        let text: String = {
            guard let first = live.first else { return "\(kind.displayName) 完成了" }
            if live.count > 1 { return "\(live.count) 个任务进行中" }
            return "\(first.agent.displayName) \(AgentInspector.activity(first).verb)…"
        }()
        return HStack(spacing: 8) {
            ZStack {
                if let first = live.first {
                    GlyphSpinner(activity: AgentInspector.activity(first), tint: Theme.agentColor(first.agent))
                        .transition(.blurReplace)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, options: .nonRepeating, value: Motion.style == .lively ? finished : nil)
                        .transition(.blurReplace)
                }
            }
            RollingText(text: text)
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .motion(Motion.morph, value: live.isEmpty)
    }

    private func open(_ session: AgentSession?) {
        if let s = session {
            model.agents.agentPick = s.agent
            model.agents.activeSessionID = s.id
        }
        finished = nil
        model.toggleAgent()
    }
}
