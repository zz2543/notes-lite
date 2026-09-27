import TwainCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            if let v = model.vault {
                Section {
                    let q = model.sidebarFilter.trimmingCharacters(in: .whitespaces)
                    if q.isEmpty {
                        FolderNodes(model: model, vault: v, folder: "")
                    } else {
                        let hits = v.notes.filter { $0.rel.localizedCaseInsensitiveContains(q) }
                        ForEach(hits) { n in NoteRow(model: model, note: n, showFolder: true) }
                        if hits.isEmpty {
                            Text("没有匹配「\(q)」的笔记").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label(v.name, systemImage: "books.vertical")
                }
            }
            Section("Agent") {
                ForEach(AgentKind.allCases, id: \.self) { k in AgentStatusRow(model: model, kind: k) }
                Button { model.openSettings(.agent) } label: {
                    LabeledContent {
                        Text(model.contextInSync ? "同源" : "未同源")
                    } label: {
                        Label("共享规则", systemImage: model.contextInSync ? "link" : "link.badge.plus")
                    }
                }
                .buttonStyle(.plain)
                .help("AGENTS.md 是唯一的规则来源，CLAUDE.md 只引用它")
            }
        }
        .listStyle(.sidebar)
        // Return renames the selected note, as in Finder.
        .onKeyPress(.return) {
            guard model.renaming == nil, let rel = model.selection, model.vault?.note(rel) != nil else { return .ignored }
            model.renaming = rel
            return .handled
        }
        .searchable(text: $model.sidebarFilter, placement: .sidebar, prompt: "搜索笔记")
        .safeAreaBar(edge: .bottom) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: model.newNote) {
                        Label("新建笔记", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .help("新建笔记 ⌘N")
                    Button { model.openSettings(.agent) } label: {
                        Label("设置", systemImage: "gearshape").labelStyle(.iconOnly)
                    }
                    .help("设置 ⌘,")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
            .padding(.horizontal, Metrics.floatInset).padding(.bottom, Metrics.floatInset)
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
        Label {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    if model.renaming == note.rel {
                        RenameField(model: model, note: note)
                    } else {
                        Text(note.displayName).lineLimit(1)
                    }
                    if showFolder, !note.folder.isEmpty {
                        Text(note.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if model.writing.contains(note.rel) {
                    ProgressView().controlSize(.mini).help("Agent 正在写入")
                } else if let p = model.pending[note.rel] {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(p.by.map(Theme.agentColor) ?? .secondary)
                        .help("\(agentLabel(p.by)) 的改动待审阅")
                }
            }
        } icon: {
            Image(systemName: note.isAgentFile ? "doc.badge.gearshape" : "doc.text")
        }
        .tag(note.rel)
        .contextMenu {
            Button("在 Finder 中显示", systemImage: "folder") {
                if let v = model.vault { NSWorkspace.shared.activateFileViewerSelecting([v.url(note.rel)]) }
            }
            Button("重命名…", systemImage: "pencil") { model.renaming = note.rel }
                .disabled(model.writing.contains(note.rel))
            if model.pending[note.rel] != nil {
                Button("审阅改动", systemImage: "checklist") { model.open(note.rel); model.showDiff = true }
            }
            Divider()
            Button("让 Claude Code 总结", systemImage: "sparkle") {
                model.open(note.rel)
                model.runAgent(prompt: "总结这篇笔记，在开头加一段摘要", agent: .claude)
            }
            Divider()
            Button("移到废纸篓", systemImage: "trash", role: .destructive) { model.trash(note.rel) }
        }
    }
}

/// The note's name, editable in its row. Return or clicking away renames; Escape cancels.
/// An AppKit field: SwiftUI's never sees Escape, and can't take focus as its row appears.
struct RenameField: NSViewRepresentable {
    @Bindable var model: AppModel
    let note: NoteRef

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: note.title)
        f.delegate = context.coordinator
        f.bezelStyle = .roundedBezel
        f.lineBreakMode = .byTruncatingTail
        f.cell?.isScrollable = true
        // Becoming first responder selects the whole name, as Finder does.
        DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        private var done = false

        init(_ parent: RenameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                finish(control.stringValue, keepOpen: true)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                done = true
                parent.model.renaming = nil
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            finish(f.stringValue, keepOpen: false)
        }

        /// A rejected name keeps the field open after Return; clicking away just drops it.
        private func finish(_ text: String, keepOpen: Bool) {
            let m = parent.model, note = parent.note
            guard !done, m.renaming == note.rel else { return }
            if text == note.title || m.renameNote(note.rel, to: text) || !keepOpen {
                done = true
                m.renaming = nil
            }
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
            model.revealAgent()
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    if running { ProgressView().controlSize(.mini) }
                    Text(status)
                }
            } label: {
                Label {
                    Text(kind.displayName)
                } icon: {
                    Image(systemName: Theme.agentSymbol(kind))
                        .foregroundStyle(info?.found == true ? Theme.agentColor(kind) : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
