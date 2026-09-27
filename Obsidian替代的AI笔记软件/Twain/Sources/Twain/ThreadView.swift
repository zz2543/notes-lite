import AppKit
import TwainCore
import SwiftUI

/// A conversation in the middle of the window. Its draft sits in the side panel (`DraftPanel`).
struct ThreadView: View {
    @Bindable var model: AppModel
    let session: AgentSession

    var body: some View {
        AgentInspector(model: model, session: session)
            .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .navigationTitle(session.title)
            .navigationSubtitle(model.state(of: session).label)
            .toolbar {
                CommonTools(model: model)
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button("草稿", systemImage: "sidebar.trailing", action: model.toggleSidePanel)
                        .help("草稿 ⌘J")
                }
            }
    }
}

/// Beside a conversation: the note it is building. The agent writes it without review; the user
/// edits it freely; "完成草稿" turns it into an ordinary note and opens it as the page.
struct DraftPanel: View {
    @Bindable var model: AppModel
    let session: AgentSession

    var body: some View {
        let draft = session.draftRel
        let draftShown = draft != nil && model.activeRel == draft
        // A note the agent is writing (or just wrote) besides the draft, opened by "跟随写入".
        let followed = !draftShown && model.activeRel.map { rel in
            model.writing.contains(rel) || model.touched(session).contains(rel)
        } == true
        VStack(spacing: 0) {
            if draftShown || followed {
                NoteDetail(model: model, embedded: true)
                    .overlay(alignment: .top) {
                        if followed, let n = model.activeNote {
                            Banner(tint: Theme.agentColor(session.agent)) {
                                Image(systemName: "scope")
                            } text: {
                                Text("正在看 \(n.displayName)")
                            } action: {
                                if draft != nil {
                                    Button("回到草稿") { model.open(draft!) }
                                        .buttonStyle(.glass)
                                }
                            }
                            .padding(.top, Metrics.floatInset)
                        }
                    }
            } else {
                empty
            }
        }
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $model.followAgent) {
                    Label("跟随写入", systemImage: "scope")
                }
                .help(model.followAgent ? "Agent 写入别的笔记时，这里跟过去（点按关闭）" : "开启后，agent 写入的笔记会在这里打开")
                if draftShown {
                    Button("完成草稿", systemImage: "checkmark.circle") { model.finishDraft(session) }
                        .labelStyle(.titleAndIcon)
                        .help("草稿成为一篇普通笔记，在中间打开")
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("草稿").font(.title3.weight(.semibold))
            Text("对话里的结论可以收进这里，最后成为一篇笔记。也可以直接对 agent 说「写进草稿」，它会在这里写。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button("开始写草稿", systemImage: "square.and.pencil") { model.beginDraft(session) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Context shelf

/// What the next prompt carries, above the composer: the open note, notes pinned for this
/// conversation, and the selection in the page — each visible and removable before sending.
struct ContextShelf: View {
    @Bindable var model: AppModel
    var inThread = false
    @State private var picking = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if let n = model.activeNote {
                    Label(n.displayName, systemImage: inThread ? "doc.badge.ellipsis" : "doc.text")
                        .lineLimit(1).truncationMode(.middle)
                        .help(inThread ? "右侧打开的笔记：\(n.rel)" : "当前笔记：\(n.rel)。agent 知道你打开的是它")
                }
                ForEach(model.contextPins.filter { $0 != model.activeRel }, id: \.self) { rel in
                    Button { model.unpin(rel) } label: {
                        Label {
                            HStack(spacing: 3) {
                                Text(InboxView.name(rel)).lineLimit(1)
                                Image(systemName: "xmark").imageScale(.small).foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "pin.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("参考笔记：\(rel)（点按移除）")
                }
                if !inThread, let q = model.selectionPreview {
                    Button { model.quoteSelection.toggle() } label: {
                        Label("引用选区 · \(q.text.count) 字", systemImage: model.quoteSelection ? "text.quote" : "text.badge.xmark")
                            .strikethrough(!model.quoteSelection)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.quoteSelection ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .help(model.quoteSelection ? "会把 \(q.rel) 第 \(q.line) 行起选中的文字作为引用发送（点按不发送）" : "点按后把选中的文字一起发送")
                }
                Button { picking = true } label: {
                    Label("参考笔记", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .help("让 agent 参考库里的其他笔记")
                .popover(isPresented: $picking, arrowEdge: .top) {
                    NotePicker(model: model) { rel in
                        model.pin(rel)
                        picking = false
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(TagLabelStyle())
        }
        .scrollIndicators(.never)
        .animation(.snappy(duration: 0.2), value: model.selectionPreview)
        .animation(.snappy(duration: 0.2), value: model.contextPins)
    }
}

/// Finds a note by title to pin as context.
struct NotePicker: View {
    @Bindable var model: AppModel
    let pick: (String) -> Void
    @State private var query = ""

    private var matches: [NoteRef] {
        let notes = (model.vault?.notes ?? []).filter { $0.rel != model.activeRel && !model.contextPins.contains($0.rel) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return Array((q.isEmpty ? notes : notes.filter { $0.rel.lowercased().contains(q) }).prefix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("搜索笔记…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let first = matches.first { pick(first.rel) } }
            if matches.isEmpty {
                Text("没有匹配的笔记").font(.callout).foregroundStyle(.secondary).padding(8)
            }
            ForEach(matches) { n in
                Button { pick(n.rel) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        Text(n.displayName).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(n.folder).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 300)
    }
}

// MARK: - Replies into notes

/// Under the reply that closes a turn. In a conversation it goes into the draft; beside a page,
/// into that page. Either way it can also become a note of its own, or go to the clipboard.
struct ReplyActions: View {
    @Bindable var model: AppModel
    let session: AgentSession
    let text: String
    var inThread = false

    var body: some View {
        HStack(spacing: 14) {
            if inThread {
                Button("收进草稿", systemImage: "text.badge.plus") { model.takeIntoDraft(text, session) }
                    .help("把这段回复加到右侧草稿的末尾")
            } else {
                Button("插入笔记", systemImage: "text.insert") { model.insertIntoNote(text) }
                    .disabled(model.activeRel == nil)
                    .help(model.activeNote.map { "插入到 \($0.displayName) 光标所在段落之后（没有光标时放在末尾）" } ?? "先打开一篇笔记")
            }
            Button("存为笔记", systemImage: "doc.badge.plus") { model.saveAsNote(text, session: session) }
                .help("把这段回复存成一篇新笔记")
            Button("复制", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                model.showToast("已复制")
            }
            .help("复制 Markdown 原文")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Touched notes

/// The notes this session changed, each one click from its page or its review.
struct TouchedStrip: View {
    @Bindable var model: AppModel
    let session: AgentSession

    var body: some View {
        let rels = model.touched(session).filter { $0 != session.draftRel }
        if !rels.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Text("改动了").font(.caption).foregroundStyle(.secondary)
                    ForEach(rels, id: \.self) { rel in
                        let pending = model.pending[rel]
                        Button {
                            if pending != nil { model.review(rel) } else { model.peek(rel) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: pending != nil ? "doc.badge.clock" : "checkmark.circle")
                                    .foregroundStyle(pending != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                Text(InboxView.name(rel)).lineLimit(1)
                                if let pending { CountBadge(plus: pending.plus, minus: pending.minus) }
                            }
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(rel == model.activeRel ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.quaternary), in: .capsule)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .help(pending != nil ? "审阅 \(rel)" : "查看 \(rel)")
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.never)
        }
    }
}
