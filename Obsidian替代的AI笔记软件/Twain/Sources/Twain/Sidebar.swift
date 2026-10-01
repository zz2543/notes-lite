import TwainCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: Bindable(model.chrome).selection) {
            if model.vault != nil {
                Section("空间") {
                    ForEach(model.spaces, id: \.id) { p in
                        Label(p.name, systemImage: p.icon).tag("space:" + p.id)
                            .contextMenu {
                                Button("停用", systemImage: "pause.circle") { model.setPluginEnabled(p, false) }
                            }
                    }
                    Button {
                        model.chrome.panelOrigin = clickPoint()
                        model.chrome.newSpaceSheet = true
                    } label: {
                        Label("新建空间…", systemImage: "plus.square.dashed").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let v = model.vault {
                Section {
                    let q = model.chrome.sidebarFilter.trimmingCharacters(in: .whitespaces)
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
                            let kept = d.cards.filter { $0.state != .discarded }.count
                            Text("\(kept)").font(.caption).foregroundStyle(.secondary)
                                .contentTransition(.numericText()).motion(Motion.quick, value: kept)
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
            guard model.chrome.renaming == nil, let rel = model.chrome.selection, model.vault?.note(rel) != nil else { return .ignored }
            model.chrome.renaming = rel
            return .handled
        }
        .searchable(text: Bindable(model.chrome).sidebarFilter, placement: .sidebar, prompt: "搜索笔记")
        .safeAreaBar(edge: .bottom) { NewBar(model: model) }
    }
}

/// The sidebar's bottom bar. 新建笔记 stays one click away; the other ways to start something
/// live behind 「+」, whose surface grows in place into a small panel and shrinks back into
/// the button when you pick one — the panel opens where you clicked and goes back there.
private struct NewBar: View {
    @Bindable var model: AppModel
    @Namespace private var morph
    /// The pointer is on 「+」: its surface rises a little.
    @State private var plusHover = false
    private var open: Bool {
        get { model.chrome.newMenuOpen }
        nonmutating set { model.chrome.newMenuOpen = newValue }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if open {
                panel
                    .background { SurfaceFill(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)).matchedGeometryEffect(id: "new", in: morph) }
                    .closesOnOutsideClick(Binding(get: { open }, set: { v in withMotion(Motion.morph) { open = v } }))
            }
            HStack(spacing: 8) {
                Button(action: model.newNote) {
                    Label("新建笔记", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.soft)
                .help("新建笔记 ⌘N")
                Button {
                    // The click that just closed the panel from outside must not reopen it.
                    if GrowPanelClock.justClosed { return }
                    withMotion(Motion.morph) { open.toggle() }
                } label: {
                    Image(systemName: open ? "xmark" : "plus").font(.body.weight(.medium))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 34, height: 34)
                        .background {
                            if !open { SurfaceFill(shape: RoundedRectangle(cornerRadius: 17, style: .continuous), lift: plusHover ? 1 : 0).matchedGeometryEffect(id: "new", in: morph) }
                            else { SurfaceFill(shape: Circle()) }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .onHover { h in withMotion(Motion.quick) { plusHover = h } }
                .help(open ? "收起" : "新建文件夹、空间或问题")
                Button { model.openSettings(.agent) } label: {
                    Label("设置", systemImage: "gearshape").labelStyle(.iconOnly)
                }
                .buttonStyle(.soft)
                .help("设置 ⌘,")
            }
            .controlSize(.large)
        }
        .padding(.horizontal, Metrics.floatInset).padding(.bottom, Metrics.floatInset)
        .onExitCommand { if open { withMotion(Motion.morph) { open = false } } }
    }

    private var panel: some View {
        let items: [(String, String, String, () -> Void)] = [
            ("folder.badge.plus", "新建文件夹", "⇧⌘N", { model.newFolder(in: "") }),
            ("plus.square.dashed", "新建空间…", "", { model.chrome.panelOrigin = clickPoint(); model.chrome.newSpaceSheet = true }),
            ("rectangle.stack.badge.person.crop", "向笔记库提问…", "", model.newDesk),
        ]
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button {
                    withMotion(Motion.morph) { open = false }
                    item.3()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.0).frame(width: 20).foregroundStyle(.secondary)
                        Text(item.1)
                        Spacer(minLength: 0)
                        Text(item.2).font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(NewItemStyle())
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(Motion.stagger(i, Motion.quick), value: open)
            }
        }
        .padding(6)
    }

    private struct NewItemStyle: ButtonStyle {
        @State private var hover = false
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(hover || configuration.isPressed ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                            in: .rect(cornerRadius: Metrics.rowRadius, style: .continuous))
                .onHover { hover = $0 }
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
            get: { model.chrome.openFolders.contains(folder) },
            set: { open in withMotion { if open { model.chrome.openFolders.insert(folder) } else { model.chrome.openFolders.remove(folder) } } }
        )) {
            FolderNodes(model: model, vault: vault, folder: folder)
        } label: {
            Label {
                if model.chrome.renaming == "dir:" + folder {
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
            .background(alignment: .leading) { TreeGuides(depth: folder.split(separator: "/").count - 1) }
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
            Button("重命名…", systemImage: "pencil") { model.chrome.renaming = "dir:" + folder }
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
                    if model.chrome.renaming == note.rel {
                        RenameField(model: model, key: note.rel, name: note.title) { model.renameNote(note.rel, to: $0) }
                    } else {
                        Text(note.displayName).lineLimit(1)
                    }
                    if showFolder, !note.folder.isEmpty {
                        Text(note.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    if model.agents.writing.contains(note.rel) {
                        GlyphSpinner(activity: .write).help("Agent 正在写入")
                            .transition(.opacity)
                    } else if let p = model.agents.pending[note.rel] {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(p.by.map(Theme.agentColor) ?? .secondary)
                            .help("\(agentLabel(p.by)) 的改动待审阅")
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .motion(Motion.pop, value: model.agents.writing.contains(note.rel) ? 2 : model.agents.pending[note.rel] != nil ? 1 : 0)
            }
        } icon: {
            Image(systemName: note.isAgentFile ? "doc.badge.gearshape" : note.isHTML ? "globe" : "doc.text")
        }
        .background(alignment: .leading) {
            if !showFolder { TreeGuides(depth: note.folder.isEmpty ? 0 : note.folder.split(separator: "/").count) }
        }
        .tag(note.rel)
        .draggable(note.rel)
        .contextMenu {
            Button("在 Finder 中显示", systemImage: "folder") {
                if let v = model.vault { NSWorkspace.shared.activateFileViewerSelecting([v.url(note.rel)]) }
            }
            Button("重命名…", systemImage: "pencil") { model.chrome.renaming = note.rel }
                .disabled(model.agents.writing.contains(note.rel))
            Menu("移动到", systemImage: "folder") {
                Button(model.vault?.name ?? "库根目录") { model.moveNote(note.rel, to: "") }
                    .disabled(note.folder.isEmpty)
                ForEach(model.vault?.folders ?? [], id: \.self) { f in
                    Button(f) { model.moveNote(note.rel, to: f) }.disabled(f == note.folder)
                }
            }
            if model.agents.pending[note.rel] != nil {
                Button("审阅改动", systemImage: "checklist") { model.open(note.rel); model.editor.showDiff = true }
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
    /// What `model.chrome.renaming` holds while this field is open.
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

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
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
                parent.model.chrome.renaming = nil
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
            guard !done, m.chrome.renaming == parent.key else { return }
            if text == parent.name || parent.commit(text) || !keepOpen {
                done = true
                m.chrome.renaming = nil
            }
        }
    }
}

struct AgentStatusRow: View {
    @Bindable var model: AppModel
    let kind: AgentKind

    var body: some View {
        let info = model.agents.cli[kind]
        let terminals = model.agents.sessions.filter { $0.agent == kind && $0.source == .terminal && $0.alive }.count
        let running = model.agents.sessions.contains { $0.agent == kind && $0.source == .app && $0.running }
        let status: String = {
            guard let info else { return "检测中…" }
            if !info.found { return "未安装" }
            if !model.agentEnabled(kind) { return "已停用" }
            if running { return "运行中" }
            return terminals > 0 ? "终端 \(terminals)" : "就绪"
        }()
        Button {
            model.agents.agentPick = kind
            if !model.chrome.agentPanel { model.toggleAgent() }
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    if running { GlyphSpinner(activity: .think, tint: Theme.agentColor(kind)).transition(.blurReplace) }
                    RollingText(text: status)
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

/// Thin vertical lines in a nested row's indent, one per enclosing folder, so a deep tree shows
/// what belongs to what. Each row draws its own stretch and the stretches meet into lines.
/// Rows don't read the selection for this: every row would then redraw on every note switch.
struct TreeGuides: View {
    /// Indentation the sidebar adds per level, and where the parent's chevron sits relative to
    /// a row's label (measured on macOS 26's source list).
    static let indent: CGFloat = 12

    let depth: Int
    /// From the label's leading edge back to the innermost line, which runs under the parent
    /// folder's chevron (measured on macOS 26's source list; notes and folders start alike).
    let lead: CGFloat = 19

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<max(depth, 0), id: \.self) { k in
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .offset(x: -(lead + CGFloat(depth - 1 - k) * Self.indent))
            }
        }
        // Past the label's own height, so the stretches of neighbouring rows meet.
        .padding(.vertical, -12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
