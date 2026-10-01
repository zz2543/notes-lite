import TwainCore
import SwiftUI

/// The detail column: the page itself, or the review of an agent's changes to it.
///
/// Split into small views that each read only what they show: opening a note changes a dozen
/// properties, and a view is only redrawn when one it read changes. The title, the toolbar,
/// the banners and the floating controls no longer redraw with the page around them.
struct NoteDetail: View {
    @Bindable var model: AppModel

    var body: some View {
        let pend = model.activePending
        let reviewing = model.editor.showDiff && pend != nil
        Group {
            if let space = model.currentSpace {
                SpaceView(model: model, plugin: space)
                    .transition(.page(from: .leading))
            } else if let desk = model.currentDesk {
                ResearchDeskView(model: model, desk: desk)
                    .transition(.page(from: .leading))
            } else if reviewing, let pend {
                ReviewView(model: model, review: pend)
                    .transition(.page(from: .top))
            } else {
                // The text view only fades: scaling or blurring it would rasterize the whole note.
                NotePage(model: model)
                    .transition(.opacity)
            }
        }
        .motion(Motion.morph ?? Motion.standard, value: PageKind(space: model.chrome.activeSpace, desk: model.chrome.openDesk, reviewing: reviewing))
        // The page takes whatever width the split view gives it. Letting its content report a
        // minimum width feeds back into the column sizes, and a width-dependent layout (the
        // dashboards) can then keep re-solving the window until AppKit aborts.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        // One continuous sheet of paper from the window's top edge down; the toolbar
        // floats on it as glass instead of sitting on its own band.
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .modifier(DetailTitle(model: model))
        .toolbar { NoteToolbar(model: model, reviewing: reviewing) }
    }

    /// Which kind of page is showing; switching kinds cross-fades, switching notes does not.
    private struct PageKind: Equatable {
        var space: String?
        var desk: String?
        var reviewing: Bool
    }
}

private struct DetailTitle: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .navigationTitle(model.currentSpace?.name ?? (model.currentDesk != nil ? "问库" : model.activeNote?.displayName ?? "共笔"))
            .navigationSubtitle(model.currentSpace.map { _ in "空间" } ?? model.currentDesk.map { $0.question.isEmpty ? "新问题" : $0.question }
                                ?? model.activeNote.map { $0.folder.isEmpty ? (model.vault?.name ?? "") : $0.folder } ?? "")
    }
}

/// The open note: its text, or why it can't be shown.
private struct NotePage: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.editor.downloading != nil {
            ProgressView("正在从 iCloud 下载这篇笔记…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else if let why = model.editor.unreadable {
            ContentUnavailableView {
                Label("无法作为笔记打开", systemImage: "doc.questionmark")
            } description: {
                Text(why)
            } actions: {
                Button("在 Finder 中显示") {
                    if let v = model.vault, let rel = model.editor.activeRel { NSWorkspace.shared.activateFileViewerSelecting([v.url(rel)]) }
                }
            }
        } else if let n = model.activeNote, n.isHTML, !model.editor.htmlSource, let v = model.vault {
            HTMLNoteView(url: v.url(n.rel), root: v.root, version: model.editor.editorVersion)
                .overlay(alignment: .top) { Banners(model: model) }
        } else {
            EditorView(model: model)
                // The page runs under the toolbar; the text view keeps its own top margin.
                .overlay(alignment: .topLeading) { OutlineRail(model: model) }
                .overlay(alignment: .topLeading) { SlashLayer(model: model) }
                .overlay(alignment: .top) { Banners(model: model) }
                .overlay(alignment: .bottomTrailing) { StatusLayer(model: model) }
                .overlay(alignment: .topTrailing) { CompanionLayer(model: model) }
                .overlay(alignment: .topTrailing) { ZenExit(model: model) }
        }
    }
}

private struct SlashLayer: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let s = model.editor.slash {
                SlashMenu(model: model, state: s).offset(x: s.anchor.x, y: s.anchor.y)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
            }
        }
        .motion(Motion.quick, value: model.editor.slash != nil)
    }
}

private struct StatusLayer: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if !model.chrome.zen {
                VStack(alignment: .trailing, spacing: 0) {
                    AgentIsland(model: model)
                    StatusPill(model: model)
                }
                .padding(Metrics.floatInset)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .motion(Motion.standard, value: model.chrome.zen)
    }
}

private struct CompanionLayer: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let tip = model.editor.companionTip, tip.rel == model.editor.activeRel {
                CompanionBubble(model: model, tip: tip)
                    .padding(.top, 64).padding(.trailing, Metrics.floatInset)
                    .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity).combined(with: .offset(x: 24)))
            }
        }
        .motion(Motion.standard, value: model.editor.companionTip)
    }
}

