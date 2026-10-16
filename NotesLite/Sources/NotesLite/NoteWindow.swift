import AppKit
import NotesCore
import SwiftUI

private enum PromptKind: String {
    case folder = "新建文件夹", rename = "重命名笔记", move = "移动笔记", copy = "保存副本"
}

struct NoteWindow: View {
    @Bindable var workspace: Workspace
    @State private var searchOpen = false
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
    @State private var expandedFolders: Set<String> = []
    @Namespace private var navigationSelection
    @Namespace private var noteSelection
    private var listTitle: String { workspace.recentsOnly ? "最近打开" : workspace.selectedFolder?.components(separatedBy: "/").last ?? "全部笔记" }
    private var navigationID: String { workspace.recentsOnly ? "recent" : workspace.selectedFolder ?? "all" }
    var body: some View {
        GeometryReader { geometry in
            let widths = ColumnWidths.fitting(total: geometry.size.width, sidebar: sidebarWidth, list: listWidth)
            VStack(spacing: 0) {
                header(widths: widths)
                    .frame(height: workspace.focus ? 0 : 52, alignment: .top).clipped()
                    .opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                HStack(spacing: 0) {
                    library.frame(width: widths.sidebar)
                        .frame(width: workspace.focus ? 0 : widths.sidebar, alignment: .leading).clipped()
                        .opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                    ColumnDivider(width: Binding(get: { widths.sidebar }, set: { sidebarWidth = $0 }), limits: 180...min(280, max(180, geometry.size.width - widths.list - 322)), label: "调整侧栏宽度")
                        .frame(width: workspace.focus ? 0 : 1).opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                    noteList.frame(width: widths.list)
                        .frame(width: workspace.focus ? 0 : widths.list, alignment: .leading).clipped()
                        .opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                    ColumnDivider(width: Binding(get: { widths.list }, set: { listWidth = $0 }), limits: 220...min(380, max(220, geometry.size.width - widths.sidebar - 322)), label: "调整笔记列表宽度")
                        .frame(width: workspace.focus ? 0 : 1).opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
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
        }
        .background(Color.paper)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .topTrailing) {
            if workspace.focus {
                Button { setFocus(false) } label: { Label("退出专注", systemImage: "arrow.down.right.and.arrow.up.left").font(.caption) }
                    .buttonStyle(SoftButton()).foregroundStyle(.secondary).padding(16)
                    .keyboardShortcut(.escape, modifiers: [])
            }
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
        .onChange(of: workspace.selectedFolder) { _, folder in
            if let folder { expandedFolders.formUnion(FolderEntry.ancestors(of: folder)) }
        }
        .onChange(of: workspace.root) { _, _ in expandedFolders = [] }
        .onReceive(NotificationCenter.default.publisher(for: .init("NotesLite.search"))) { _ in showSearch() }
        .onReceive(NotificationCenter.default.publisher(for: .init("NotesLite.focus"))) { _ in setFocus(!workspace.focus) }
    }

    private func header(widths: ColumnWidths) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("留白").font(.system(size: 14, weight: .medium, design: .serif))
                Spacer(minLength: 0)
            }.padding(.leading, 80).padding(.trailing, 14).frame(width: widths.sidebar, height: 52).background(Color.library)
            Color.hairline.frame(width: 1)
            HStack(spacing: 8) {
                Text(listTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(workspace.visibleNotes.count)").font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.045), in: Capsule())
                Spacer(minLength: 0)
            }.padding(.horizontal, 20).frame(width: widths.list, height: 52).background(Color.listPaper)
            Color.hairline.frame(width: 1)
            HStack(spacing: 5) {
                Text(workspace.root?.lastPathComponent ?? "本地笔记").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 4)
                Circle().fill(workspace.dirty ? Color.orange : Color.secondary.opacity(0.35)).frame(width: 4, height: 4)
                Text(workspace.saveState).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.trailing, 10)
                tool("magnifyingglass", "搜索笔记") { showSearch() }
                tool("square.and.pencil", "新建笔记") { withAnimation(Motion.selection) { performNoteAction(workspace) { try workspace.createNote() } } }
                tool("arrow.up.left.and.arrow.down.right", "进入专注模式") { setFocus(true) }
            }.padding(.horizontal, 18).frame(height: 52)
        }.overlay(alignment: .bottom) { Color.hairline.frame(height: 1) }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("资料库").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)
            VStack(spacing: 3) {
                NavigationRow(title: "全部笔记", icon: "square.stack", selected: navigationID == "all", namespace: navigationSelection, count: workspace.notes.count) {
                    withAnimation(Motion.selection) { workspace.selectedFolder = nil; workspace.recentsOnly = false }
                }
                NavigationRow(title: "最近打开", icon: "clock", selected: navigationID == "recent", namespace: navigationSelection) {
                    withAnimation(Motion.selection) { workspace.recentsOnly = true; workspace.selectedFolder = nil }
                }
                HStack {
                    Text("文件夹").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                    Spacer()
                    Button { promptValue = ""; prompt = .folder } label: { Image(systemName: "plus").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(SoftButton()).help("新建文件夹").accessibilityLabel("新建文件夹")
                }.padding(.leading, 10).padding(.trailing, 3).padding(.top, 18).padding(.bottom, 3)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(FolderEntry.visible(paths: workspace.folders, expanded: expandedFolders)) { folder in
                            NavigationRow(title: folder.title, icon: workspace.selectedFolder == folder.path ? "folder.fill" : "folder", selected: workspace.selectedFolder == folder.path, namespace: navigationSelection, depth: folder.depth,
                                expanded: folder.hasChildren ? expandedFolders.contains(folder.path) : nil,
                                toggle: {
                                    withAnimation(Motion.selection) {
                                        if !expandedFolders.insert(folder.path).inserted { expandedFolders.remove(folder.path) }
                                    }
                                }) {
                                    withAnimation(Motion.selection) { workspace.selectedFolder = folder.path; workspace.recentsOnly = false }
                                }
                                .transition(Motion.row)
                        }
                        if workspace.folders.isEmpty { Text("用文件夹整理想法").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                    }.padding(.vertical, 2)
                }.scrollIndicators(.hidden)
            }.padding(.horizontal, 10)
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

    private var noteList: some View {
        let visible = workspace.visibleNotes
        let showFolders = Set(visible.map(\.folder)).count > 1
        return VStack(spacing: 0) {
            if visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: workspace.query.isEmpty ? "doc.text" : "magnifyingglass").font(.system(size: 22, weight: .ultraLight))
                    Text(workspace.root == nil ? "打开文件夹，开始记录" : workspace.query.isEmpty ? "这里还没有笔记" : "没有找到笔记").font(.system(size: 11))
                }.foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 50)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(visible) { note in
                        NoteRow(note: note, selected: workspace.current == note.path, showFolder: showFolders, namespace: noteSelection,
                            select: { performNoteAction(workspace) { try workspace.select(note.path) } }, actions: { noteActions(note) })
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

    @ViewBuilder private var editor: some View {
        if workspace.current != nil {
            VStack(spacing: 0) {
                if !workspace.focus {
                    HStack {
                        Text(workspace.current ?? "").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { chooseAttachment() } label: { Image(systemName: "paperclip").font(.system(size: 12)) }.buttonStyle(SoftButton()).help("添加图片或附件").accessibilityLabel("添加图片或附件")
                        Button { workspace.source.toggle() } label: { Text(workspace.source ? "排版" : "Markdown").font(.system(size: 10, weight: .medium, design: .monospaced)) }.buttonStyle(SoftButton()).help("切换源码与原地排版")
                    }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.top, 14)
                }
                NativeEditor(workspace: workspace)
                if !workspace.focus {
                    HStack { Text("本地 Markdown"); Spacer(); Text("\(workspace.text.count) 字") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.bottom, 14)
                }
            }
        } else {
            ContentUnavailableView { Label("让想法，在这里停留", systemImage: "leaf") } description: { Text("打开一个本地文件夹，开始记录。") } actions: { Button("打开笔记库…") { chooseLibrary(workspace) } }
        }
    }

    private var searchOverlay: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea().onTapGesture { searchOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索标题或正文…", text: $workspace.query).textFieldStyle(.plain).focused($searchFocused)
                    Button { searchOpen = false } label: { Text("esc").font(.system(size: 10, design: .monospaced)) }.buttonStyle(SoftButton()).foregroundStyle(.secondary)
                }.padding(20)
                Divider().opacity(0.4)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(workspace.visibleNotes) { note in
                            Button { performNoteAction(workspace) { try workspace.select(note.path); searchOpen = false } } label: {
                                HStack(spacing: 12) { Image(systemName: "doc.text").foregroundStyle(.secondary); VStack(alignment: .leading, spacing: 5) { Text(note.title).font(.system(size: 13)); Text(note.folder.isEmpty ? "笔记库" : note.folder).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer() }.padding(13).contentShape(Rectangle())
                            }.buttonStyle(SoftButton())
                        }
                        if workspace.visibleNotes.isEmpty { Text("没有找到笔记，换个词试试。").font(.caption).foregroundStyle(.secondary).padding(35) }
                    }.padding(8)
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

    private func applyPrompt() {
        do {
            switch prompt {
            case .folder:
                try workspace.createFolder(promptValue)
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
        backdrop = GlassBackdrop.capture()
        glassImpulse.sequence += 1
        workspace.query = ""; workspace.selectedFolder = nil; workspace.recentsOnly = false
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
