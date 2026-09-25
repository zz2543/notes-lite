import PlumeCore
import SwiftUI

struct AgentPanel: View {
    @Bindable var model: AppModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        let sess = model.activeSession
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Agent").font(.system(size: 13, weight: .semibold))
                Text("cwd " + (model.vault?.displayPath ?? "~"))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                    .lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                if let sess, sess.source == .app, sess.running {
                    Button { model.stopAgent(sess) } label: {
                        Text("停止").font(.system(size: 12)).padding(.horizontal, 9).frame(height: 24)
                    }
                    .buttonStyle(.hover(.black.opacity(0.08), base: .black.opacity(0.05)))
                }
                Button(action: model.newSession) {
                    Text("新会话").font(.system(size: 12)).padding(.horizontal, 9).frame(height: 24)
                }
                .buttonStyle(.hover(.black.opacity(0.08), base: .black.opacity(0.05)))
            }
            .padding(.leading, 16).padding(.trailing, 12)
            .frame(height: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelLine).frame(height: 1) }

            if !model.sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.sessions) { s in chip(s, selected: s.id == sess?.id) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelLine).frame(height: 1) }
            }

            if let sess {
                Text(meta(sess))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 10)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let sess, !sess.items.isEmpty {
                            ForEach(sess.items) { it in ItemView(model: model, item: it).id(it.id) }
                            if sess.running && sess.source == .app {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("运行中…").font(.system(size: 11.5)).foregroundStyle(Theme.muted2)
                                }
                                .id("running")
                            }
                        } else {
                            Text("描述一个任务。Claude Code 或 Codex 会直接读写库里的 Markdown 文件，每次改动都进入审阅，可逐段接受或还原。")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.muted2)
                                .multilineTextAlignment(.center).lineSpacing(5)
                                .padding(.horizontal, 8).padding(.top, 120)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
                }
                .onChange(of: sess?.items.count) { _, _ in
                    withAnimation { proxy.scrollTo(sess?.running == true ? AnyHashable("running") : AnyHashable(sess?.items.last?.id), anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)

            composer
        }
        .background(Theme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0xE7E4DF)).frame(width: 1) }
    }

    private func chip(_ s: AgentSession, selected: Bool) -> some View {
        Button { model.activeSessionID = s.id } label: {
            HStack(spacing: 6) {
                Dot(color: s.agent.color, size: 6)
                    .opacity(s.source == .terminal && !s.alive ? 0.4 : 1)
                Text(s.title).font(.system(size: 12)).lineLimit(1)
                if s.source == .terminal {
                    Text("终端").font(.system(size: 10)).foregroundStyle(Theme.muted3)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xE9E6E1)))
                }
            }
            .foregroundStyle(Color(hex: 0x3D3A35))
            .padding(.horizontal, 10).frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(selected ? Color.white : .clear)
                    .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 1, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meta(_ s: AgentSession) -> String {
        var parts = [s.agent.displayName]
        if s.source == .terminal {
            parts.append("终端 pid \(s.pid.map(String.init) ?? "?")")
            parts.append(!s.alive ? "已结束" : model.watchTerminal ? "监听中" : "未监听")
        } else {
            parts.append("应用内会话")
            if let id = s.cliSessionID { parts.append(String(id.prefix(8))) }
        }
        if s.running { parts.append("运行中") }
        return parts.joined(separator: " · ")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let n = model.activeNote {
                    Text("@" + (n.rel as NSString).lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.chip))
                }
                Text("AGENTS.md").font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.chip))
            }
            .font(.system(size: 11)).foregroundStyle(Theme.text3)

            ZStack(alignment: .topLeading) {
                if model.agentInput.isEmpty {
                    Text("让 agent 修改当前笔记…  ↵ 发送").foregroundStyle(Theme.faint).allowsHitTesting(false)
                }
                TextField("", text: $model.agentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .focused($inputFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        send()
                        return .handled
                    }
            }
            .font(.system(size: 13))
            .lineSpacing(3)

            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(AgentKind.allCases, id: \.self) { k in
                        SegmentButton(label: k.displayName, on: model.agentPick == k, small: true) { model.agentPick = k }
                            .opacity(model.cli[k]?.found == false ? 0.5 : 1)
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chip))
                Spacer()
                DarkButton(title: "发送 ↵", height: 26, horizontal: 12, fill: Theme.accent, weight: .medium, action: send)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE3E0DA)))
        .padding(12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.panelLine).frame(height: 1) }
    }

    private func send() {
        model.runAgent(prompt: model.agentInput, agent: model.agentPick)
    }
}

struct ItemView: View {
    @Bindable var model: AppModel
    let item: SessionItem

    var body: some View {
        switch item.kind {
        case let .user(t):
            HStack {
                Spacer(minLength: 40)
                Text(t)
                    .font(.system(size: 13)).lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardLine))
            }
        case let .step(_, text, running):
            HStack(spacing: 8) {
                Circle().fill(running ? Theme.accent : Theme.slash).frame(width: 6, height: 6)
                    .background(Circle().fill(Theme.accent.opacity(running ? 0.15 : 0)).frame(width: 12, height: 12))
                Text(text).lineLimit(2)
            }
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(Color(hex: 0x7D786F))
        case let .agent(t):
            Text(t)
                .font(.system(size: 13)).lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .error(t):
            Text(t)
                .font(.system(size: 12)).lineSpacing(3)
                .foregroundStyle(Theme.delText)
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.delBg))
        case let .change(rel, plus, minus):
            let pendingNow = model.pending[rel] != nil
            HStack(spacing: 10) {
                FileGlyph()
                VStack(alignment: .leading, spacing: 2) {
                    Text((rel as NSString).lastPathComponent).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    HStack(spacing: 8) {
                        Text("+\(plus)").foregroundStyle(Theme.plus)
                        Text("−\(minus)").foregroundStyle(Theme.minus)
                        Text(pendingNow ? "待审阅" : "已处理").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if pendingNow {
                    DarkButton(title: "审阅") {
                        model.open(rel)
                        model.showDiff = true
                        model.zen = false
                    }
                } else if model.vault?.note(rel) != nil {
                    Button("打开") { model.open(rel) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardLine))
        }
    }
}
