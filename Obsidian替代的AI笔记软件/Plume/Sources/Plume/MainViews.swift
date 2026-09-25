import PlumeCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let overlayAgent = geo.size.width < 1100
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if model.sidebar && !model.zen {
                        SidebarView(model: model)
                            .frame(width: 248)
                            .transition(.move(edge: .leading))
                    }
                    MainColumn(model: model)
                        .frame(maxWidth: .infinity)
                    if model.agentPanel && !model.zen && !overlayAgent {
                        AgentPanel(model: model).frame(width: 340)
                    }
                }
                if model.agentPanel && !model.zen && overlayAgent {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        AgentPanel(model: model)
                            .frame(width: min(340, geo.size.width - 24))
                            .shadow(color: .black.opacity(0.12), radius: 20, x: -12)
                    }
                }
                if model.palette { CommandPalette(model: model) }
                if model.settings { SettingsOverlay(model: model) }
                if model.onboardingStep != nil { OnboardingOverlay(model: model) }
                if let t = model.toast {
                    VStack {
                        Spacer()
                        Text(t)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.toast))
                            .shadow(color: .black.opacity(0.2), radius: 15, y: 10)
                            .padding(.bottom, 48)
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.18), value: model.toast)
        .animation(.easeOut(duration: 0.2), value: model.sidebar)
        .animation(.easeOut(duration: 0.2), value: model.zen)
        .background(WindowConfigurator(zen: model.zen))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: model.toggleSidebar) { SidebarIcon().frame(width: 28, height: 24) }
                    .buttonStyle(.hover(.black.opacity(0.06)))
                    .help("隐藏侧边栏 ⌘\\")
            }
            .padding(.leading, 16).padding(.trailing, 14)
            .frame(height: 52)

            Button(action: model.openPalette) {
                HStack(spacing: 8) {
                    SearchIcon(size: 13, color: Theme.muted2)
                    Text("搜索笔记与命令").font(.system(size: 12.5)).foregroundStyle(Theme.muted2)
                    Spacer()
                    Text("⌘K").font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
            }
            .buttonStyle(.hover(.black.opacity(0.075), base: .black.opacity(0.05), radius: 7))
            .padding(.horizontal, 10).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("库 · \(model.vault?.name ?? "Vault")")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 5)
                    if let v = model.vault {
                        FolderContents(model: model, vault: v, folder: "", depth: 0)
                    }
                }
                .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 10)
            }

            VStack(spacing: 1) {
                agentRow(.claude)
                agentRow(.codex)
                Button { model.openSettings(.agent) } label: {
                    HStack(spacing: 8) {
                        Text("⇄").font(.system(size: 11)).foregroundStyle(Theme.muted2).frame(width: 7)
                        Text("AGENTS.md · CLAUDE.md").font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text(model.contextInSync ? "同源" : "未同源").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 8).frame(height: 26)
                }
                .buttonStyle(.hover)
            }
            .padding(8)
            .overlay(alignment: .top) { Rectangle().fill(Theme.sidebarLine).frame(height: 1) }

            HStack(spacing: 6) {
                Button(action: model.newNote) {
                    Text("新建笔记").font(.system(size: 12.5)).frame(maxWidth: .infinity).frame(height: 28)
                }
                .buttonStyle(.hover(.black.opacity(0.09), base: .black.opacity(0.06), radius: 7))
                Button { model.openSettings(.editor) } label: {
                    Text("设置").font(.system(size: 12.5)).padding(.horizontal, 12).frame(height: 28)
                }
                .buttonStyle(.hover(.black.opacity(0.09), base: .black.opacity(0.06), radius: 7))
            }
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 12)
        }
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.sidebarLine).frame(width: 1) }
    }

    private func agentRow(_ k: AgentKind) -> some View {
        let info = model.cli[k]
        let terminals = model.sessions.filter { $0.agent == k && $0.source == .terminal && $0.alive }.count
        let status: String = {
            if info == nil { return "检测中…" }
            if info?.found != true { return "未安装" }
            if !model.agentEnabled(k) { return "已停用" }
            if model.sessions.contains(where: { $0.agent == k && $0.source == .app && $0.running }) { return "运行中" }
            return terminals > 0 ? "终端会话 \(terminals)" : "已连接"
        }()
        return Button { model.openSettings(.agent) } label: {
            HStack(spacing: 8) {
                Dot(color: k.color).opacity(info?.found == true ? 1 : 0.35)
                Text(k.displayName).font(.system(size: 12))
                Spacer()
                Text(status).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8).frame(height: 26)
        }
        .buttonStyle(.hover)
    }
}

