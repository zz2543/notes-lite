import PlumeCore
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            DetailView(model: model)
                .inspector(isPresented: $model.agentPanel) {
                    AgentInspector(model: model)
                        .inspectorColumnWidth(min: 300, ideal: 340, max: 520)
                }
        }
        .toolbar(model.zen ? .hidden : .automatic, for: .windowToolbar)
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: model.toggleSidebar) {
                    Label("显示或隐藏边栏", systemImage: "sidebar.left")
                }
                .plumeGlassButton()
                .help("显示或隐藏边栏 ⌃⌘S")
            }
        }
        .overlay {
            if model.palette { CommandPalette(model: model) }
        }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator.opacity(0.6)))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .padding(.bottom, 44)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.toast)
        .sheet(isPresented: Binding(get: { model.onboardingStep != nil }, set: { if !$0 { model.onboardingStep = nil } })) {
            OnboardingSheet(model: model)
        }
        .onAppear { model.openSettingsAction = { openSettings() } }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            if let v = model.vault {
                Section(v.name) {
                    let q = model.sidebarFilter.trimmingCharacters(in: .whitespaces)
                    if q.isEmpty {
                        FolderNodes(model: model, vault: v, folder: "")
                    } else {
                        ForEach(v.notes.filter { $0.rel.localizedCaseInsensitiveContains(q) }) { n in
                            NoteRow(model: model, note: n, showFolder: true)
                        }
                    }
                }
            }
            Section("Agent") {
                ForEach(AgentKind.allCases, id: \.self) { k in AgentStatusRow(model: model, kind: k) }
                Button { model.openSettings(.agent) } label: {
                    HStack {
                        Label("共享规则", systemImage: "link")
                            .help("AGENTS.md 是唯一的规则来源，CLAUDE.md 只引用它")
                        Spacer()
                        Text(model.contextInSync ? "同源" : "未同源").foregroundStyle(.secondary).font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.sidebarFilter, placement: .sidebar, prompt: "搜索笔记")
        .safeAreaInset(edge: .bottom) {
            PlumeGlassControls {
                HStack {
                    Button(action: model.newNote) { Label("新建笔记", systemImage: "square.and.pencil") }
                        .plumeGlassButton()
                        .help("新建笔记 ⌘N")
                    Spacer()
                    Button { model.openSettings(.agent) } label: { Image(systemName: "gearshape") }
                        .plumeGlassButton()
                        .help("设置 ⌘,")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }
}

struct FolderNodes: View {
    @Bindable var model: AppModel
    let vault: Vault
    let folder: String

    var body: some View {
        ForEach(vault.folders.filter { ($0 as NSString).deletingLastPathComponent == folder }, id: \.self) { f in
            DisclosureGroup(isExpanded: Binding(
                get: { model.openFolders.contains(f) },
                set: { if $0 { model.openFolders.insert(f) } else { model.openFolders.remove(f) } }
            )) {
                FolderNodes(model: model, vault: vault, folder: f)
            } label: {
                Label((f as NSString).lastPathComponent, systemImage: "folder")
            }
        }
        ForEach(vault.notes.filter { $0.folder == folder }) { n in
            NoteRow(model: model, note: n, showFolder: false)
        }
    }
}

struct NoteRow: View {
    @Bindable var model: AppModel
    let note: NoteRef
    let showFolder: Bool

    var body: some View {
        HStack(spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.displayName).lineLimit(1)
                    if showFolder, !note.folder.isEmpty {
                        Text(note.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: note.isAgentFile ? "doc.badge.gearshape" : "doc.text")
            }
            Spacer(minLength: 0)
            if model.writing.contains(note.rel) {
                ProgressView().controlSize(.mini).help("Agent 正在写入")
            } else if let p = model.pending[note.rel] {
                Circle().fill(p.by.map(Theme.agentColor) ?? .secondary).frame(width: 7, height: 7)
                    .help("\(agentLabel(p.by)) 的改动待审阅")
            }
        }
        .tag(note.rel)
        .contextMenu {
            Button("在 Finder 中显示") {
                if let v = model.vault { NSWorkspace.shared.activateFileViewerSelecting([v.url(note.rel)]) }
            }
            if model.pending[note.rel] != nil {
                Button("审阅改动") { model.open(note.rel); model.showDiff = true }
            }
            Divider()
            Button("让 Claude Code 总结") { model.open(note.rel); model.runAgent(prompt: "总结这篇笔记，在开头加一段摘要", agent: .claude) }
            Divider()
            Button("移到废纸篓", role: .destructive) { model.trash(note.rel) }
        }
    }
}

struct AgentStatusRow: View {
    @Bindable var model: AppModel
    let kind: AgentKind

    var body: some View {
        let info = model.cli[kind]
        let terminals = model.sessions.filter { $0.agent == kind && $0.source == .terminal && $0.alive }.count
        let running = model.sessions.contains { $0.agent == kind && $0.source == .app && $0.running }
        let status: String = {
            guard let info else { return "检测中…" }
            if !info.found { return "未安装" }
            if !model.agentEnabled(kind) { return "已停用" }
            if running { return "运行中" }
            return terminals > 0 ? "终端 \(terminals)" : "就绪"
        }()
        Button {
            model.agentPick = kind
            if !model.agentPanel { model.toggleAgent() }
        } label: {
            HStack {
                Label {
                    Text(kind.displayName)
                } icon: {
                    Image(systemName: kind == .claude ? "sparkle" : "terminal")
                        .foregroundStyle(info?.found == true ? Theme.agentColor(kind) : .secondary)
                }
                Spacer()
                if running { ProgressView().controlSize(.mini) }
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

func agentLabel(_ a: AgentKind?) -> String { a?.displayName ?? "外部程序" }

// MARK: - Detail

struct DetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        let pend = model.activePending
        let isDiff = model.showDiff && pend != nil
        VStack(spacing: 0) {
            if isDiff, let pend {
                DiffView(model: model, review: pend)
            } else {
                if let pend, !model.zen {
                    InfoBar(tint: pend.by.map(Theme.agentColor) ?? .secondary, systemImage: "doc.badge.clock",
                            text: "\(agentLabel(pend.by)) \(pend.source == .terminal ? "在终端中" : "在 Plume 中")修改了此文件 · \(pend.hunks.count) 处改动待审阅") {
                        Button("审阅") { model.showDiff = true }
                            .plumePrimaryButton().controlSize(.small)
                    }
                }
                if let rel = model.activeRel, model.writing.contains(rel) {
                    let agent = model.sessions.first { $0.running && $0.source == .app }?.agent
                    InfoBar(tint: Theme.claude, systemImage: nil, text: "\(agent?.displayName ?? "Agent") 正在写入此文件，完成后可以继续编辑") {
                        ProgressView().controlSize(.small)
                    }
                }
                EditorView(model: model)
                    .overlay(alignment: .topLeading) {
                        if let s = model.slash {
                            SlashMenu(model: model, state: s).offset(x: s.anchor.x, y: s.anchor.y)
                        }
                    }
                    .ignoresSafeArea(.container, edges: model.zen ? .top : [])
            }
            if !model.zen { StatusBar(model: model) }
        }
        .navigationTitle(model.activeNote?.displayName ?? "Plume")
        .navigationSubtitle(model.activeNote.map { $0.folder.isEmpty ? (model.vault?.name ?? "") : $0.folder } ?? "")
        .toolbar { toolbar(isDiff: isDiff) }
        .overlay(alignment: .topTrailing) {
            if model.zen {
                Button("退出专注", action: model.toggleZen)
                    .plumeGlassButton().controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .padding(14)
                    .opacity(0.6)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(isDiff: Bool) -> some ToolbarContent {
        if !model.pending.isEmpty && !isDiff {
            ToolbarItem(placement: .primaryAction) {
                Button(action: model.reviewNext) {
                    Label("审阅 \(model.pending.count) 处改动", systemImage: "checklist")
                        .labelStyle(.titleAndIcon)
                }
                .plumePrimaryButton()
                .help("审阅 agent 的改动")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: model.toggleZen) { Label("专注模式", systemImage: "arrow.up.left.and.arrow.down.right") }
                .plumeGlassButton()
                .help("专注模式 ⌘.")
            Button(action: model.openPalette) { Label("命令面板", systemImage: "magnifyingglass") }
                .plumeGlassButton()
                .help("搜索笔记与命令 ⌘K")
            Button(action: model.toggleAgent) { Label("Agent", systemImage: "sidebar.right") }
                .plumeGlassButton()
                .help("Agent 面板 ⌘J")
        }
    }
}

struct InfoBar<Trailing: View>: View {
    let tint: Color
    let systemImage: String?
    let text: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(tint)
                } else {
                    Circle().fill(tint).frame(width: 8, height: 8)
                }
                Text(text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.bar)
            Divider()
        }
    }
}

struct StatusBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if let rel = model.activeRel {
                    Button {
                        if let v = model.vault { NSWorkspace.shared.activateFileViewerSelecting([v.url(rel)]) }
                    } label: {
                        Text(rel).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中显示")
                    Text(model.dirty ? "编辑中" : "已保存").foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Text(model.stats).monospacedDigit().lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(.bar)
        }
    }
}

// MARK: - Slash menu

struct SlashMenu: View {
    @Bindable var model: AppModel
    let state: SlashState

    static func icon(_ key: String) -> String {
        ["h1": "textformat.size.larger", "h2": "textformat.size", "h3": "textformat.size.smaller", "list": "list.bullet",
         "todo": "checklist", "quote": "text.quote", "hr": "minus", "claude": "sparkle", "codex": "terminal"][key] ?? "textformat"
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.items.enumerated()), id: \.element.id) { i, item in
                let sel = i == min(state.selection, state.items.count - 1)
                HStack(spacing: 8) {
                    Image(systemName: Self.icon(item.key))
                        .frame(width: 18)
                        .foregroundStyle(sel ? AnyShapeStyle(.white) : item.ai.map { AnyShapeStyle(Theme.agentColor($0)) } ?? AnyShapeStyle(.secondary))
                    Text(item.label).frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.hint).font(.caption.monospaced()).foregroundStyle(sel ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                }
                .foregroundStyle(sel ? .white : .primary)
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(sel ? Color.accentColor : .clear))
                .contentShape(Rectangle())
                .onTapGesture { NotificationCenter.default.post(name: .plumeApplySlash, object: item) }
                .onHover { if $0 { model.slash?.selection = i } }
            }
        }
        .padding(5)
        .frame(width: 250)
        .plumeControlGlass(in: RoundedRectangle(cornerRadius: 13))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }
}

