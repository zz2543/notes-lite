import Foundation
import AppKit
import Observation

public struct Note: Identifiable, Equatable, Sendable {
    public let path: String
    public let modified: Date
    public let preview: String
    public var id: String { path }
    public var title: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }
}

public enum NoteError: LocalizedError {
    case noLibrary, invalidName, exists(String), outsideLibrary, conflict, missing(String)
    public var errorDescription: String? {
        switch self {
        case .noLibrary: "请先打开笔记库。"
        case .invalidName: "名称不能为空，不能包含斜杠或使用隐藏文件名。"
        case .exists(let name): "已经存在「\(name)」，请换一个名称。"
        case .outsideLibrary: "该位置不在当前笔记库内。"
        case .conflict: "文件已被外部修改。你的输入仍保留，请选择重新载入或另存副本。"
        case .missing(let path): "找不到笔记：\(path)"
        }
    }
}

@MainActor @Observable public final class Workspace {
    public private(set) var root: URL?
    public private(set) var notes: [Note] = []
    public private(set) var folders: [String] = []
    public private(set) var current: String?
    public private(set) var text = ""
    public private(set) var dirty = false
    public private(set) var revision = 0
    public private(set) var recent: [String] = []
    public var query = ""
    public var selectedFolder: String?
    public var recentsOnly = false
    public var focus = false
    public var source = false
    public var error: String?
    public var saveState = "已保存"
    public private(set) var lastDeleted: (path: String, url: URL)?
    @ObservationIgnored private var baseline: Data?
    private var scanCache: [String: LibraryScan.Cached] = [:]
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var observers: [UUID: ([String]) -> Void] = [:]
    @ObservationIgnored private var backgroundScan: Task<Void, Never>?
    @ObservationIgnored private var rescanPending = false
    @ObservationIgnored private var scanCompletions: [() -> Void] = []
    @ObservationIgnored private var autosave: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults?
    public init(defaults: UserDefaults? = nil) { self.defaults = defaults }

    /// Opens a library. With `scanInBackground`, the first pass over its notes runs off the main thread
    /// (the app's choice for large libraries); the first note opens when it lands.
    public func open(_ url: URL, scanInBackground: Bool = false) throws {
        try save()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { throw NoteError.missing(url.path) }
        let watching = watcher != nil
        stopWatching()
        root = url.resolvingSymlinksInPath().standardizedFileURL
        scanCache = [:]
        lastDeleted = nil
        current = nil; text = ""; baseline = nil; dirty = false; revision += 1
        selectedFolder = nil; query = ""; recentsOnly = false
        recent = defaults?.stringArray(forKey: "recent.\(root!.path)") ?? []
        if scanInBackground {
            notes = []; folders = []
            if watching { startWatching() }
            refreshInBackground { [weak self] in
                guard let self, self.current == nil, let first = self.notes.first else { return }
                do { try self.select(first.path) } catch { self.error = error.localizedDescription }
            }
            return
        }
        try refresh()
        if watching { startWatching() }
        if let first = notes.first { try select(first.path) }
    }

    public func url(for path: String) throws -> URL {
        guard let root else { throw NoteError.noLibrary }
        let result = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard result.path.hasPrefix(root.path + "/"), !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { throw NoteError.outsideLibrary }
        return result
    }

    public func refresh() throws {
        guard let root else { return }
        apply(try LibraryScan.run(root: root, previous: scanCache))
    }

    private func apply(_ scan: LibraryScan) {
        scanCache = scan.cache
        if notes != scan.notes { notes = scan.notes }
        if folders != scan.folders { folders = scan.folders }
    }

