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
                        .contextMenu { FolderMenu(model: model, folder: "") }
                        .dropDestination(for: String.self) { rels, _ in
                            rels.forEach { model.moveNote($0, to: "") }
                            return !rels.isEmpty
                        }
                }
            }
            Section("问库") {
                Button(action: model.newDesk) {
                    Label("向笔记库提问…", systemImage: "rectangle.stack.badge.person.crop")
                }
                .buttonStyle(.plain)
                ForEach(model.desks.filter { !$0.question.isEmpty }.prefix(6)) { d in
                    Label {
                        HStack {
                            Text(d.question).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(d.cards.filter { $0.state != .discarded }.count)").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "rectangle.stack") }
                    .tag("desk:" + d.id)
                    .contextMenu { Button("删除这个问题", systemImage: "trash", role: .destructive) { model.deleteDesk(d.id) } }
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
                    Button { model.newFolder(in: "") } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus").labelStyle(.iconOnly)
                    }
                    .help("新建文件夹 ⇧⌘N")
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

/// A folder's subfolders, then its notes. The folder note is the folder row itself.
struct FolderNodes: View {
    @Bindable var model: AppModel
    let vault: Vault
    let folder: String

    var body: some View {
        let node = vault.tree[folder]
        ForEach(node?.folders ?? [], id: \.self) { f in
            FolderRow(model: model, vault: vault, folder: f)
        }
        ForEach((node?.notes ?? []).filter { !vault.isFolderNote($0) }) { n in
            NoteRow(model: model, note: n, showFolder: false)
        }
    }
}

struct FolderRow: View {
    @Bindable var model: AppModel
    let vault: Vault
    let folder: String
    @State private var targeted = false

    var body: some View {
        let note = vault.folderNote(folder)
        DisclosureGroup(isExpanded: Binding(
            get: { model.openFolders.contains(folder) },
            set: { if $0 { model.openFolders.insert(folder) } else { model.openFolders.remove(folder) } }
        )) {
            FolderNodes(model: model, vault: vault, folder: folder)
        } label: {
            Label {
                if model.renaming == "dir:" + folder {
                    RenameField(model: model, key: "dir:" + folder, name: (folder as NSString).lastPathComponent) { name in
                        model.renameFolder(folder, to: name)
                    }
                } else {
                    Text((folder as NSString).lastPathComponent).lineLimit(1)
                }
            } icon: {
                Image(systemName: note != nil ? "folder.fill" : "folder")
                    .help(note != nil ? "点击打开文件夹笔记" : "")
            }
            .tag(note?.rel ?? "dir:" + folder)
            .background(targeted ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)) : nil)
            .contextMenu { FolderMenu(model: model, folder: folder) }
            .dropDestination(for: String.self) { rels, _ in
                rels.forEach { model.moveNote($0, to: folder) }
                return !rels.isEmpty
            } isTargeted: { targeted = $0 }
        }
    }
}

struct FolderMenu: View {
    @Bindable var model: AppModel
    let folder: String

    var body: some View {
        Button("新建笔记", systemImage: "square.and.pencil") { model.newNote(in: folder) }
        Button("新建文件夹", systemImage: "folder.badge.plus") { model.newFolder(in: folder) }
        if !folder.isEmpty {
            Button(model.vault?.folderNote(folder) != nil ? "打开文件夹笔记" : "创建文件夹笔记", systemImage: "doc.text") {
                model.openFolderNote(folder)
            }
            Divider()
            Button("重命名…", systemImage: "pencil") { model.renaming = "dir:" + folder }
        }
        Button("在 Finder 中显示", systemImage: "folder") {
            if let v = model.vault { NSWorkspace.shared.activateFileViewerSelecting([folder.isEmpty ? v.root : v.url(folder)]) }
        }
        if !folder.isEmpty {
            Divider()
            Button("移到废纸篓", systemImage: "trash", role: .destructive) { model.trashFolder(folder) }
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
                        RenameField(model: model, key: note.rel, name: note.title) { model.renameNote(note.rel, to: $0) }
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
            Image(systemName: note.isAgentFile ? "doc.badge.gearshape" : note.isHTML ? "globe" : "doc.text")
        }
        .tag(note.rel)
        .draggable(note.rel)
        .contextMenu {
            Button("在 Finder 中显示", systemImage: "folder") {
                if let v = model.vault { NSWorkspace.shared.activateFileViewerSelecting([v.url(note.rel)]) }
            }
            Button("重命名…", systemImage: "pencil") { model.renaming = note.rel }
                .disabled(model.writing.contains(note.rel))
            Menu("移动到", systemImage: "folder") {
                Button(model.vault?.name ?? "库根目录") { model.moveNote(note.rel, to: "") }
                    .disabled(note.folder.isEmpty)
                ForEach(model.vault?.folders ?? [], id: \.self) { f in
                    Button(f) { model.moveNote(note.rel, to: f) }.disabled(f == note.folder)
                }
            }
            if model.pending[note.rel] != nil {
                Button("审阅改动", systemImage: "checklist") { model.open(note.rel); model.showDiff = true }
            }
            Divider()
            ForEach(model.userCommands.filter { $0.scope == .note }.prefix(4), id: \.key) { c in
                Button(c.title, systemImage: c.icon) {
                    model.open(note.rel)
                    do { try model.runUserCommand(c, input: nil) } catch let e as RPCError { model.showToast(e.message) } catch {}
                }
            }
            Divider()
            Button("移到废纸篓", systemImage: "trash", role: .destructive) { model.trash(note.rel) }
        }
    }
}

/// A name edited in its sidebar row. Return or clicking away commits; Escape cancels.
/// An AppKit field: SwiftUI's never sees Escape, and can't take focus as its row appears.
struct RenameField: NSViewRepresentable {
    @Bindable var model: AppModel
    /// What `model.renaming` holds while this field is open.
    let key: String
    let name: String
    /// Returns false to keep the field open (the reason has been shown).
    let commit: (String) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: name)
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
            let m = parent.model
            guard !done, m.renaming == parent.key else { return }
            if text == parent.name || parent.commit(text) || !keepOpen {
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
            if !model.agentPanel { model.toggleAgent() }
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
