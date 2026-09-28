import CoreServices
import Foundation
import Observation

public struct NoteRef: Hashable, Identifiable, Sendable {
    public let rel: String
    public init(rel: String) { self.rel = rel }
    public var id: String { rel }
    public var title: String { ((rel as NSString).lastPathComponent as NSString).deletingPathExtension }
    public var folder: String { (rel as NSString).deletingLastPathComponent }
    /// Root-level agent files are listed with their extension, like the prototype does.
    public var isAgentFile: Bool { folder.isEmpty && (title == "AGENTS" || title == "CLAUDE") }
    public var displayName: String { isAgentFile ? title + ".md" : title }
    /// An HTML note: rendered as a page, edited as source.
    public var isHTML: Bool { VaultListing.htmlExtensions.contains((rel as NSString).pathExtension.lowercased()) }
    public var ext: String { (rel as NSString).pathExtension }
}

/// A folder on disk full of Markdown files. Twain keeps no database: `known` is only
/// the last content Twain itself read or wrote, used to tell our writes from other writers.
///
/// The folder is walked by a `VaultService` off the main thread whenever files change; what
/// Twain changes itself (a new note, a rename, a move) is applied to the listing right away,
/// so the sidebar never waits for a walk.
@MainActor @Observable
public final class Vault {
    public let root: URL
    public private(set) var notes: [NoteRef] = []
    public private(set) var folders: [String] = []
    /// Non-note files by lowercased file name, for resolving `![[name.png]]` like Obsidian does.
    @ObservationIgnored public private(set) var attachments: [String: [String]] = [:]
    /// Each folder's subfolders and notes, in sidebar order ("" is the root).
    public private(set) var tree: [String: Node] = [:]
    public private(set) var isGitRepo = false

    public struct Node: Equatable, Sendable {
        public var folders: [String] = []
        public var notes: [NoteRef] = []
    }

