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
    /// Non-note files by lowercased file name, for resolving `![[name.png]]` like Obsidian does.
    @ObservationIgnored private(set) var attachments: [String: [String]] = [:]
    /// Each folder's subfolders and notes, in sidebar order ("" is the root).
    private(set) var tree: [String: (folders: [String], notes: [NoteRef])] = [:]
    @ObservationIgnored private var byRel: [String: NoteRef] = [:]
    @ObservationIgnored private var scanWork: DispatchWorkItem?
    @ObservationIgnored private var scanGeneration = 0
    private(set) var isGitRepo = false

    @ObservationIgnored private(set) var known: [String: String] = [:]
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored var onFilesChanged: (([String]) -> Void)?
    /// `.twain/commands` or `.twain/automations` changed.
    @ObservationIgnored var onTwainFilesChanged: ((Set<String>) -> Void)?

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

    struct Listing {
        var notes: [NoteRef] = []
        var folders: [String] = []
        var attachments: [String: [String]] = [:]
        var isGitRepo = false
    }

    /// Everything under the root; safe to call off the main thread.
    static func list(_ root: URL) -> Listing {
        let fm = FileManager.default
        var out = Listing()
        out.isGitRepo = fm.fileExists(atPath: root.appendingPathComponent(".git").path)
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let u as URL in e {
                let p = u.standardizedFileURL.resolvingSymlinksInPath().path
                guard p.hasPrefix(base) else { continue }
                let rel = String(p.dropFirst(base.count))
                if (try? u.resourceValues(forKeys: Set(keys)).isDirectory) == true {
                    if u.lastPathComponent == "node_modules" { e.skipDescendants(); continue }
                    out.folders.append(rel)
                } else if u.pathExtension.lowercased() == "md" {
                    out.notes.append(NoteRef(rel: rel))
                } else {
                    out.attachments[u.lastPathComponent.lowercased(), default: []].append(rel)
                }
            }
        }
        let cmp: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        out.notes.sort { cmp($0.rel, $1.rel) }
        out.folders.sort(by: cmp)
        return out
    }

    private func apply(_ l: Listing) {
        isGitRepo = l.isGitRepo
        attachments = l.attachments
        byRel = Dictionary(l.notes.map { ($0.rel, $0) }, uniquingKeysWith: { a, _ in a })
        var t: [String: (folders: [String], notes: [NoteRef])] = ["": ([], [])]
        for f in l.folders {
            t[f, default: ([], [])] = t[f] ?? ([], [])
            t[(f as NSString).deletingLastPathComponent, default: ([], [])].folders.append(f)
        }
        for n in l.notes { t[n.folder, default: ([], [])].notes.append(n) }
        if l.notes != notes { notes = l.notes }
        if l.folders != folders { folders = l.folders }
        let same = tree.count == t.count && t.allSatisfy { k, v in tree[k].map { $0.folders == v.folders && $0.notes == v.notes } ?? false }
        if !same { tree = t }
    }

    /// Re-reads the folder now. File events use `scanSoon` instead.
    func scan() {
        scanGeneration += 1
        apply(Self.list(root))
    }

    /// Re-reads the folder in the background, coalescing bursts of file events.
    func scanSoon(then done: (() -> Void)? = nil) {
        scanWork?.cancel()
        scanGeneration += 1
        let gen = scanGeneration, root = root
        let w = DispatchWorkItem { [weak self] in
            let l = Self.list(root)
            DispatchQueue.main.async {
                guard let self, gen == self.scanGeneration else { return }
                self.apply(l)
                done?()
            }
        }
        scanWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    func relative(_ path: String) -> String {
        let p = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let r = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return p.hasPrefix(r) ? String(p.dropFirst(r.count)) : p
    }

    func note(_ rel: String) -> NoteRef? { byRel[rel] }

    /// `name.png`, `folder/name.png` or `name.png|300` → the file's path in the vault.
    func attachment(_ target: String, from noteRel: String?) -> String? {
        var t = target.split(separator: "|", maxSplits: 1).first.map(String.init) ?? target
        t = t.trimmingCharacters(in: .whitespaces)
        t = t.removingPercentEncoding ?? t
        if t.hasPrefix("/") { t.removeFirst() }
        if let noteRel {
            let here = ((noteRel as NSString).deletingLastPathComponent as NSString).appendingPathComponent(t)
            let clean = (here as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: url(clean).path) { return clean }
        }
        if FileManager.default.fileExists(atPath: url(t).path) { return t }
        let name = (t as NSString).lastPathComponent.lowercased()
        let hits = attachments[name] ?? []
        // Obsidian's rule: a partial path narrows the match, the shortest path wins ties.
        return hits.filter { $0.lowercased().hasSuffix(t.lowercased()) }.min { $0.count < $1.count } ?? hits.min { $0.count < $1.count }
    }

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

    func forget(_ rel: String) { known[rel] = nil }

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

    func snapshotAll() -> VaultSnapshot { VaultSnapshot.take(root: root, rels: notes.map(\.rel)) }

    func noteCount(in folder: String) -> Int { tree[folder]?.notes.count ?? 0 }

    private func handleEvents(_ paths: [String]) {
        let all = Set(paths.map(relative))
        // Hidden folders are not notes; Twain's own config lives in one of them.
        let visible = all.filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
        let rels = visible.filter { $0.lowercased().hasSuffix(".md") }
        if !visible.isEmpty {
            scanSoon { [weak self] in if !rels.isEmpty { self?.onFilesChanged?(Array(rels)) } }
        }
        if all.contains(where: { $0.hasPrefix(".twain/") }) { onTwainFilesChanged?(all.filter { $0.hasPrefix(".twain/") }) }
    }
}

/// The notes as they were before an agent ran. Taken and compared off the main thread: a vault
/// can hold hundreds of notes, some in iCloud and slow to read.
struct VaultSnapshot: Sendable {
    let root: URL
    var files: [String: (stamp: Date?, text: String?)]

    static func stamp(_ u: URL) -> Date? {
        try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func take(root: URL, rels: [String]) -> VaultSnapshot {
        var files: [String: (Date?, String?)] = [:]
        for rel in rels {
            let u = root.appendingPathComponent(rel)
            files[rel] = (stamp(u), try? String(contentsOf: u, encoding: .utf8))
        }
        return VaultSnapshot(root: root, files: files)
    }

    /// Notes whose file changed since the snapshot (new ones included), with before and after.
    func changes() -> [(rel: String, before: String?, after: String?)] {
        var rels = Set(files.keys)
        let fm = FileManager.default
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
            for case let u as URL in e where u.pathExtension.lowercased() == "md" {
                let p = u.standardizedFileURL.resolvingSymlinksInPath().path
                if p.hasPrefix(base) { rels.insert(String(p.dropFirst(base.count))) }
            }
        }
        var out: [(String, String?, String?)] = []
        for rel in rels.sorted() {
            let u = root.appendingPathComponent(rel)
            let old = files[rel]
            let now = Self.stamp(u)
            if let old, old.stamp == now, now != nil { continue }
            let after = try? String(contentsOf: u, encoding: .utf8)
            if after != old?.text { out.append((rel, old?.text, after)) }
        }
        return out
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
