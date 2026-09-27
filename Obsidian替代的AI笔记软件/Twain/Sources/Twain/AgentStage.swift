import AppKit
import TwainCore
import SwiftUI

/// The agent workspace's middle: the conversation on a sheet of paper, the page panel beside it.
struct AgentStage: View {
    @Bindable var model: AppModel

    var body: some View {
        AgentInspector(model: model, stage: true)
            .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .navigationTitle(model.activeSession?.title ?? "Agent")
            .navigationSubtitle(model.vault?.name ?? "")
            .toolbar {
                if !model.pending.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: model.reviewNext) {
                            Label("审阅 \(model.pending.values.reduce(0) { $0 + $1.hunks.count }) 处改动", systemImage: "checklist")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.glassProminent)
                        .help("在右侧审阅 agent 的改动 ⇧⌘R")
                    }
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("命令面板", systemImage: "magnifyingglass", action: model.openPalette)
                        .help("搜索笔记与命令 ⌘K")
                    Button("笔记面板", systemImage: "sidebar.trailing", action: model.toggleSidePanel)
                        .help("笔记面板 ⌘J")
                }
            }
    }
}

// MARK: - Context shelf

/// What the next prompt carries, above the composer: the open note, notes pinned for this
/// session, and the selection in the page — each visible and removable before sending.
struct ContextShelf: View {
    @Bindable var model: AppModel
    @State private var picking = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if let n = model.activeNote {
                    Label(n.displayName, systemImage: "doc.text")
                        .lineLimit(1).truncationMode(.middle)
                        .help("当前笔记：\(n.rel)。agent 知道你打开的是它")
                }
                ForEach(model.contextPins.filter { $0 != model.activeRel }, id: \.self) { rel in
                    Button { model.unpin(rel) } label: {
                        Label {
                            HStack(spacing: 3) {
                                Text(((rel as NSString).lastPathComponent as NSString).deletingPathExtension).lineLimit(1)
                                Image(systemName: "xmark").imageScale(.small).foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "pin.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("参考笔记：\(rel)（点按移除）")
                }
                if let q = model.selectionPreview {
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

/// Under the reply that closes a turn: keep it in the open note, as a note of its own, or on the clipboard.
struct ReplyActions: View {
    @Bindable var model: AppModel
    let session: AgentSession
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Button("插入笔记", systemImage: "text.insert") { model.insertIntoNote(text) }
                .disabled(model.activeRel == nil)
                .help(model.activeNote.map { "插入到 \($0.displayName) 的光标处（没有光标时放在末尾）" } ?? "先打开一篇笔记")
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
        let rels = model.touched(session)
        if !rels.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Text("本次改动").font(.caption).foregroundStyle(.secondary)
                    ForEach(rels, id: \.self) { rel in
                        let pending = model.pending[rel]
                        Button {
                            if pending != nil { model.review(rel) } else { model.open(rel); model.revealNote() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: pending != nil ? "doc.badge.clock" : "checkmark.circle")
                                    .foregroundStyle(pending != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                Text(((rel as NSString).lastPathComponent as NSString).deletingPathExtension).lineLimit(1)
                                if let pending { CountBadge(plus: pending.plus, minus: pending.minus) }
                            }
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(rel == model.activeRel ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.quaternary), in: .capsule)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .help(pending != nil ? "审阅 \(rel)" : "打开 \(rel)")
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.never)
        }
    }
}
