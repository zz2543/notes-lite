import TwainCore
import SwiftUI

/// The page itself, or the review of an agent's changes to it. Usually the middle of the window;
/// `embedded`, it is the draft beside a conversation, which leaves reviews to the middle.
struct NoteDetail: View {
    @Bindable var model: AppModel
    var embedded = false

    var body: some View {
        let pend = model.activePending
        let reviewing = model.showDiff && pend != nil && !embedded
        let content = Group {
            if reviewing, let pend {
                ReviewView(model: model, review: pend)
            } else if embedded, model.activeRel == nil {
                ContentUnavailableView("没有打开的笔记", systemImage: "doc.text",
                                       description: Text("从侧栏选一篇笔记，或者让 agent 写一篇。它写入的笔记会在这里打开。"))
            } else {
                page(pending: pend)
            }
        }
        // One continuous sheet of paper from the window's top edge down; the toolbar
        // floats on it as glass instead of sitting on its own band.
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        if embedded {
            content
        } else {
            content
                .toolbar { toolbar(reviewing: reviewing) }
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .navigationTitle(model.activeNote?.displayName ?? "共笔")
                .navigationSubtitle(model.activeNote.map { $0.folder.isEmpty ? (model.vault?.name ?? "") : $0.folder } ?? "")
        }
    }

    private func page(pending: PendingReview?) -> some View {
        EditorView(model: model)
            // The page runs under the toolbar; the text view keeps its own top margin.
            .overlay(alignment: .topLeading) {
                if let s = model.slash {
                    SlashMenu(model: model, state: s).offset(x: s.anchor.x, y: s.anchor.y)
                }
            }
            .overlay(alignment: .top) {
                if !model.zen { banners(pending: pending) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !model.zen { StatusPill(model: model).padding(Metrics.floatInset) }
            }
            .overlay(alignment: .bottomLeading) {
                if embedded, let n = model.activeNote {
                    Label(n.displayName, systemImage: "doc.text")
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glassCapsule()
                        .padding(Metrics.floatInset)
                        .help(n.rel)
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.zen {
                    Button("退出专注", systemImage: "arrow.down.right.and.arrow.up.left", action: model.toggleZen)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .keyboardShortcut(.cancelAction)
                        .padding(18)
                        .opacity(0.7)
                }
            }
            .animation(.snappy(duration: 0.25), value: pending?.hunks.count)
    }

    @ViewBuilder
    private func banners(pending: PendingReview?) -> some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                if let pending {
                    Banner(tint: pending.by.map(Theme.agentColor) ?? .secondary) {
                        Image(systemName: "doc.badge.clock")
                    } text: {
                        let where_ = pending.source == .terminal ? "在终端中" : pending.source == .automation ? "在自动化中" : "在共笔中"
                        let what = pending.isProposal ? (pending.isNew ? "提议新建此文件" : "提议修改此文件") : "\(where_)修改了此文件"
                        Text("\(agentLabel(pending.by)) \(what) \(Text("· \(pending.hunks.count) 处改动待审阅").foregroundStyle(.secondary))")
                    } action: {
                        Button("审阅") { model.review(pending.rel) }
                            .buttonStyle(.glassProminent)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let rel = model.activeRel, model.writing.contains(rel) {
                    let agent = model.sessions.first { $0.running && $0.source == .app }?.agent
                    Banner(tint: agent.map(Theme.agentColor) ?? Theme.claude) {
                        ProgressView().controlSize(.small)
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
        .glassCapsule(tint: tint.opacity(0.12))
    }
}

/// Save state and word count, floating in the page's corner.
struct StatusPill: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            if let v = model.vault, let rel = model.activeRel { NSWorkspace.shared.activateFileViewerSelecting([v.url(rel)]) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.dirty ? AnyShapeStyle(.orange) : AnyShapeStyle(.green.opacity(0.8)))
                    .frame(width: 6, height: 6)
                Text(model.dirty ? "编辑中" : "已保存")
                Text(model.stats).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .help((model.activeRel ?? "") + " · 在 Finder 中显示")
        .disabled(model.activeRel == nil)
    }
}

// MARK: - Toolbar

extension NoteDetail {
    @ToolbarContentBuilder
    fileprivate func toolbar(reviewing: Bool) -> some ToolbarContent {
        if reviewing {
            if let p = model.reviewProgress {
                ToolbarItem(placement: .primaryAction) {
                    Text("第 \(p.index) / \(p.total) 篇").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .help("处理完这篇会自动打开下一篇；全部处理完回到刚才的位置")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("稍后", systemImage: "clock") {
                    if model.reviewReturn != nil { model.endReviewFlow(done: false) } else { model.showDiff = false }
                }
                .help(model.reviewReturn != nil ? "稍后再审阅，回到刚才的位置" : "稍后审阅")
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
            CommonTools(model: model)
            ToolbarItemGroup(placement: .primaryAction) {
                Button("专注模式", systemImage: "arrow.up.left.and.arrow.down.right", action: model.toggleZen)
                    .help("专注模式 ⌘.")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("旁注", systemImage: "sidebar.trailing", action: model.toggleSidePanel)
                .help("Agent 旁注 ⌘J")
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
                .background(RowHighlight(on: sel))
                .contentShape(.rect)
                .onTapGesture { NotificationCenter.default.post(name: .twainApplySlash, object: item) }
                .onHover { if $0 { model.slash?.selection = i } }
            }
        }
        .padding(6)
        .frame(width: 260)
        .floatingGlass(radius: Metrics.cardRadius)
    }
}

extension Notification.Name {
    static let twainApplySlash = Notification.Name("twainApplySlash")
}