struct FolderContents: View {
    @Bindable var model: AppModel
    let vault: Vault
    let folder: String
    let depth: Int

    var body: some View {
        let subfolders = vault.folders.filter { ($0 as NSString).deletingLastPathComponent == folder }
        let files = vault.notes.filter { $0.folder == folder }
        ForEach(subfolders, id: \.self) { f in
            let open = model.openFolders.contains(f)
            TreeRow(selected: false, depth: depth, action: {
                if open { model.openFolders.remove(f) } else { model.openFolders.insert(f) }
            }) {
                Text("›").font(.system(size: 14)).foregroundStyle(Theme.muted)
                    .frame(width: 10)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .animation(.easeOut(duration: 0.15), value: open)
                Text((f as NSString).lastPathComponent).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            if open {
                FolderContents(model: model, vault: vault, folder: f, depth: depth + 1)
            }
        }
        ForEach(files) { n in
            TreeRow(selected: n.rel == model.activeRel, depth: depth, action: { model.open(n.rel) }) {
                FileGlyph().padding(.leading, 1).padding(.trailing, 2)
                Text(n.displayName).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if model.writing.contains(n.rel) {
                    Text("写入中…").font(.system(size: 10.5)).foregroundStyle(Theme.claude)
                }
                if let p = model.pending[n.rel] {
                    Dot(color: p.by?.color ?? Theme.muted)
                        .help("\(agentLabel(p.by)) 改动待审阅")
                }
            }
        }
    }
}

struct TreeRow<Content: View>: View {
    let selected: Bool
    let depth: Int
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(.system(size: 13, weight: selected ? .medium : .regular))
            .padding(.leading, 8 + CGFloat(depth) * 14)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.black.opacity(0.075) : .clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

// MARK: - Main column

struct MainColumn: View {
    @Bindable var model: AppModel

    var body: some View {
        let pend = model.activePending
        let isDiff = model.showDiff && pend != nil
        VStack(spacing: 0) {
            if !model.zen { HeaderBar(model: model, isDiff: isDiff) }
            if isDiff, let pend {
                DiffScreen(model: model, review: pend)
            } else {
                if let pend, !model.zen { PendingBanner(model: model, review: pend) }
                if let rel = model.activeRel, model.writing.contains(rel) { WritingBanner(model: model) }
                EditorArea(model: model)
            }
            StatusBar(model: model)
        }
        .background(Theme.paper)
        .overlay(alignment: .topTrailing) {
            if model.zen {
                ZenExitButton(action: model.toggleZen).padding(.top, 14).padding(.trailing, 16)
            }
        }
    }
}

struct ZenExitButton: View {
    let action: () -> Void
    @State private var over = false
    var body: some View {
        Button(action: action) {
            Text("退出专注 ⌘.")
                .font(.system(size: 11.5))
                .foregroundStyle(over ? Theme.muted3 : Color(hex: 0xB0ABA3))
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(over ? Color.black.opacity(0.04) : .clear))
        }
        .buttonStyle(.plain)
        .opacity(over ? 1 : 0.7)
        .onHover { over = $0 }
    }
}

struct HeaderBar: View {
    @Bindable var model: AppModel
    let isDiff: Bool

