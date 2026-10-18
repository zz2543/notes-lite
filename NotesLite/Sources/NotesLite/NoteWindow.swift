import AppKit
import NotesCore
import SwiftUI

private enum PromptKind: String {
    case folder = "新建文件夹", rename = "重命名笔记", move = "移动笔记", copy = "保存副本"
}

private enum SpaceSheetKind: Identifiable {
    case create, edit(String)
    var id: String { switch self { case .create: "create"; case .edit(let name): "edit:" + name } }
}

private enum LibraryLocation: Equatable {
    case all, recent, folder(String)
}

struct NoteWindow: View {
    @Bindable var workspace: Workspace
    @AppStorage("navigation.mode") private var navigationMode: NavigationMode = .split
    @AppStorage("navigation.showAll") private var showAll = true
    @AppStorage("navigation.showRecent") private var showRecent = true
    @State private var searchQuery = ""
    @State private var searchLocal = false
    @State private var searchFolder = ""
    @State private var searchOpen = false
    @State private var searchResponder: NSResponder?
    @State private var prompt: PromptKind?
    @State private var promptValue = ""
    @State private var promptError: String?
    @State private var discardConfirmation = false
    @State private var backdrop: GlassBackdrop?
    @State private var glassImpulse = GlassImpulse()
    @State private var edgeBackdrop: GlassBackdrop?
    @State private var edgeImpulse = GlassImpulse()
    @State private var edgeVisible = false
    @State private var edgeTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @AppStorage("layout.sidebarWidth") private var sidebarWidth = 208.0
    @AppStorage("layout.listWidth") private var listWidth = 280.0
    @AppStorage("editor.font") private var editorFont: EditorFont = .sans
    @State private var expandedFolders: Set<String> = []
    @AppStorage("sidebar.mode") private var sidebarMode: SidebarMode = .library
    @State var spaces = SpaceStore()
    @State private var spaceSheet: SpaceSheetKind?
    @State private var changeToken: UUID?
    @State private var showOperationLog = false
    @Namespace private var navigationSelection
    @Namespace private var noteSelection
    @Namespace private var spaceSelection
    @Namespace private var spaceTreeSelection
    private var inSpaces: Bool { sidebarMode == .spaces }
    private var unified: Bool { navigationMode == .unified && !inSpaces }
    private var spaceNotes: [Note] { spaces.current.map { SpaceTree.notes(workspace.notes, in: $0.scope) } ?? [] }
    private var newTarget: String { workspace.creationFolder.isEmpty ? "笔记库根目录" : workspace.creationFolder }
    private var searchResults: [Note] { workspace.searchNotes(searchQuery, in: searchLocal ? searchFolder : nil) }
    private var listTitle: String { inSpaces ? (spaces.current.map { $0.icon + " " + $0.name } ?? "空间") : workspace.recentsOnly ? "最近打开" : workspace.selectedFolder.map { $0.isEmpty ? "笔记库" : ($0 as NSString).lastPathComponent } ?? "全部笔记" }
    private var navigationID: LibraryLocation {
        if workspace.recentsOnly { return .recent }
        return workspace.selectedFolder.map(LibraryLocation.folder) ?? .all
    }
    var body: some View {
        GeometryReader { geometry in
            let widths = unified
                ? ColumnWidths(sidebar: min(380, max(240, sidebarWidth)), list: 0)
                : ColumnWidths.fitting(total: geometry.size.width, sidebar: sidebarWidth, list: listWidth)
            VStack(spacing: 0) {
                header(widths: widths)
                    .frame(height: workspace.focus ? 0 : 52, alignment: .top).clipped()
                    .opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                HStack(spacing: 0) {
                    library.frame(width: widths.sidebar)
                        .frame(width: workspace.focus ? 0 : widths.sidebar, alignment: .leading).clipped()
                        .opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                    ColumnDivider(width: Binding(get: { widths.sidebar }, set: { sidebarWidth = $0 }), limits: (unified ? 240 : 180)...min(unified ? 380 : 280, max(unified ? 240 : 180, geometry.size.width - widths.list - 322)), label: "调整侧栏宽度")
                        .frame(width: workspace.focus ? 0 : 1).opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                    noteList.frame(width: widths.list)
                        .frame(width: workspace.focus || unified ? 0 : widths.list, alignment: .leading).clipped()
                        .opacity(workspace.focus || unified ? 0 : 1).allowsHitTesting(!workspace.focus && !unified).accessibilityHidden(workspace.focus || unified)
                    ColumnDivider(width: Binding(get: { widths.list }, set: { listWidth = $0 }), limits: 220...min(380, max(220, geometry.size.width - widths.sidebar - 322)), label: "调整笔记列表宽度")
                        .frame(width: workspace.focus || unified ? 0 : 1).opacity(workspace.focus || unified ? 0 : 1).allowsHitTesting(!workspace.focus && !unified).accessibilityHidden(workspace.focus || unified)
                    editor.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .leading) {
                if edgeVisible {
                    GlassSurface(backdrop: edgeBackdrop, impulse: edgeImpulse)
                        .frame(width: 20).offset(x: workspace.focus ? -10 : widths.sidebar + widths.list - 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                        .animation(Motion.panel, value: workspace.focus)
                }
            }
            .overlay(alignment: .topTrailing) {
                tool(workspace.focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                     workspace.focus ? "退出专注" : "进入专注模式") { setFocus(!workspace.focus) }
                    .foregroundStyle(.secondary)
                    .frame(height: 52)
                    .padding(.trailing, 18)
            }
        }
        .background(Color.paper)
        .ignoresSafeArea(.container, edges: .top)
        .onExitCommand {
            if workspace.focus { setFocus(false) }
        }
        .overlay {
            if searchOpen { searchOverlay.transition(.opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: -8))) }
        }
        .animation(Motion.panel, value: searchOpen)
        .alert("未能完成操作", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("返回笔记") { workspace.error = nil }
            if workspace.dirty {
                Button("另存副本…") { workspace.error = nil; promptValue = "保留副本"; prompt = .copy }
                Button("重新载入磁盘内容…", role: .destructive) { workspace.error = nil; discardConfirmation = true }
            }
        } message: { Text(workspace.error ?? "") }
        .confirmationDialog("放弃当前未保存的输入，重新载入磁盘内容？", isPresented: $discardConfirmation) {
            Button("放弃未保存输入并重新载入", role: .destructive) { performNoteAction(workspace) { try workspace.reloadFromDisk() } }
        }
        .sheet(isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Text(prompt?.rawValue ?? "").font(.headline)
                if prompt == .folder { Text("新建位置：" + newTarget).font(.caption).foregroundStyle(.secondary) }
                TextField(prompt == .move ? "目标文件夹（留空为笔记库根目录）" : "名称", text: $promptValue).textFieldStyle(.roundedBorder).frame(width: 340)
                if prompt == .move { Text("可用文件夹：" + workspace.folders.joined(separator: "、")).font(.caption).foregroundStyle(.secondary) }
                if let promptError { Text(promptError).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                HStack { Spacer(); Button("取消") { prompt = nil }.keyboardShortcut(.cancelAction); Button("确定") { applyPrompt() }.keyboardShortcut(.defaultAction) }
            }.padding(26).onAppear { promptError = nil }
        }
        .background(WindowCloseGuard(workspace: workspace).frame(width: 0, height: 0))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            performNoteAction(workspace) { try workspace.checkExternalChanges() }
        }
        .onChange(of: searchOpen) { _, open in
            if !open {
                workspace.query = ""
                let responder = searchResponder
                searchResponder = nil
                Task { @MainActor in
                    await Task.yield()
                    if !searchOpen, let view = responder as? NSView { view.window?.makeFirstResponder(view) }
                }
            }
        }
        .onChange(of: workspace.selectedFolder) { _, folder in
            if let folder { expandedFolders.formUnion(FolderEntry.ancestors(of: folder)) }
        }
        .onChange(of: workspace.root) { _, root in expandedFolders = []; enforceVisibleLocation(); workspace.startWatching(); spaces.load(root: root) }
        .onAppear {
            enforceVisibleLocation(); revealSelection(); workspace.startWatching(); spaces.load(root: workspace.root)
            if changeToken == nil {
                let store = spaces
                changeToken = workspace.observeChanges { paths in store.libraryChanged(paths) }
            }
        }
        .onChange(of: spaces.error) { _, message in if let message { workspace.error = message; spaces.error = nil } }
        .sheet(item: $spaceSheet) { kind in
            switch kind {
            case .create:
                SpaceSheet(title: "新建空间", folders: workspace.folders, space: nil, save: { name, icon, scope in
                    try spaces.create(name: name, icon: icon, scope: scope); spaceSheet = nil
                }, cancel: { spaceSheet = nil })
            case .edit(let name):
                SpaceSheet(title: "编辑空间", folders: workspace.folders, space: spaces.spaces.first { $0.name == name }, save: { newName, icon, scope in
                    try spaces.update(name, newName: newName, icon: icon, scope: scope); spaceSheet = nil
                }, cancel: { spaceSheet = nil })
            }
        }
        .onChange(of: workspace.current) { _, _ in revealSelection() }
        .onChange(of: navigationMode) { _, _ in revealSelection() }
        .onChange(of: showAll) { _, _ in enforceVisibleLocation() }
        .onChange(of: showRecent) { _, _ in enforceVisibleLocation() }
        .onReceive(NotificationCenter.default.publisher(for: .init("NotesLite.search"))) { _ in showSearch() }
        .onReceive(NotificationCenter.default.publisher(for: .init("NotesLite.focus"))) { _ in setFocus(!workspace.focus) }
    }

    private func header(widths: ColumnWidths) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("留白").font(.system(size: 14, weight: .medium, design: .serif))
                Spacer(minLength: 0)
            }.padding(.leading, 80).padding(.trailing, 14).frame(width: widths.sidebar, height: 52).background(Color.library)
            Color.hairline.frame(width: unified ? 0 : 1)
            HStack(spacing: 8) {
                Text(listTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(inSpaces ? spaceNotes.count : workspace.visibleNotes.count)").font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.045), in: Capsule())
                Spacer(minLength: 0)
            }.padding(.horizontal, 20).frame(width: widths.list, height: 52).clipped().opacity(unified ? 0 : 1).accessibilityHidden(unified).background(Color.listPaper)
            Color.hairline.frame(width: unified ? 0 : 1)
            HStack(spacing: 5) {
                Text(workspace.root?.lastPathComponent ?? "本地笔记").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 4)
                Circle().fill(workspace.dirty ? Color.orange : Color.secondary.opacity(0.35)).frame(width: 4, height: 4)
                Text(workspace.saveState).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.trailing, 10)
                tool("magnifyingglass", "搜索笔记") { showSearch() }
                tool("square.and.pencil", "新建笔记（" + newTarget + "）") { withAnimation(Motion.selection) { performNoteAction(workspace) { try workspace.createNote(folder: workspace.creationFolder) } } }
                // Reserve the shared focus button's space outside the collapsing header.
                Color.clear.frame(width: 31, height: 31).accessibilityHidden(true)
            }.padding(.horizontal, 18).frame(height: 52)
        }.overlay(alignment: .bottom) { Color.hairline.frame(height: 1) }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("侧栏", selection: Binding(get: { sidebarMode }, set: { mode in withAnimation(Motion.panel) { sidebarMode = mode } })) {
                Text("资料库").tag(SidebarMode.library)
                Text("空间").tag(SidebarMode.spaces)
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
                .accessibilityLabel("切换资料库与空间")
            if inSpaces {
                SpaceSidebarList(store: spaces, namespace: spaceSelection, create: { spaceSheet = .create }) { space in
                    withAnimation(Motion.selection) { spaces.select(space.name) }
                }.padding(.horizontal, 10).transition(Motion.pane(true))
            } else {
            VStack(spacing: 3) {
                if showAll { NavigationRow(title: "全部笔记", icon: "square.stack", selected: navigationID == .all, namespace: navigationSelection, count: workspace.notes.count) {
                    withAnimation(Motion.selection) { workspace.selectedFolder = nil; workspace.recentsOnly = false }
                }
                }
                if showRecent { NavigationRow(title: "最近打开", icon: "clock", selected: navigationID == .recent, namespace: navigationSelection) {
                    withAnimation(Motion.selection) { workspace.recentsOnly = true; workspace.selectedFolder = nil }
                }
                }
                HStack {
                    Text(unified ? listTitle : "文件夹").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                    Spacer()
                    Button { promptValue = ""; prompt = .folder } label: { Image(systemName: "plus").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(SoftButton()).help("新建文件夹（" + newTarget + "）").accessibilityLabel("新建文件夹")
                }.padding(.leading, 10).padding(.trailing, 3).padding(.top, 18).padding(.bottom, 3)
                ScrollView {
                    VStack(spacing: 2) {
                        NavigationRow(title: "笔记库根目录", icon: "folder", selected: navigationID == .folder(""), namespace: navigationSelection) { browse("") }
                            .contextMenu { folderActions("") }
                        if unified {
                            if workspace.selectedFolder == nil || workspace.recentsOnly {
                                ForEach(workspace.visibleNotes) { note in
                                    NoteRow(note: note, selected: workspace.current == note.path, showFolder: true, namespace: noteSelection,
                                            select: { openNote(note) }, actions: { noteActions(note) })
                                }
                                if workspace.visibleNotes.isEmpty { Text("这里还没有笔记").font(.caption).foregroundStyle(.tertiary).padding() }
                            } else {
                                ForEach(LibraryTreeEntry.visible(folders: workspace.folders, notes: workspace.notes, expanded: expandedFolders)) { entry in
                                    switch entry {
                                    case .folder(let folder): folderRow(folder)
                                    case .note(let note, let depth):
                                        NavigationRow(title: note.title, icon: "doc.text", selected: workspace.current == note.path, namespace: noteSelection, depth: depth + 1) { openNote(note) }
                                            .contextMenu { noteActions(note) }
                                    }
                                }
                            }
                        } else {
                            ForEach(FolderEntry.visible(paths: workspace.folders, expanded: expandedFolders)) { folder in folderRow(folder) }
                        }
                    }.padding(.vertical, 2)
                }.scrollIndicators(.hidden)
            }.padding(.horizontal, 10).transition(Motion.pane(false))
            }
            Spacer(minLength: 14)
            if workspace.lastDeleted != nil {
                Button("恢复上次删除") { performNoteAction(workspace) { try workspace.restoreDeleted() } }
                    .font(.caption).buttonStyle(SoftButton()).padding(.horizontal, 12).padding(.bottom, 8)
            }
            Button { chooseLibrary(workspace) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "externaldrive").font(.system(size: 12))
                    Text(workspace.root?.lastPathComponent ?? "打开笔记库").font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                }.frame(maxWidth: .infinity).padding(.vertical, 4)
            }.buttonStyle(SoftButton()).foregroundStyle(.secondary).padding(10)
                .overlay(alignment: .top) { Color.hairline.frame(height: 1).padding(.horizontal, 18) }
        }.frame(maxHeight: .infinity).background(Color.library)
        .animation(Motion.selection, value: navigationID)
    }

    @ViewBuilder private var noteList: some View {
        ZStack {
            if inSpaces { spaceTreeList.transition(Motion.pane(true)) } else { libraryNoteList.transition(Motion.pane(false)) }
        }.clipped()
    }

    private var spaceTreeList: some View {
        VStack(spacing: 0) {
            if let space = spaces.current {
                ScrollView {
                    VStack(spacing: 2) {
                        NavigationRow(title: "主页", icon: spaces.showingHome ? "house.fill" : "house", selected: spaces.showingHome, namespace: spaceTreeSelection) {
                            withAnimation(Motion.selection) { spaces.showingHome = true }
                        }
                        ForEach(LibraryTreeEntry.visible(folders: SpaceTree.folders(workspace.folders, in: space.scope), notes: spaceNotes, expanded: expandedFolders)) { entry in
                            switch entry {
                            case .folder(let folder):
                                NavigationRow(title: folder.title, icon: "folder", selected: false, namespace: spaceTreeSelection, depth: folder.depth,
                                              expanded: folder.hasChildren ? expandedFolders.contains(folder.path) : nil,
                                              toggle: { toggleFolder(folder.path) }) { toggleFolder(folder.path) }
                                    .transition(Motion.row)
                            case .note(let note, let depth):
                                NavigationRow(title: note.title, icon: "doc.text", selected: !spaces.showingHome && workspace.current == note.path, namespace: spaceTreeSelection, depth: depth + 1) { openNote(note) }
                                    .contextMenu { noteActions(note) }.transition(Motion.row)
                            }
                        }
                    }.padding(.horizontal, 10).padding(.vertical, 12)
                    .animation(Motion.selection, value: spaceNotes.map(\.path))
                }.scrollIndicators(.hidden).id(space.name).transition(.opacity.combined(with: .offset(y: 6)))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 22, weight: .ultraLight))
                    Text(workspace.root == nil ? "打开笔记库后可以新建空间" : "新建一个空间开始").font(.system(size: 11))
                }.foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 50)
                Spacer()
            }
        }.frame(maxHeight: .infinity).background(Color.listPaper)
    }

    private func toggleFolder(_ path: String) {
        withAnimation(Motion.selection) { if !expandedFolders.insert(path).inserted { expandedFolders.remove(path) } }
    }

    private var libraryNoteList: some View {
        let visible = workspace.visibleNotes
        let showFolders = workspace.selectedFolder == nil || workspace.recentsOnly
        return VStack(spacing: 0) {
            if let folder = workspace.selectedFolder, !workspace.recentsOnly { directoryPath(folder) }
            if visible.isEmpty && workspace.childFolders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: workspace.query.isEmpty ? "doc.text" : "magnifyingglass").font(.system(size: 22, weight: .ultraLight))
                    Text(workspace.root == nil ? "打开文件夹，开始记录" : workspace.query.isEmpty ? "这里还没有笔记" : "没有找到笔记").font(.system(size: 11))
                }.foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 50)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(workspace.childFolders, id: \.self) { folder in
                        Button { browse(folder) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                Text((folder as NSString).lastPathComponent).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                            }.font(.system(size: 12)).padding(10).contentShape(Rectangle())
                        }.buttonStyle(SoftButton()).contextMenu { folderActions(folder) }
                    }
                    ForEach(visible) { note in
                        NoteRow(note: note, selected: workspace.current == note.path, showFolder: showFolders, namespace: noteSelection,
                            select: { openNote(note) }, actions: { noteActions(note) })
                            .transition(Motion.row)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 12)
                .animation(Motion.selection, value: workspace.query)
                .animation(Motion.selection, value: workspace.current)
            }.scrollIndicators(.hidden)
        }.frame(maxHeight: .infinity).background(Color.listPaper)
    }

    @ViewBuilder private func noteActions(_ note: Note) -> some View {
        Button("重命名…") { performNoteAction(workspace) { try workspace.select(note.path); promptValue = note.title; prompt = .rename } }
        Button("移动到…") { performNoteAction(workspace) { try workspace.select(note.path); promptValue = note.folder; prompt = .move } }
        Divider()
        Button("移到废纸篓", role: .destructive) { performNoteAction(workspace) { try workspace.select(note.path); withAnimation(Motion.selection) { do { try workspace.deleteCurrent() } catch { workspace.error = error.localizedDescription } } } }
    }

    private var editor: some View {
        ZStack {
            if inSpaces, spaces.showingHome, let space = spaces.current {
                spaceHome(space).id("home:" + space.name).transition(Motion.surface)
            } else {
                noteEditor.transition(Motion.surface)
            }
        }
        .animation(Motion.panel, value: spaces.current?.name)
        .animation(Motion.panel, value: spaces.showingHome)
    }

    @ViewBuilder private var noteEditor: some View {
        if workspace.current != nil {
            VStack(spacing: 0) {
                if !workspace.focus {
                    HStack {
                        Text(workspace.current ?? "").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Menu {
                            Picker("字体", selection: $editorFont) {
                                ForEach(EditorFont.allCases) { font in
                                    Text(font.cardLabel).tag(font)
                                }
                            }
                        } label: {
                            Image(systemName: "textformat").font(.system(size: 12))
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help("更改字体").accessibilityLabel("更改字体")
                        Button { chooseAttachment() } label: { Image(systemName: "paperclip").font(.system(size: 12)) }.buttonStyle(SoftButton()).help("添加图片或附件").accessibilityLabel("添加图片或附件")
                        Button { workspace.source.toggle() } label: { Text(workspace.source ? "排版" : "Markdown").font(.system(size: 10, weight: .medium, design: .monospaced)) }.buttonStyle(SoftButton()).help("切换源码与原地排版")
                    }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.top, 14)
                }
                NativeEditor(workspace: workspace, font: editorFont)
                if !workspace.focus {
                    HStack { Text("本地 Markdown"); Spacer(); Text("\(workspace.text.count) 字") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.bottom, 14)
                }
            }
        } else {
            ContentUnavailableView { Label("让想法，在这里停留", systemImage: "leaf") } description: { Text("打开一个本地文件夹，开始记录。") } actions: { Button("打开笔记库…") { chooseLibrary(workspace) } }
        }
    }

    @ViewBuilder private func spaceHome(_ space: Space) -> some View {
        if space.hasPage, let root = workspace.root {
            SpaceHome(space: space, root: root, store: spaces, showLog: { showOperationLog = true })
        } else {
            SpaceEmptyHome(space: space, store: spaces)
        }
    }

    private var searchOverlay: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea().onTapGesture { searchOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索标题或正文…", text: $searchQuery).textFieldStyle(.plain).focused($searchFocused)
                    Button { searchOpen = false } label: { Text("esc").font(.system(size: 10, design: .monospaced)) }.buttonStyle(SoftButton()).foregroundStyle(.secondary)
                }.padding(20)
                Picker("搜索范围", selection: $searchLocal) {
                    Text("整个笔记库").tag(false)
                    Text("当前文件夹及子文件夹").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 12)
                if searchLocal { Text(searchFolder.isEmpty ? "笔记库根目录" : searchFolder).font(.caption).foregroundStyle(.secondary).padding(.bottom, 8) }
                Divider().opacity(0.4)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(searchResults) { note in
                            Button { performNoteAction(workspace) { try workspace.select(note.path); browse(note.folder); searchOpen = false } } label: {
                                HStack(spacing: 12) { Image(systemName: "doc.text").foregroundStyle(.secondary); VStack(alignment: .leading, spacing: 5) { Text(note.title).font(.system(size: 13)); Text(note.folder.isEmpty ? "笔记库" : note.folder).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer() }.padding(13).contentShape(Rectangle())
                            }.buttonStyle(SoftButton()).transition(Motion.row)
                        }
                        if searchResults.isEmpty { Text("没有找到笔记，换个词试试。").font(.caption).foregroundStyle(.secondary).padding(35) }
                    }.padding(8).animation(Motion.selection, value: searchQuery)
                }.frame(maxHeight: 300)
                Divider().opacity(0.4)
                Text("本地搜索 · 标题与正文").font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }.frame(width: 510)
                .background { GlassSurface(backdrop: backdrop, impulse: glassImpulse).allowsHitTesting(false).clipShape(RoundedRectangle(cornerRadius: 20)) }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in glassImpulse.point = tap.location; glassImpulse.sequence += 1 }).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.45), lineWidth: 1)).shadow(color: .black.opacity(0.12), radius: 30, y: 16)
                .onExitCommand { searchOpen = false }
        }
    }

    private func browse(_ folder: String) {
        withAnimation(Motion.selection) {
            workspace.recentsOnly = false
            workspace.selectedFolder = folder
            expandedFolders.formUnion(FolderEntry.ancestors(of: folder))
            expandedFolders.insert(folder)
        }
    }

    private func selectFolder(_ folder: String) {
        guard unified, workspace.selectedFolder == folder, expandedFolders.contains(folder) else {
            browse(folder)
            return
        }
        withAnimation(Motion.selection) {
            expandedFolders.remove(folder)
        }
    }

    private func openNote(_ note: Note) {
        if spaces.showingHome { withAnimation(Motion.panel) { spaces.showingHome = false } }
        guard workspace.current != note.path else { return }
        performNoteAction(workspace) { try workspace.select(note.path) }
    }

    private func revealSelection() {
        if let folder = workspace.selectedFolder {
            expandedFolders.formUnion(FolderEntry.ancestors(of: folder)); expandedFolders.insert(folder)
        }
        if let current = workspace.current { expandedFolders.formUnion(FolderEntry.ancestors(of: current)) }
    }

    private func enforceVisibleLocation() {
        if (workspace.recentsOnly && !showRecent) || (!workspace.recentsOnly && workspace.selectedFolder == nil && !showAll) {
            browse(workspace.current.map { ($0 as NSString).deletingLastPathComponent } ?? "")
        }
    }

    private func folderRow(_ folder: FolderEntry) -> some View {
        NavigationRow(title: folder.title, icon: workspace.selectedFolder == folder.path ? "folder.fill" : "folder",
                      selected: navigationID == .folder(folder.path), namespace: navigationSelection, depth: folder.depth,
                      expanded: folder.hasChildren ? expandedFolders.contains(folder.path) : nil,
                      toggle: { withAnimation(Motion.selection) {
                          if !expandedFolders.insert(folder.path).inserted { expandedFolders.remove(folder.path) }
                      } }) { selectFolder(folder.path) }
            .contextMenu { folderActions(folder.path) }.transition(Motion.row)
    }

    @ViewBuilder private func folderActions(_ folder: String) -> some View {
        Button("在此新建笔记") { browse(folder); performNoteAction(workspace) { try workspace.createNote(folder: folder) } }
        Button("在此新建文件夹…") { browse(folder); promptValue = ""; prompt = .folder }
    }

    private func directoryPath(_ folder: String) -> some View {
        HStack(spacing: 5) {
            Button { browse((folder as NSString).deletingLastPathComponent) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(SoftButton()).disabled(folder.isEmpty).help("返回父文件夹").accessibilityLabel("返回父文件夹")
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    Button("笔记库") { browse("") }.buttonStyle(.plain)
                    ForEach(Array(folder.split(separator: "/").enumerated()), id: \.offset) { index, part in
                        Image(systemName: "chevron.right").font(.system(size: 7))
                        Button(String(part)) { browse(folder.split(separator: "/").prefix(index + 1).joined(separator: "/")) }.buttonStyle(.plain)
                    }
                }.fixedSize()
            }.scrollIndicators(.hidden)
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(alignment: .bottom) { Color.hairline.frame(height: 1) }
    }

    private func applyPrompt() {
        do {
            switch prompt {
            case .folder:
                try workspace.createFolder(promptValue, folder: workspace.creationFolder)
                if let parent = workspace.selectedFolder { withAnimation(Motion.selection) { _ = expandedFolders.insert(parent) } }
            case .rename: try workspace.renameCurrent(title: promptValue)
            case .move:
                guard let current = workspace.current else { return }
                try workspace.relocateCurrent(to: (promptValue.isEmpty ? "" : promptValue + "/") + (current as NSString).lastPathComponent)
            case .copy: try workspace.saveCopy(title: promptValue)
            case nil: return
            }
            prompt = nil
        } catch { promptError = error.localizedDescription }
    }
    private func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.prompt = "加入笔记"
        if panel.runModal() == .OK {
            performNoteAction(workspace) {
                for url in panel.urls {
                    let snippet = try workspace.importAttachment(from: url)
                    NotificationCenter.default.post(name: .init("NotesLite.insert"), object: snippet)
                }
            }
        }
    }
    private func showSearch() {
        if searchOpen { return }
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
        searchResponder = window?.firstResponder
        backdrop = GlassBackdrop.capture()
        glassImpulse.sequence += 1
        searchQuery = ""; searchLocal = false; searchFolder = workspace.creationFolder
        searchOpen = true; searchFocused = true
    }
    private func setFocus(_ value: Bool) {
        edgeTask?.cancel()
        edgeBackdrop = GlassBackdrop.capture()
        edgeImpulse.sequence += 1
        edgeVisible = true
        withAnimation(Motion.panel) { workspace.focus = value }
        edgeTask = Task {
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { edgeVisible = false }
        }
    }
    private func tool(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 17, height: 17) }.buttonStyle(SoftButton()).help(label).accessibilityLabel(label)
    }
}
