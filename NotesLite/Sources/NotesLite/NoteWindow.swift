import AppKit
import NotesCore
import SwiftUI

extension Color {
    static let paper = Color(nsColor: .textBackgroundColor)
    static let navigationAccent = Color.primary
    static let library = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) == .darkAqua ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.962, alpha: 1) })
}

enum Motion {
    static let panel = Animation.spring(duration: 0.42, bounce: 0.20)
    static let feedback = Animation.spring(duration: 0.24, bounce: 0.16)
}

struct SoftButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(8)
            .background(configuration.isPressed ? Color.navigationAccent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.feedback, value: configuration.isPressed)
    }
}

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
    var body: some View {
        VStack(spacing: 0) {
            if !workspace.focus {
                HStack(spacing: 12) {
                    Text("留白").font(.system(size: 14, weight: .medium, design: .serif)).padding(.leading, 76)
                    Text("/  \(workspace.root?.lastPathComponent ?? "本地笔记")").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(workspace.saveState).font(.system(size: 10)).foregroundStyle(workspace.dirty ? .orange : .secondary)
                    tool("magnifyingglass", "搜索笔记", key: "k") { showSearch() }
                    tool("square.and.pencil", "新建笔记", key: "n") { performNoteAction(workspace) { try workspace.createNote() } }
                    tool("arrow.up.left.and.arrow.down.right", "进入专注模式", key: "f", modifiers: [.command, .shift]) { setFocus(true) }
                }.padding(.horizontal, 14).frame(height: 54)
                Divider().opacity(0.35)
            }
            HStack(spacing: 0) {
                library.frame(width: workspace.focus ? 0 : 185).clipped().opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                Divider().frame(width: workspace.focus ? 0 : 1).opacity(workspace.focus ? 0 : 0.3)
                noteList.frame(width: workspace.focus ? 0 : 230).clipped().opacity(workspace.focus ? 0 : 1).allowsHitTesting(!workspace.focus).accessibilityHidden(workspace.focus)
                Divider().frame(width: workspace.focus ? 0 : 1).opacity(workspace.focus ? 0 : 0.3)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.paper)
        .overlay(alignment: .leading) {
            if edgeVisible {
                GlassSurface(backdrop: edgeBackdrop, impulse: edgeImpulse)
                    .frame(width: 24).offset(x: workspace.focus ? -12 : 403)
                    .allowsHitTesting(false).accessibilityHidden(true)
                    .animation(Motion.panel, value: workspace.focus)
            }
        }
        .overlay(alignment: .topTrailing) {
            if workspace.focus {
                Button { setFocus(false) } label: { Label("退出专注", systemImage: "arrow.down.right.and.arrow.up.left").font(.caption) }
                    .buttonStyle(SoftButton()).foregroundStyle(.secondary).padding(16)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .overlay {
            if searchOpen { searchOverlay.transition(.opacity.combined(with: .scale(scale: 0.96))) }
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
        .onReceive(NotificationCenter.default.publisher(for: .init("NotesLite.search"))) { _ in showSearch() }
        .onReceive(NotificationCenter.default.publisher(for: .init("NotesLite.focus"))) { _ in setFocus(!workspace.focus) }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) { Image(systemName: "leaf").font(.title3); Text("我的笔记").font(.system(size: 17, weight: .medium, design: .serif)) }
                .padding(.horizontal, 18).padding(.top, 25).padding(.bottom, 20)
            navigation("全部笔记", icon: "square.stack", selected: workspace.selectedFolder == nil && !workspace.recentsOnly, count: workspace.notes.count) {
                workspace.selectedFolder = nil; workspace.recentsOnly = false
            }
            navigation("最近打开", icon: "clock", selected: workspace.recentsOnly) { workspace.recentsOnly = true; workspace.selectedFolder = nil }
            HStack {
                Text("文件夹").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button { promptValue = ""; prompt = .folder } label: { Image(systemName: "folder.badge.plus").font(.system(size: 12)) }.buttonStyle(SoftButton()).help("新建文件夹").accessibilityLabel("新建文件夹")
            }.padding(.horizontal, 18).padding(.top, 20)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(workspace.folders, id: \.self) { folder in
                        navigation(folder, icon: "folder", selected: workspace.selectedFolder == folder) {
                            workspace.selectedFolder = folder; workspace.recentsOnly = false
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if workspace.lastDeleted != nil {
                Button("恢复上次删除") { performNoteAction(workspace) { try workspace.restoreDeleted() } }.font(.caption).buttonStyle(SoftButton()).padding(.horizontal, 10)
            }
            Button { chooseLibrary(workspace) } label: { Label(workspace.root?.lastPathComponent ?? "打开笔记库", systemImage: "externaldrive").font(.system(size: 11)).lineLimit(1) }
                .buttonStyle(SoftButton()).padding(10).foregroundStyle(.secondary)
        }.frame(maxHeight: .infinity).background(Color.library)
    }

    private func navigation(_ title: String, icon: String, selected: Bool, count: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 10)
                .background(selected ? Color.navigationAccent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }

    private var noteList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(workspace.recentsOnly ? "最近打开" : workspace.selectedFolder?.components(separatedBy: "/").last ?? "全部笔记").font(.system(size: 15, weight: .medium)); Spacer(); Text("\(workspace.visibleNotes.count) 篇").font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(20)
            if workspace.notes.isEmpty {
                Text(workspace.root == nil ? "先打开一个本地文件夹" : "还没有笔记，按 ⌘N 开始记录").font(.caption).foregroundStyle(.secondary).padding(20)
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(workspace.visibleNotes) { note in
                        Button { performNoteAction(workspace) { try workspace.select(note.path) } } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                Text(note.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(4)
                                HStack { Text(note.modified, style: .date); Spacer(); Text(note.folder.isEmpty ? "笔记库" : note.folder).lineLimit(1) }.font(.system(size: 9)).foregroundStyle(.tertiary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
                                .background(workspace.current == note.path ? Color.navigationAccent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 11))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu { noteActions(note) }
                        .overlay(alignment: .topTrailing) {
                            Menu { noteActions(note) } label: { Image(systemName: "ellipsis").font(.system(size: 11)) }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20).padding(8)
                                .accessibilityLabel("整理「\(note.title)」")
                        }
                    }
                }.padding(.horizontal, 10)
            }
        }.frame(maxHeight: .infinity).background(Color.library.opacity(0.28))
    }

    @ViewBuilder private func noteActions(_ note: Note) -> some View {
        Button("重命名…") { performNoteAction(workspace) { try workspace.select(note.path); promptValue = note.title; prompt = .rename } }
        Button("移动到…") { performNoteAction(workspace) { try workspace.select(note.path); promptValue = note.folder; prompt = .move } }
        Divider()
        Button("移到废纸篓", role: .destructive) { performNoteAction(workspace) { try workspace.select(note.path); try workspace.deleteCurrent() } }
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
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in glassImpulse.point = tap.location; glassImpulse.sequence += 1 }).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.45), lineWidth: 1)).shadow(color: .black.opacity(0.14), radius: 32, y: 18)
                .onExitCommand { searchOpen = false }
        }
    }

    private func applyPrompt() {
        do {
            switch prompt {
            case .folder: try workspace.createFolder(promptValue)
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
            edgeVisible = false
        }
    }
    private func tool(_ symbol: String, _ label: String, key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 17, height: 17) }.buttonStyle(SoftButton()).help(label).accessibilityLabel(label).keyboardShortcut(key, modifiers: modifiers)
    }
}
