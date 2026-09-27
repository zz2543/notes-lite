import CoreServices
import Foundation
import Observation

struct NoteRef: Hashable, Identifiable {
    let rel: String
    var id: String { rel }
    var title: String { ((rel as NSString).lastPathComponent as NSString).deletingPathExtension }
    var folder: String { (rel as NSString).deletingLastPathComponent }
    /// Root-level agent files are listed with their extension, like the prototype does.
    var isAgentFile: Bool { folder.isEmpty && (title == "AGENTS" || title == "CLAUDE") }
    var displayName: String { isAgentFile ? title + ".md" : title }
}

/// A folder on disk full of Markdown files. Twain keeps no database: `known` is only
/// the last content Twain itself read or wrote, used to tell our writes from other writers.
@Observable
final class Vault {
    let root: URL
    private(set) var notes: [NoteRef] = []
    private(set) var folders: [String] = []
    private(set) var isGitRepo = false

    @ObservationIgnored private(set) var known: [String: String] = [:]
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored var onFilesChanged: (([String]) -> Void)?
    /// `.twain/commands` or `.twain/automations` changed.
    @ObservationIgnored var onTwainFilesChanged: (() -> Void)?

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        scan()
        watcher = FileWatcher(path: self.root.path) { [weak self] paths in
            self?.handleEvents(paths)
        }
    }

    var rootPath: String { root.path }
    var displayPath: String { (rootPath as NSString).abbreviatingWithTildeInPath }
    var name: String { root.lastPathComponent }

    func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }

    func scan() {
        let fm = FileManager.default
        isGitRepo = fm.fileExists(atPath: root.appendingPathComponent(".git").path)
        var found: [NoteRef] = []
        var dirs: [String] = []
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let u as URL in e {
                let rel = relative(u.path)
                if (try? u.resourceValues(forKeys: Set(keys)).isDirectory) == true {
                    if ["node_modules"].contains(u.lastPathComponent) { e.skipDescendants(); continue }
                    dirs.append(rel)
                } else if u.pathExtension.lowercased() == "md" {
                    found.append(NoteRef(rel: rel))
                }
            }
        }
        let cmp: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        notes = found.sorted { cmp($0.rel, $1.rel) }
        folders = dirs.sorted(by: cmp)
    }

    func relative(_ path: String) -> String {
        let p = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let r = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return p.hasPrefix(r) ? String(p.dropFirst(r.count)) : p
    }

    func note(_ rel: String) -> NoteRef? { notes.first { $0.rel == rel } }

    func note(titled title: String) -> NoteRef? {
        notes.first { $0.title == title } ?? notes.first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
    }

    func diskContent(_ rel: String) -> String? {
        try? String(contentsOf: url(rel), encoding: .utf8)
    }

    func knownContent(_ rel: String) -> String? { known[rel] }

    @discardableResult
    func read(_ rel: String) -> String {
        let text = diskContent(rel) ?? ""
        known[rel] = text
        return text
    }

    /// Marks the current disk content as seen without changing the editor.
    func acknowledge(_ rel: String, content: String?) {
        known[rel] = content
    }

    enum WriteResult { case ok, conflict(String) }

    /// Writes only if nobody else changed the file since we last saw it.
    func write(_ rel: String, _ text: String) -> WriteResult {
        if let disk = diskContent(rel), let k = known[rel], disk != k, disk != text {
            return .conflict(disk)
        }
        forceWrite(rel, text)
        return .ok
    }

    func forceWrite(_ rel: String, _ text: String) {
        let u = url(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        known[rel] = text
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    func uniqueRel(title: String, folder: String) -> String {
        var n = 1
        while true {
            let name = n == 1 ? title : "\(title) \(n)"
            let rel = folder.isEmpty ? name + ".md" : folder + "/" + name + ".md"
            if !FileManager.default.fileExists(atPath: url(rel).path) { return rel }
            n += 1
        }
    }

    func create(title: String, folder: String = "", content: String) -> String {
        let rel = uniqueRel(title: title, folder: folder)
        forceWrite(rel, content)
        scan()
        return rel
    }

    enum RenameError: LocalizedError {
        case empty, invalid, taken(String)
        var errorDescription: String? {
            switch self {
            case .empty: "名字不能为空"
            case .invalid: "名字不能包含 / 或 :，也不能以 . 开头"
            case let .taken(n): "已经有一篇叫「\(n)」的笔记"
            }
        }
    }

    /// Moves `rel` to `title`.md in the same folder and returns the new path. The file keeps
    /// what we last knew of it, so the move is not mistaken for someone else's edit.
    func rename(_ rel: String, to title: String) throws -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw RenameError.empty }
        guard !t.contains("/"), !t.contains(":"), !t.hasPrefix(".") else { throw RenameError.invalid }
        let folder = (rel as NSString).deletingLastPathComponent
        let new = folder.isEmpty ? t + ".md" : folder + "/" + t + ".md"
        if new == rel { return rel }
        // A case-only change is the same file on a case-insensitive disk.
        if new.lowercased() != rel.lowercased(), FileManager.default.fileExists(atPath: url(new).path) {
            throw RenameError.taken(t)
        }
        try FileManager.default.moveItem(at: url(rel), to: url(new))
        known[new] = known.removeValue(forKey: rel)
        scan()
        return new
    }

    func snapshotAll() -> [String: String] {
        var out: [String: String] = [:]
        for n in notes { out[n.rel] = diskContent(n.rel) }
        return out
    }

    func noteCount(in folder: String) -> Int { notes.filter { $0.folder == folder }.count }

    private func handleEvents(_ paths: [String]) {
        scan()
        let all = Set(paths.map(relative))
        // Hidden folders are not notes; Twain's own config lives in one of them.
        let rels = all.filter { $0.lowercased().hasSuffix(".md") && !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
        if !rels.isEmpty { onFilesChanged?(Array(rels)) }
        if all.contains(where: { $0.hasPrefix(".twain/commands") || $0.hasPrefix(".twain/automations") }) { onTwainFilesChanged?() }
    }
}

/// FSEvents with file-level granularity, delivered on the main queue.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let callback: ([String]) -> Void

    init(path: String, callback: @escaping ([String]) -> Void) {
        self.callback = callback
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let arr = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            me.callback(Array(arr.prefix(count)))
        }, &ctx, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