    /// Rescans off the main thread, reusing unchanged bodies; overlapping requests coalesce into one more pass.
    public func refreshInBackground(then done: (() -> Void)? = nil) {
        guard let root else { return }
        if let done { scanCompletions.append(done) }
        if backgroundScan != nil { rescanPending = true; return }
        let previous = scanCache
        backgroundScan = Task { [weak self] in
            let scan = await Task.detached(priority: .userInitiated) { try? LibraryScan.run(root: root, previous: previous) }.value
            guard let self else { return }
            self.backgroundScan = nil
            if let scan, self.root == root { self.apply(scan) }
            if self.rescanPending { self.rescanPending = false; self.refreshInBackground(); return }
            let completions = self.scanCompletions; self.scanCompletions = []
            for completion in completions { completion() }
        }
    }

    /// Follows changes made by other tools while the app stays open.
    public func startWatching() {
        guard watcher == nil, let root else { return }
        let watcher = FileWatcher(root: root) { [weak self] paths in self?.externalChange(paths) }
        watcher.start()
        self.watcher = watcher
    }

    public func stopWatching() { watcher?.stop(); watcher = nil }

    /// Library-relative paths of every change, hidden app files included.
    @discardableResult public func observeChanges(_ handler: @escaping ([String]) -> Void) -> UUID {
        let token = UUID(); observers[token] = handler; return token
    }
    public func removeObserver(_ token: UUID) { observers[token] = nil }

    private func externalChange(_ paths: [String]) {
        for observer in observers.values { observer(paths) }
        if paths.contains(where: { !$0.split(separator: "/").contains { $0.hasPrefix(".") } }) { refreshInBackground() }
        guard let current, paths.contains(current) || paths.contains((current as NSString).deletingLastPathComponent),
              let location = try? url(for: current) else { return }
        guard FileManager.default.fileExists(atPath: location.path) else {
            // Moved or trashed by another tool: a clean editor lets go; unsaved input stays for the user to keep.
            if !dirty { self.current = nil; text = ""; baseline = nil; revision += 1 }
            return
        }
        guard let disk = try? Data(contentsOf: location), disk != baseline else { return }
        if dirty { saveState = "保存冲突"; error = NoteError.conflict.localizedDescription; return }
        do { try reloadFromDisk() } catch { self.error = error.localizedDescription }
    }

    public var visibleNotes: [Note] {
        let filtered = notes.filter { n in
            let folderMatches = selectedFolder.map { folder in
                query.isEmpty ? n.folder == folder : Self.contains(n.folder, in: folder)
            } ?? true
            let recentMatches = !recentsOnly || recent.contains(n.path)
            guard folderMatches && recentMatches else { return false }
            guard !query.isEmpty else { return true }
            if n.title.localizedCaseInsensitiveContains(query) { return true }
            return (n.path == current ? text : scanCache[n.path]?.body ?? "").localizedCaseInsensitiveContains(query)
        }
        return recentsOnly ? filtered.sorted { (recent.firstIndex(of: $0.path) ?? .max) < (recent.firstIndex(of: $1.path) ?? .max) } : filtered
    }