    @ObservationIgnored private var listing = VaultListing()
    @ObservationIgnored private var byRel: [String: NoteRef] = [:]
    @ObservationIgnored private var scanWork: DispatchWorkItem?
    /// Bumped by every change applied to the listing, so a walk that started before it is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored public private(set) var known: [String: String] = [:]
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored public let service: VaultService
    /// Note files that changed on disk (by anyone, Twain included; compare with `knownContent`).
    @ObservationIgnored public var onFilesChanged: (([String]) -> Void)?
    /// Files under `.twain/` changed.
    @ObservationIgnored public var onTwainFilesChanged: ((Set<String>) -> Void)?
    /// A new index after a walk of the folder.
    @ObservationIgnored public var onIndex: ((VaultIndex) -> Void)?

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        let first = VaultListing.walk(self.root)
        service = VaultService(root: self.root, listing: first)
        apply(first)
        watcher = FileWatcher(path: self.root.path) { [weak self] paths in
            MainActor.assumeIsolated { self?.handleEvents(paths) }
        }
    }

    public var rootPath: String { root.path }
    public var displayPath: String { (rootPath as NSString).abbreviatingWithTildeInPath }
    public var name: String { root.lastPathComponent }

    public func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }

    public static let htmlExtensions = VaultListing.htmlExtensions
    public static let noteExtensions = VaultListing.noteExtensions

    private func apply(_ l: VaultListing) {
        listing = l
        isGitRepo = l.isGitRepo
        attachments = l.attachments
        let refs = l.notes.map { NoteRef(rel: $0.rel) }
        byRel = Dictionary(refs.map { ($0.rel, $0) }, uniquingKeysWith: { a, _ in a })
        var t: [String: Node] = ["": Node()]
        for f in l.folders {
            if t[f] == nil { t[f] = Node() }
            t[(f as NSString).deletingLastPathComponent, default: Node()].folders.append(f)
        }
        for n in refs { t[n.folder, default: Node()].notes.append(n) }
        if refs != notes { notes = refs }
        if l.folders != folders { folders = l.folders }
        if t != tree { tree = t }
    }

    /// Changes the listing for something Twain just did on disk, then checks with a walk.
    private func change(_ edit: (inout VaultListing) -> Void) {
        var l = listing
        edit(&l)
        generation += 1
        apply(l)
        scanSoon()
    }

    /// Note files reported changed since the last walk, delivered together after it.
    @ObservationIgnored private var changedSinceWalk = Set<String>()
    @ObservationIgnored private var afterWalk: [(VaultIndex) -> Void] = []

    /// Walks the folder in the background (bursts of file events share one walk) and applies
    /// the result; `done` runs on the main thread after it, with the fresh index.
    public func scanSoon(delay: TimeInterval = 0.15, then done: ((VaultIndex) -> Void)? = nil) {
        if let done { afterWalk.append(done) }
        scanWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.refresh() }
        scanWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    /// Walks the folder now (off the main thread) and calls `done` with the result.
    public func refresh(_ done: ((VaultIndex) -> Void)? = nil) {
        scanWork?.cancel()
        scanWork = nil
        if let done { afterWalk.append(done) }
        let gen = generation
        service.refresh { [weak self] listing, index in
            DispatchQueue.main.async {
                guard let self else { return }
                // Something Twain did since the walk started is newer than the walk.
                if gen == self.generation { self.apply(listing) }
                self.onIndex?(index)
                let changed = self.changedSinceWalk
                self.changedSinceWalk = []
                let callbacks = self.afterWalk
                self.afterWalk = []
                if !changed.isEmpty { self.onFilesChanged?(changed.sorted()) }
                for c in callbacks { c(index) }
            }
        }
    }

    public func relative(_ path: String) -> String {
        let r = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(r) { return String(path.dropFirst(r.count)) }
        let p = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return p.hasPrefix(r) ? String(p.dropFirst(r.count)) : p
    }

    public func note(_ rel: String) -> NoteRef? { byRel[rel] }

    /// When the note file was last modified, as of the last walk.
    public func stamp(_ rel: String) -> Date? { listing.notes.first { $0.rel == rel }?.stamp }

    /// `name.png`, `folder/name.png` or `name.png|300` → the file's path in the vault.
    public func attachment(_ target: String, from noteRel: String?) -> String? {
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

    public func note(titled title: String) -> NoteRef? {
        notes.first { $0.title == title } ?? notes.first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
    }

    public nonisolated func diskContent(_ rel: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
    }

    public func knownContent(_ rel: String) -> String? { known[rel] }

    @discardableResult
    public func read(_ rel: String) -> String {
        let text = diskContent(rel) ?? ""
        known[rel] = text
        return text
    }

    public func forget(_ rel: String) { known[rel] = nil }

    /// Marks the current disk content as seen without changing the editor.
    public func acknowledge(_ rel: String, content: String?) {
        known[rel] = content
    }

    public enum WriteResult: Equatable, Sendable { case ok, conflict(String) }

    /// Writes only if nobody else changed the file since we last saw it.
    public func write(_ rel: String, _ text: String) -> WriteResult {
        if let disk = diskContent(rel), let k = known[rel], disk != k, disk != text {
            return .conflict(disk)
        }
        forceWrite(rel, text)
        return .ok
    }

    public func forceWrite(_ rel: String, _ text: String) {
        let u = url(rel)
        let isNew = !FileManager.default.fileExists(atPath: u.path)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        known[rel] = text
        try? text.write(to: u, atomically: true, encoding: .utf8)
        if isNew, VaultListing.isNote(rel), !rel.hasPrefix(".") { change { $0.insertNote(rel) } }
    }

    public func uniqueRel(title: String, folder: String, ext: String = "md") -> String {
        var n = 1
        while true {
            let name = n == 1 ? title : "\(title) \(n)"
            let rel = folder.isEmpty ? name + "." + ext : folder + "/" + name + "." + ext
            if !FileManager.default.fileExists(atPath: url(rel).path) { return rel }
            n += 1
        }
    }

    public func create(title: String, folder: String = "", content: String) -> String {
        let rel = uniqueRel(title: title, folder: folder)
        forceWrite(rel, content)
        return rel
    }

    /// A file Twain added that is not a note (a pasted picture).
    public func attachmentAdded(_ rel: String) {
        change { $0.insertAttachment(rel) }
    }

    /// A note Twain moved to the trash.
    public func noteRemoved(_ rel: String) {
        known[rel] = nil
        change { $0.removeNote(rel) }
    }

    /// A folder Twain moved to the trash.
    public func folderRemoved(_ folder: String) {
        for k in known.keys where k.hasPrefix(folder + "/") { known[k] = nil }
        change { l in
            l.notes.removeAll { $0.rel.hasPrefix(folder + "/") }
            l.folders.removeAll { $0 == folder || $0.hasPrefix(folder + "/") }
        }
    }

    public enum RenameError: LocalizedError, Equatable {
        case empty, invalid, taken(String)
        public var errorDescription: String? {
            switch self {
            case .empty: "名字不能为空"
            case .invalid: "名字不能包含 / 或 :，也不能以 . 开头"
            case let .taken(n): "已经有一篇叫「\(n)」的笔记"
            }
        }
    }

    /// Moves `rel` to `title`.md in the same folder and returns the new path. The file keeps
    /// what we last knew of it, so the move is not mistaken for someone else's edit.
    public func rename(_ rel: String, to title: String) throws -> String {
        let t = try Self.validName(title)
        let folder = (rel as NSString).deletingLastPathComponent
        let ext = (rel as NSString).pathExtension.isEmpty ? "md" : (rel as NSString).pathExtension
        let new = folder.isEmpty ? t + "." + ext : folder + "/" + t + "." + ext
        if new == rel { return rel }
        // A case-only change is the same file on a case-insensitive disk.
        if new.lowercased() != rel.lowercased(), FileManager.default.fileExists(atPath: url(new).path) {
            throw RenameError.taken(t)
        }
        try FileManager.default.moveItem(at: url(rel), to: url(new))
        known[new] = known.removeValue(forKey: rel)
        change { $0.removeNote(rel); $0.insertNote(new) }
        return new
    }

    // MARK: folders

    /// `Folder/Folder.md` when it exists.
    public func folderNote(_ folder: String) -> NoteRef? {
        guard !folder.isEmpty else { return nil }
        return note(folder + "/" + (folder as NSString).lastPathComponent + ".md")
    }

    public func isFolderNote(_ n: NoteRef) -> Bool {
        !n.folder.isEmpty && (n.folder as NSString).lastPathComponent == n.title
    }

    public static func validName(_ name: String) throws -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw RenameError.empty }
        guard !t.contains("/"), !t.contains(":"), !t.hasPrefix(".") else { throw RenameError.invalid }
        return t
    }

    public func createFolder(in parent: String, name: String) throws -> String {
        let t = try Self.validName(name)
        var rel = parent.isEmpty ? t : parent + "/" + t
        var n = 2
        while FileManager.default.fileExists(atPath: url(rel).path) {
            rel = (parent.isEmpty ? "" : parent + "/") + "\(t) \(n)"
            n += 1
        }
        try FileManager.default.createDirectory(at: url(rel), withIntermediateDirectories: true)
        change { $0.insertFolder(rel) }
        return rel
    }

    /// Renames the folder, and its folder note with it. Returns the new path.
    public func renameFolder(_ folder: String, to name: String) throws -> String {
        let t = try Self.validName(name)
        let parent = (folder as NSString).deletingLastPathComponent
        let new = parent.isEmpty ? t : parent + "/" + t
        guard new != folder else { return folder }
        if new.lowercased() != folder.lowercased(), FileManager.default.fileExists(atPath: url(new).path) {
            throw RenameError.taken(t)
        }
        let oldName = (folder as NSString).lastPathComponent
        let hadNote = folderNote(folder) != nil
        try FileManager.default.moveItem(at: url(folder), to: url(new))
        let oldNote = new + "/" + oldName + ".md", newNote = new + "/" + t + ".md"
        if hadNote {
            try? FileManager.default.moveItem(at: url(oldNote), to: url(newNote))
        }
        // What we knew of the files moves with them.
        for (k, v) in known where k.hasPrefix(folder + "/") {
            var nk = new + String(k.dropFirst(folder.count))
            if hadNote, nk == oldNote { nk = newNote }
            forget(k)
            acknowledge(nk, content: v)
        }
        change { l in
            l.moveFolder(folder, to: new)
            if hadNote { l.removeNote(oldNote); l.insertNote(newNote) }
        }
        return new
    }

    /// Moves a note into `folder`, keeping its name (numbered when taken). Returns the new path.
    public func move(_ rel: String, to folder: String) throws -> String {
        guard (rel as NSString).deletingLastPathComponent != folder else { return rel }
        let ref = NoteRef(rel: rel)
        let new = uniqueRel(title: ref.title, folder: folder, ext: ref.ext.isEmpty ? "md" : ref.ext)
        try FileManager.default.createDirectory(at: url(folder), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url(rel), to: url(new))
        let k = known[rel]
        forget(rel)
        acknowledge(new, content: k)
        change { $0.removeNote(rel); $0.insertNote(new) }
        return new
    }

    // MARK: file events

    private func handleEvents(_ paths: [String]) {
        let all = Set(paths.map(relative))
        // Hidden folders are not notes; Twain's own config lives in one of them.
        let visible = all.filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
        let rels = visible.filter(VaultListing.isNote)
        if !visible.isEmpty {
            changedSinceWalk.formUnion(rels)
            scanSoon()
        }
        if all.contains(where: { $0.hasPrefix(".twain/") }) { onTwainFilesChanged?(all.filter { $0.hasPrefix(".twain/") }) }
    }
}