    var body: some View {
        HStack(spacing: 10) {
            if !model.sidebar {
                Color.clear.frame(width: 62)
                Button(action: model.toggleSidebar) { SidebarIcon().frame(width: 28, height: 24) }
                    .buttonStyle(.hover)
                    .help("显示侧边栏 ⌘\\")
            }
            HStack(spacing: 6) {
                Text(model.activeNote?.folder.isEmpty == false ? model.activeNote!.folder : (model.vault?.name ?? "Vault"))
                    .foregroundStyle(Theme.muted)
                Text("/").foregroundStyle(Theme.slash)
                Text(model.activeNote?.displayName ?? "").fontWeight(.semibold)
                if isDiff {
                    Text("审阅改动").font(.system(size: 11)).foregroundStyle(Theme.muted3)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.chip))
                }
            }
            .font(.system(size: 13))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            Button(action: model.openPalette) { SearchIcon().frame(width: 30, height: 26) }
                .buttonStyle(.hover)
                .help("⌘K")
            Button(action: model.toggleAgent) {
                HStack(spacing: 6) {
                    Text("Agent").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color(hex: 0x3D3A35))
                    if !model.pending.isEmpty {
                        Text("\(model.pending.count)")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(Theme.claude))
                    }
                }
                .padding(.horizontal, 10).frame(height: 26)
            }
            .buttonStyle(.hover(.black.opacity(0.07), base: model.agentPanel ? .black.opacity(0.07) : .clear))
            .help("Agent 面板 ⌘J")
        }
        .padding(.leading, 14).padding(.trailing, 12)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

struct PendingBanner: View {
    @Bindable var model: AppModel
    let review: PendingReview

    var body: some View {
        HStack(spacing: 10) {
            Dot(color: review.by?.color ?? Theme.muted, size: 8)
            Text("\(agentLabel(review.by)) \(review.source == .terminal ? "在终端中" : "在 Plume 中")修改了此文件 · \(review.hunks.count) 处改动待审阅")
                .foregroundStyle(Theme.text2).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            DarkButton(title: "审阅") { model.showDiff = true }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(Color(hex: 0xF6F4F0))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xECE9E4)).frame(height: 1) }
    }
}

struct WritingBanner: View {
    @Bindable var model: AppModel
    var body: some View {
        let agent = model.sessions.first { $0.running && $0.source == .app }?.agent
        HStack(spacing: 10) {
            Dot(color: Theme.claude)
            Text("\(agent?.displayName ?? "Agent") 正在写入此文件，完成后可以继续编辑")
            Spacer()
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.writingText)
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(Theme.writingBg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.writingLine).frame(height: 1) }
    }
}

struct EditorArea: View {
    @Bindable var model: AppModel

    var body: some View {
        EditorView(model: model)
            .overlay(alignment: .topLeading) {
                if let s = model.slash {
                    SlashMenu(model: model, state: s)
                        .offset(x: s.anchor.x, y: s.anchor.y)
                }
            }
            .clipped()
    }
}

struct SlashMenu: View {
    @Bindable var model: AppModel
    let state: SlashState

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.items.enumerated()), id: \.element.id) { i, item in
                let sel = i == min(state.selection, state.items.count - 1)
                HStack(spacing: 10) {
                    Text(item.label).frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.hint).font(.system(size: 11, design: .monospaced)).opacity(0.6)
                }
                .foregroundStyle(sel ? .white : item.ai.map { $0 == .claude ? Theme.claudeText : Theme.codex } ?? Theme.ink)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(sel ? Theme.accent : .clear))
                .contentShape(Rectangle())
                .onTapGesture { NotificationCenter.default.post(name: .plumeApplySlash, object: item) }
                .onHover { if $0 { model.slash?.selection = i } }
            }
        }
        .font(.system(size: 13))
        .padding(5)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xFCFBF9).opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 12)
    }
}

extension Notification.Name {
    static let plumeApplySlash = Notification.Name("plumeApplySlash")
}

// MARK: - Review

struct DiffScreen: View {
    @Bindable var model: AppModel
    let review: PendingReview