private struct ZenExit: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if model.chrome.zen {
                Button("退出专注", systemImage: "arrow.down.right.and.arrow.up.left", action: model.toggleZen)
                    .buttonStyle(.soft)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                    .padding(18)
                    .opacity(0.7)
                    .transition(.opacity)
            }
        }
        .motion(Motion.standard, value: model.chrome.zen)
    }
}

/// What the page wants the user to know: an agent's change to review, a read-only note, a write in progress.
private struct Banners: View {
    @Bindable var model: AppModel

    var body: some View {
        let pending = model.activePending
        let writingHere = model.editor.activeRel.map { model.agents.writing.contains($0) } ?? false
        ZStack(alignment: .top) {
            if !model.chrome.zen {
                Group {
                    VStack(spacing: 8) {
                        if let pending {
                            Banner(tint: pending.by.map(Theme.agentColor) ?? .secondary) {
                                Image(systemName: "doc.badge.clock")
                            } text: {
                                let where_ = pending.source == .terminal ? "在终端中" : pending.source == .automation ? "在自动化中" : "在共笔中"
                                let what = pending.isProposal ? (pending.isNew ? "提议新建此文件" : "提议修改此文件") : "\(where_)修改了此文件"
                                // Counts roll to their new value rather than blinking.
                                Text("\(agentLabel(pending.by)) \(what) \(Text("· \(pending.hunks.count) 处改动待审阅").foregroundStyle(.secondary))")
                                    .contentTransition(.numericText())
                                    .motion(Motion.quick, value: pending.hunks.count)
                            } action: {
                                Button("审阅") { model.editor.showDiff = true }
                                    .buttonStyle(.solid)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if model.editor.oversized {
                            Banner(tint: .secondary) {
                                Image(systemName: "text.alignleft")
                            } text: {
                                Text("含有极长的行（如内嵌 base64 图片）\(Text(" · 以纯文本只读显示").foregroundStyle(.secondary))")
                            } action: {
                                Button("在 Finder 中显示") {
                                    if let v = model.vault, let rel = model.editor.activeRel { NSWorkspace.shared.activateFileViewerSelecting([v.url(rel)]) }
                                }
                                .buttonStyle(.soft)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if writingHere {
                            let agent = model.agents.sessions.first { $0.running && $0.source == .app }?.agent
                            Banner(tint: agent.map(Theme.agentColor) ?? Theme.claude) {
                                GlyphSpinner(activity: .write, tint: agent.map(Theme.agentColor) ?? Theme.claude)
                            } text: {
                                Text("\(agent?.displayName ?? "Agent") 正在写入此文件，完成后可以继续编辑")
                            } action: {
                                EmptyView()
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .padding(.top, Metrics.floatInset)
                .padding(.horizontal, 24)
                .transition(.opacity)
            }
        }
        .motion(Motion.standard, value: BannerState(hunks: pending?.hunks.count, oversized: model.editor.oversized, writing: writingHere))
    }

    private struct BannerState: Equatable {
        var hunks: Int?
        var oversized: Bool
        var writing: Bool
    }
}

/// A floating glass capsule that announces something about the open page.
struct Banner<Icon: View, Message: View, Action: View>: View {
    let tint: Color
    @ViewBuilder let icon: Icon
    @ViewBuilder let text: Message
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 10) {
            icon.foregroundStyle(tint)
            text.lineLimit(1)
            action.controlSize(.small)
        }
        .font(.callout)
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .frame(minHeight: 40)
        .capsuleSurface(tint: tint.opacity(0.12))
    }
}

/// Save state and word count, floating in the page's corner.
struct StatusPill: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            if let v = model.vault, let rel = model.editor.activeRel { NSWorkspace.shared.activateFileViewerSelecting([v.url(rel)]) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.editor.dirty ? AnyShapeStyle(.orange) : AnyShapeStyle(.green.opacity(0.8)))
                    .frame(width: 6, height: 6)
                    .motion(Motion.quick, value: model.editor.dirty)
                // Not rolled: a transition in the glass capsule costs ~1 ms on keys that flip it.
                Text(model.editor.dirty ? "编辑中" : "已保存")
                if model.prefs.companionOn {
                    ZStack {
                        if model.editor.companionThinking {
                            GlyphSpinner(activity: .think).transition(.blurReplace)
                        } else {
                            Image(systemName: "sparkle").foregroundStyle(.tint).transition(.blurReplace)
                        }
                    }
                    .motion(Motion.quick, value: model.editor.companionThinking)
                }
                // The pace covers the last minute: only this text redraws on a timer.
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Text(model.stats).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .hoverGlassCapsule(interactive: true)
        .help((model.editor.activeRel ?? "") + " · 在 Finder 中显示")
        .disabled(model.editor.activeRel == nil)
    }
}

// MARK: - Toolbar

private struct NoteToolbar: ToolbarContent {
    @Bindable var model: AppModel
    let reviewing: Bool

    var body: some ToolbarContent {
        if model.currentDesk != nil || model.currentSpace != nil {
            ToolbarItem(placement: .primaryAction) {
                Button("返回笔记", systemImage: "doc.text") {
                    model.chrome.openDesk = nil
                    model.chrome.activeSpace = nil
                    if let rel = model.editor.activeRel { model.chrome.selection = rel }
                }
                .help("回到刚才的笔记")
            }
        } else if reviewing {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("稍后", systemImage: "clock") { model.editor.showDiff = false }
                    .help("稍后审阅 ⎋")
                let proposal = model.activePending?.isProposal == true
                Button(proposal ? "全部拒绝" : "全部还原", systemImage: "arrow.uturn.backward") { model.finishReview(all: .rejected) }
                    .labelStyle(.titleAndIcon)
                    .help(proposal ? "不采纳这份提案，文件保持不变" : "还原到 agent 写入前的版本")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("接受并写入", systemImage: "checkmark") { model.finishReview(all: nil) }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            if !model.agents.pending.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: model.reviewNext) {
                        let n = model.agents.pending.values.reduce(0) { $0 + $1.hunks.count }
                        Label("审阅 \(n) 处改动", systemImage: "checklist")
                            .labelStyle(.titleAndIcon)
                            .contentTransition(.numericText())
                            .motion(Motion.quick, value: n)
                    }
                    .buttonStyle(.glassProminent)
                    .help("审阅 agent 的改动 ⇧⌘R")
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            if model.activeNote?.isHTML == true {
                ToolbarItem(placement: .primaryAction) {
                    Button(model.editor.htmlSource ? "预览" : "源码", systemImage: model.editor.htmlSource ? "eye" : "chevron.left.forwardslash.chevron.right") {
                        model.flushSave()
                        model.editor.htmlSource.toggle()
                    }
                    .help(model.editor.htmlSource ? "显示渲染后的页面" : "编辑 HTML 源码")
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("AI 审阅", systemImage: "text.bubble") { model.startAIReview() }
                    .help("让 \(model.agents.agentPick.displayName) 通读这篇笔记，在正文旁留下批注，不改动笔记")
                    .disabled(model.editor.activeRel == nil || model.activeNote?.isHTML == true)
                Button("笔记信息", systemImage: "info.circle") {
                    model.chrome.panelOrigin = clickPoint()
                    model.chrome.noteInfoOpen.toggle()
                }
                    .help("笔记的名片：摘要、标签、反链")
                    .disabled(model.editor.activeRel == nil || model.activeNote?.isHTML == true)
                Button("专注模式", systemImage: "arrow.up.left.and.arrow.down.right", action: model.toggleZen)
                    .help("专注模式 ⌘.")
                Button("命令面板", systemImage: "magnifyingglass", action: model.openPalette)
                    .help("搜索笔记与命令 ⌘K")
            }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button("Agent", systemImage: "sidebar.trailing", action: model.toggleAgent)
                .help("Agent 面板 ⌘J")
        }
    }
}

// MARK: - Slash menu

struct SlashMenu: View {
    @Bindable var model: AppModel
    let state: SlashState
    @Namespace private var highlight

    static func icon(_ key: String) -> String {
        ["h1": "textformat.size.larger", "h2": "textformat.size", "h3": "textformat.size.smaller", "list": "list.bullet",
         "todo": "checklist", "quote": "text.quote", "hr": "minus", "claude": "sparkle", "codex": "terminal"][key] ?? "textformat"
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(state.items.enumerated()), id: \.element.id) { i, item in
                let sel = i == min(state.selection, state.items.count - 1)
                if item.ai != nil, i > 0, state.items[i - 1].ai == nil { Divider().padding(.vertical, 3).padding(.horizontal, 8) }
                HStack(spacing: 10) {
                    Image(systemName: item.icon ?? Self.icon(item.key))
                        .frame(width: 18)
                        .foregroundStyle(sel ? AnyShapeStyle(.white) : item.ai.map { AnyShapeStyle(Theme.agentColor($0)) } ?? AnyShapeStyle(.secondary))
                    Text(item.label).frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.hint).font(.caption.monospaced())
                        .foregroundStyle(sel ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                }
                .foregroundStyle(sel ? .white : .primary)
                .padding(.horizontal, 10).frame(height: 30)
                .slidingHighlight(sel, in: highlight)
                .contentShape(.rect)
                .onTapGesture { NotificationCenter.default.post(name: .twainApplySlash, object: item) }
                .onHover { if $0 { model.editor.slash?.selection = i } }
            }
        }
        .padding(6)
        .frame(width: 260)
        .motion(Motion.quick, value: state.selection)
        .surface(radius: Metrics.cardRadius)
    }
}

extension Notification.Name {
    static let twainApplySlash = Notification.Name("twainApplySlash")
}