extension Notification.Name {
    static let plumeApplySlash = Notification.Name("plumeApplySlash")
}

// MARK: - Review

struct DiffView: View {
    @Bindable var model: AppModel
    let review: PendingReview

    var body: some View {
        let name = ((model.activeRel ?? "") as NSString).lastPathComponent
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.clock").font(.title2).foregroundStyle(review.by.map(Theme.agentColor) ?? .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agentLabel(review.by)) \(review.source == .terminal ? "在终端中" : "在 Plume 中")修改了 \(name)")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text("+\(review.plus)").foregroundStyle(.green)
                        Text("−\(review.minus)").foregroundStyle(.red)
                        Text("· 文件已在磁盘上改动，还原会恢复到写入前的版本")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("稍后") { model.showDiff = false }
                    .keyboardShortcut(.cancelAction)
                Button("全部还原") { model.finishReview(all: .rejected) }
                Button("接受并写入") { model.finishReview(all: nil) }
                    .plumePrimaryButton()
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.bar)
            Divider()

            ScrollView {
                let rows = LineDiff.rows(base: review.baseline, hunks: review.hunks)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        DiffRowView(model: model, row: row, review: review)
                    }
                }
                .font(Font(model.font.nsFont(size: 15)))
                .frame(maxWidth: model.editorWidth + 40)
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 80)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
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
            line(" ", t, fg: .secondary, bg: .clear)
        case let .deleted(t):
            line("−", t, fg: .red, bg: .red.opacity(0.1), strike: true)
        case let .added(t):
            line("+", t, fg: .primary, bg: .green.opacity(0.14), markColor: .green)
        case let .bar(i):
            let h = review.hunks[i]
            HStack(spacing: 8) {
                Text("改动 \(i + 1) · +\(h.add.count) −\(h.del)")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if h.state == .pending {
                    Button("还原") { model.setHunk(i, .rejected) }
                    Button("接受") { model.setHunk(i, .accepted) }.plumePrimaryButton()
                } else {
                    Label(h.state == .accepted ? "已接受" : "已还原",
                          systemImage: h.state == .accepted ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                        .font(.caption).foregroundStyle(h.state == .accepted ? .green : .secondary)
                    Button("撤销") { model.setHunk(i, .pending) }.buttonStyle(.link).font(.caption)
                }
            }
            .controlSize(.small)
            .padding(.leading, 30)
            .padding(.top, 6).padding(.bottom, 16)
        }
    }

    private func line(_ mark: String, _ text: String, fg: Color, bg: Color, markColor: Color? = nil, strike: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(mark).foregroundStyle(markColor ?? fg).frame(width: 20, alignment: .leading)
            Text(text.isEmpty ? " " : text)
                .strikethrough(strike, color: .red.opacity(0.5))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(bg))
    }
}