    var body: some View {
        let name = ((model.activeRel ?? "") as NSString).lastPathComponent
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Dot(color: review.by?.color ?? Theme.muted, size: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agentLabel(review.by)) \(review.source == .terminal ? "在终端中" : "在 Plume 中")修改了 \(name)")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("+\(review.plus) −\(review.minus) · 文件已在磁盘上改动，还原会恢复到写入前的版本")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.showDiff = false } label: {
                    Text("稍后").foregroundStyle(Theme.muted3).padding(.horizontal, 12).frame(height: 28)
                }
                .buttonStyle(.hover(.black.opacity(0.05), radius: 7))
                OutlineButton(title: "全部还原", height: 28, horizontal: 12, size: 13) { model.finishReview(all: .rejected) }
                DarkButton(title: "接受并写入", height: 28, horizontal: 14, weight: .medium) { model.finishReview(all: nil) }
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xECE9E4)).frame(height: 1) }

            ScrollView {
                let rows = LineDiff.rows(base: review.baseline, hunks: review.hunks)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        DiffRowView(model: model, row: row, review: review)
                    }
                }
                .font(Font(model.font.nsFont(size: 15)))
                .lineSpacing(15 * 0.75 - 4)
                .frame(maxWidth: model.editorWidth + 40)
                .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 120)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
        }
    }
}

struct DiffRowView: View {
    @Bindable var model: AppModel
    let row: DiffRow
    let review: PendingReview

    var body: some View {
        switch row {
        case let .context(t):
            line(mark: "·", markColor: Color(hex: 0xCFCAC2), text: t, color: Theme.muted3, bg: .clear)
        case let .deleted(t):
            line(mark: "−", markColor: Theme.delText, text: t, color: Theme.delText, bg: Theme.delBg, strike: true)
        case let .added(t):
            line(mark: "+", markColor: Theme.addText, text: t, color: Theme.addText, bg: Theme.addBg)
        case let .bar(i):
            let h = review.hunks[i]
            HStack(spacing: 8) {
                Text("改动 \(i + 1) · +\(h.add.count) −\(h.del)").frame(maxWidth: .infinity, alignment: .leading)
                if h.state == .pending {
                    OutlineButton(title: "还原") { model.setHunk(i, .rejected) }
                    DarkButton(title: "接受", horizontal: 10, fill: Theme.accent) { model.setHunk(i, .accepted) }
                } else {
                    Text(h.state == .accepted ? "已接受" : "已还原").foregroundStyle(Theme.text2)
                    Button("撤销") { model.setHunk(i, .pending) }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).padding(.horizontal, 8)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted2)
            .padding(.leading, 32)
            .padding(.top, 6).padding(.bottom, 18)
        }
    }

    private func line(mark: String, markColor: Color, text: String, color: Color, bg: Color, strike: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(mark).foregroundStyle(markColor).frame(width: 22, alignment: .leading)
            Text(text.isEmpty ? " " : text)
                .strikethrough(strike, color: Theme.delText.opacity(0.45))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(bg))
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @Bindable var model: AppModel
    @State private var over = false

    var body: some View {
        HStack(spacing: 10) {
            Text(pathLabel)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                .lineLimit(1).truncationMode(.middle)
                .layoutPriority(-1)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                PillToggle(label: "打字机", on: model.typewriter) { model.typewriter.toggle() }
                PillToggle(label: "聚焦", on: model.dim) { model.dim.toggle() }
                PillToggle(label: "Tab 续写", on: model.ghostOn) { model.ghostOn.toggle() }
                Rectangle().fill(Theme.sidebarLine).frame(width: 1, height: 12).padding(.horizontal, 6)
                ForEach(EditorFont.allCases) { f in
                    SegmentButton(label: f.shortLabel, on: model.font == f, small: true) { model.font = f }
                }
                Rectangle().fill(Theme.sidebarLine).frame(width: 1, height: 12).padding(.horizontal, 6)
                PillToggle(label: model.zen ? "退出专注" : "专注 ⌘.", on: model.zen, action: model.toggleZen)
            }
            .fixedSize()
            Spacer(minLength: 0)
            Text(model.stats)
                .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.muted2)
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(model.zen ? .clear : Theme.hairline).frame(height: 1) }
        .opacity(model.zen && !over ? 0 : 1)
        .animation(.easeOut(duration: 0.3), value: over)
        .onHover { over = $0 }
    }

    private var pathLabel: String {
        guard let v = model.vault, let rel = model.activeRel else { return "" }
        return v.displayPath + "/" + rel + (model.dirty ? " · 编辑中" : " · 已保存")
    }
}