    /// Search is independent of the active directory and recent-list filter.
    public func searchNotes(_ query: String, in folder: String? = nil) -> [Note] {
        notes.filter { note in
            guard folder.map({ Self.contains(note.folder, in: $0) }) ?? true else { return false }
            return query.isEmpty || note.title.localizedCaseInsensitiveContains(query)
                || (note.path == current ? text : scanCache[note.path]?.body ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private static func contains(_ child: String, in folder: String) -> Bool {
        folder.isEmpty || child == folder || child.hasPrefix(folder + "/")
    }

    public var creationFolder: String { selectedFolder ?? current.map { ($0 as NSString).deletingLastPathComponent } ?? "" }

    public var childFolders: [String] {
        guard let selectedFolder, !recentsOnly else { return [] }
        return folders.filter { ($0 as NSString).deletingLastPathComponent == selectedFolder }
    }

    public func select(_ path: String) throws {
        try save()
        let u = try url(for: path)
        let data = try Data(contentsOf: u)
        guard let body = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        current = path; text = body; baseline = data; dirty = false; revision += 1
        recent.removeAll { $0 == path }; recent.insert(path, at: 0); recent = Array(recent.prefix(40))
        persistRecent()
        revealCurrent()
    }

    private func revealCurrent() {
        guard let current else { return }
        if selectedFolder != nil { selectedFolder = (current as NSString).deletingLastPathComponent }
        if !query.isEmpty { query = "" }
    }

    public func createNote(title: String = "未命名笔记", folder: String? = nil) throws {
        try save()
        try validateName(title)
        let dir = folder ?? selectedFolder ?? ""
        var name = title, number = 2
        while FileManager.default.fileExists(atPath: try url(for: dir.isEmpty ? name + ".md" : dir + "/" + name + ".md").path) {
            name = "\(title) \(number)"; number += 1
        }
        let path = dir.isEmpty ? name + ".md" : dir + "/" + name + ".md"
        try Data("# \(name)\n\n".utf8).write(to: url(for: path), options: .withoutOverwriting)
        try refresh(); try select(path)
    }

    public func edit(_ value: String) {
        guard value != text else { return }
        text = value; dirty = true; saveState = "正在保存…"
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            do { try self.save() } catch { self.error = error.localizedDescription; self.saveState = "未保存" }
        }
    }

    public func save() throws {
        guard dirty, let current else { return }
        autosave?.cancel()
        let u = try url(for: current)
        let disk = try Data(contentsOf: u)
        guard disk == baseline else { saveState = "保存冲突"; throw NoteError.conflict }
        let data = Data(text.utf8)
        try data.write(to: u, options: .atomic)
        baseline = data; dirty = false; saveState = "已保存"
        try refresh()
    }


    public func resolveFile(_ raw: String) -> URL? {
        guard let root else { return nil }
        let target = raw.components(separatedBy: "|")[0].components(separatedBy: "#")[0].removingPercentEncoding ?? raw
        guard !target.isEmpty, !target.contains("://") else { return nil }
        let parent = current.map { root.appendingPathComponent($0).deletingLastPathComponent() } ?? root
        for base in [parent, root] {
            let candidate = base.appendingPathComponent(target).standardizedFileURL.resolvingSymlinksInPath()
            if candidate.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: candidate.path) {
                let relative = String(candidate.path.dropFirst(root.path.count + 1))
                if let safe = try? url(for: relative) { return safe }
            }
        }
        return nil
    }

    public func followLink(_ raw: String) throws {
        guard let root else { throw NoteError.noLibrary }
        let target = raw.components(separatedBy: "|")[0].components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
        if target.isEmpty { return }
        let named = target.lowercased().hasSuffix(".md") ? target : target + ".md"
        if let u = resolveFile(named) {
            try select(String(u.path.dropFirst(root.path.count + 1))); return
        }
        guard !target.contains("/") else { throw NoteError.missing(target) }
        let title = target.lowercased().hasSuffix(".md") ? String(target.dropLast(3)) : target
        let candidates = notes.filter { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
        guard candidates.count == 1, let match = candidates.first else {
            if candidates.count > 1 { throw NSError(domain: "NotesLite", code: 2, userInfo: [NSLocalizedDescriptionKey: "有多篇同名笔记，请使用包含文件夹的完整链接。"] ) }
            throw NoteError.missing(target)
        }
        try select(match.path)
    }


    public func saveCopy(title: String) throws {
        try validateName(title)
        guard let current, let root else { throw NoteError.noLibrary }
        let newPath = title + ".md"
        let destination = try url(for: newPath)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw NoteError.exists(title) }
        let source = try url(for: current)
        let copied = References.updating(text, document: source, destination: destination, old: source, new: source, root: root, notes: notes)
        try Data(copied.utf8).write(to: destination, options: .withoutOverwriting)
        autosave?.cancel(); dirty = false; saveState = "已保存"
        try refresh(); try select(newPath)
    }

    /// Only invoked after the user explicitly chooses to discard their local edits.
    public func reloadFromDisk() throws {
        guard let current else { return }
        let data = try Data(contentsOf: url(for: current))
        guard let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        autosave?.cancel(); text = value; baseline = data; dirty = false; saveState = "已保存"; revision += 1
        try refresh()
    }

    public func checkExternalChanges() throws {
        guard let current else { try refresh(); return }
        let disk = try Data(contentsOf: url(for: current))
        if disk != baseline {
            if dirty { throw NoteError.conflict }
            try reloadFromDisk()
        }
        try refresh()
    }


    public func createFolder(_ name: String, folder: String? = nil) throws {
        try validateName(name)
        let parent = folder ?? selectedFolder ?? ""
        let path = parent.isEmpty ? name : parent + "/" + name
        let folder = try url(for: path)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw NoteError.exists(name) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try refresh()
    }

    public func importAttachment(data: Data, name: String) throws -> String {
        guard let current else { throw NoteError.noLibrary }
        try validateName(name)
        let folder = try url(for: "附件")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = URL(fileURLWithPath: name)
        let ext = original.pathExtension
        let base = original.deletingPathExtension().lastPathComponent
        var finalName = name, number = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(finalName).path) {
            finalName = "\(base) \(number)" + (ext.isEmpty ? "" : "." + ext); number += 1
        }
        let destination = try url(for: "附件/" + finalName)
        try data.write(to: destination, options: .withoutOverwriting)
        let parent = try url(for: current).deletingLastPathComponent()
        let relative = References.relativePath(to: destination, from: parent)
        let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#()[] "))) ?? relative
        let image = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "svg"].contains(ext.lowercased())
        return (image ? "!" : "") + "[" + finalName.replacingOccurrences(of: "]", with: "") + "](" + encoded + ")"
    }

    public func importAttachment(from url: URL) throws -> String {
        try importAttachment(data: Data(contentsOf: url), name: url.lastPathComponent)
    }

    public func renameCurrent(title: String) throws {
        try validateName(title)
        guard let current else { throw NoteError.noLibrary }
        let parent = (current as NSString).deletingLastPathComponent
        try relocateCurrent(to: (parent.isEmpty ? "" : parent + "/") + title + ".md")
    }

    public func relocateCurrent(to newPath: String) throws {
        try save()
        guard let oldPath = current, let root else { throw NoteError.noLibrary }
        let oldURL = try url(for: oldPath), newURL = try url(for: newPath)
        guard newPath.lowercased().hasSuffix(".md") else { throw NoteError.invalidName }
        try validateName(newURL.lastPathComponent)
        if oldURL == newURL { return }
        guard !FileManager.default.fileExists(atPath: newURL.path) else { throw NoteError.exists(newURL.lastPathComponent) }
        try NoteRelocation.move(root: root, notes: notes, from: oldURL, to: newURL)
        try? SpaceLibrary(root: root).syncPaths(from: oldPath, to: newPath)
        current = newPath
        recent = recent.map { $0 == oldPath ? newPath : $0 }; persistRecent()
        try refresh(); try select(newPath)
    }

    public func deleteCurrent() throws {
        try save()
        guard let current else { return }
        let source = try url(for: current)
        var trashed: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &trashed)
        if let trashed { lastDeleted = (current, trashed as URL) }
        recent.removeAll { $0 == current }; persistRecent()
        self.current = nil; text = ""; baseline = nil; revision += 1
        try refresh()
        if let next = notes.first { try select(next.path) }
    }

    public func restoreDeleted() throws {
        guard let deleted = lastDeleted else { return }
        let destination = try url(for: deleted.path)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw NoteError.exists(deleted.path) }
        try FileManager.default.moveItem(at: deleted.url, to: destination)
        lastDeleted = nil
        try refresh(); try select(deleted.path)
    }

    private func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"), !name.contains("\n") else { throw NoteError.invalidName }
    }
    private func persistRecent() { if let root { defaults?.set(recent, forKey: "recent.\(root.path)") } }
}
