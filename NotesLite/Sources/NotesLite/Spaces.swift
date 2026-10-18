import AppKit
import NotesCore
import SwiftUI

enum SidebarMode: String { case library, spaces }

/// The spaces of the open library and which one the window is showing.
@MainActor @Observable final class SpaceStore {
    private(set) var spaces: [Space] = []
    private(set) var library: SpaceLibrary?
    var selected: String?
    /// The right column shows the space homepage rather than a note.
    var showingHome = true
    var copiedPrompt = false
    var error: String?

    var current: Space? { spaces.first { $0.name == selected } ?? nil }

    func load(root: URL?) {
        library = root.map(SpaceLibrary.init(root:))
        // Keep the installed guide in step with this version of the app.
        if let library, FileManager.default.fileExists(atPath: library.folder.path) { try? library.installGuide() }
        reload()
    }

    func reload() {
        let fresh = (try? library?.spaces()) ?? []
        if fresh != spaces { spaces = fresh }
        if let selected, !spaces.contains(where: { $0.name == selected }) { self.selected = nil }
        if selected == nil { selected = spaces.first?.name }
    }

    func create(name: String, icon: String, scope: SpaceScope) throws {
        guard let library else { throw NoteError.noLibrary }
        let space = try library.create(name: name, icon: icon, scope: scope)
        reload()
        selected = space.name; showingHome = true
        try copyPrompt(for: space)
    }

    func update(_ name: String, newName: String, icon: String, scope: SpaceScope) throws {
        guard let library else { throw NoteError.noLibrary }
        let space = try library.update(name, newName: newName, icon: icon, scope: scope)
        reload()
        selected = space.name
    }

    func copyPrompt(for space: Space) throws {
        guard let library else { throw NoteError.noLibrary }
        let prompt = try library.prompt(for: space)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copiedPrompt = true
    }

    func perform(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
    }
}

/// Folders and notes inside a space's scope, as one tree.
enum SpaceTree {
    static func folders(_ all: [String], in scope: SpaceScope) -> [String] {
        guard case .folders(let roots) = scope else { return all }
        return all.filter { folder in roots.contains { folder == $0 || folder.hasPrefix($0 + "/") || $0.hasPrefix(folder + "/") } }
    }
    static func notes(_ all: [Note], in scope: SpaceScope) -> [Note] { all.filter { scope.contains($0.path) } }
}

struct SpaceSidebarList: View {
    @Bindable var store: SpaceStore
    let namespace: Namespace.ID
    let create: () -> Void
    let select: (Space) -> Void
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("空间").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                Spacer()
                Button(action: create) { Image(systemName: "plus").font(.system(size: 10, weight: .medium)) }
                    .buttonStyle(SoftButton()).help("新建空间").accessibilityLabel("新建空间")
            }.padding(.leading, 10).padding(.trailing, 3).padding(.top, 6).padding(.bottom, 3)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.spaces) { space in
                        SpaceRow(space: space, selected: store.selected == space.name, namespace: namespace) { select(space) }
                    }
                    if store.spaces.isEmpty {
                        Button("新建空间", action: create).font(.caption).buttonStyle(SoftButton()).padding(.top, 20)
                        Text("空间围绕一个主题，把相关文件夹放在一起，并有一个由 agent 生成的主页。")
                            .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.horizontal, 12)
                    }
                }.padding(.vertical, 2)
            }.scrollIndicators(.hidden)
        }
    }
}

struct SpaceRow: View {
    let space: Space
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(space.icon.isEmpty ? "◻︎" : space.icon).font(.system(size: 14)).frame(width: 20)
                Text(space.name).font(.system(size: 12, weight: selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 3)
            }.padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8).fill(Color.selectionPaper)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.055)))
                    .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
                    .matchedGeometryEffect(id: "navigation-selection", in: namespace)
            }
        }
        .background(Color.primary.opacity(hovered && !selected ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
        .animation(Motion.hover, value: hovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(space.name + " · " + space.scope.label)
    }
}

/// Creating or editing a space: name, emoji and scope.
struct SpaceSheet: View {
    let title: String
    let folders: [String]
    @State var name: String
    @State var icon: String
    @State var wholeLibrary: Bool
    @State var chosen: Set<String>
    let save: (String, String, SpaceScope) throws -> Void
    let cancel: () -> Void
    @State private var error: String?

    init(title: String, folders: [String], space: Space?, save: @escaping (String, String, SpaceScope) throws -> Void, cancel: @escaping () -> Void) {
        self.title = title; self.folders = folders; self.save = save; self.cancel = cancel
        _name = State(initialValue: space?.name ?? "")
        _icon = State(initialValue: space?.icon ?? "✨")
        if case .folders(let list) = space?.scope { _wholeLibrary = State(initialValue: false); _chosen = State(initialValue: Set(list)) }
        else { _wholeLibrary = State(initialValue: space != nil); _chosen = State(initialValue: []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            HStack(spacing: 10) {
                TextField("图标", text: $icon).textFieldStyle(.roundedBorder).frame(width: 52).multilineTextAlignment(.center)
                    .accessibilityLabel("空间图标")
                TextField("空间名称，例如：健身", text: $name).textFieldStyle(.roundedBorder).frame(width: 280)
            }
            Text("范围：空间主页只能读取和写入范围内的笔记。").font(.caption).foregroundStyle(.secondary)
            Toggle("整个笔记库", isOn: $wholeLibrary)
            if !wholeLibrary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(folders, id: \.self) { folder in
                            Toggle(isOn: Binding(get: { chosen.contains(folder) }, set: { if $0 { chosen.insert(folder) } else { chosen.remove(folder) } })) {
                                Text(folder).font(.system(size: 12))
                            }.toggleStyle(.checkbox).padding(.leading, CGFloat(folder.split(separator: "/").count - 1) * 14)
                        }
                        if folders.isEmpty { Text("笔记库里还没有文件夹，可以选择整个笔记库。").font(.caption).foregroundStyle(.tertiary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 180).padding(8).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("确定") {
                    let scope: SpaceScope = wholeLibrary ? .library : .folders(folders.filter(chosen.contains))
                    do { try save(name.trimmingCharacters(in: .whitespaces), icon.trimmingCharacters(in: .whitespaces), scope) }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 400)
    }
}

/// The right column when a space has no homepage yet.
struct SpaceEmptyHome: View {
    let space: Space
    @Bindable var store: SpaceStore
    var body: some View {
        ContentUnavailableView {
            Label("\(space.icon) \(space.name) 还没有主页", systemImage: "sparkles")
        } description: {
            Text("复制提示词，粘贴给 Claude Code、Codex 等外部 agent。agent 写好空间文件后，主页会自动出现在这里。")
        } actions: {
            Button(store.copiedPrompt ? "已复制提示词" : "让 agent 生成主页") { store.perform { try store.copyPrompt(for: space) } }
                .buttonStyle(.borderedProminent)
            Text("范围：" + space.scope.label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