/// The notes as they were before an agent ran. Taken and compared off the main thread: a vault
/// can hold hundreds of notes, some in iCloud and slow to read.
public struct VaultSnapshot: Sendable {
    public let root: URL
    public var files: [String: (stamp: Date?, text: String?)]

    public static func take(root: URL, rels: [String]) -> VaultSnapshot {
        var files: [String: (Date?, String?)] = [:]
        let stamps = Dictionary(VaultListing.walk(root).notes.map { ($0.rel, $0.stamp) }, uniquingKeysWith: { a, _ in a })
        for rel in rels {
            files[rel] = (stamps[rel] ?? nil, try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8))
        }
        return VaultSnapshot(root: root, files: files)
    }

    /// Notes whose file changed since the snapshot (new ones included), with before and after.
    public func changes() -> [(rel: String, before: String?, after: String?)] {
        let now = Dictionary(VaultListing.walk(root).notes.map { ($0.rel, $0.stamp) }, uniquingKeysWith: { a, _ in a })
        var out: [(String, String?, String?)] = []
        for rel in Set(files.keys).union(now.keys).sorted() {
            let old = files[rel]
            let stamp = now[rel] ?? nil
            if let old, old.stamp == stamp, stamp != nil { continue }
            let after = try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            if after != old?.text { out.append((rel, old?.text, after)) }
        }
        return out
    }
}

/// FSEvents with file-level granularity, delivered on the main queue.
public final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let callback: ([String]) -> Void

    public init(path: String, callback: @escaping ([String]) -> Void) {
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
