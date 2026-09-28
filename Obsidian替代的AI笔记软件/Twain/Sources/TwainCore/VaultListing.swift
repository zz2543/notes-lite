import Foundation

/// Everything in a vault folder from one walk: notes with their dates, folders, and the other
/// files by name. The sidebar, the index and the before/after snapshot of an agent run all
/// start from this, so the folder is walked once rather than once for each of them.
public struct VaultListing: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let rel: String
        public let stamp: Date?
        public let size: Int

        public init(rel: String, stamp: Date?, size: Int) {
            self.rel = rel
            self.stamp = stamp
            self.size = size
        }
    }

    /// Markdown and HTML notes, in sidebar order.
    public var notes: [Entry] = []
    public var folders: [String] = []
    /// Non-note files by lowercased file name, for resolving `![[name.png]]` like Obsidian does.
    public var attachments: [String: [String]] = [:]
    public var isGitRepo = false

    public init() {}

    public static let htmlExtensions: Set<String> = ["html", "htm"]
    public static let noteExtensions: Set<String> = ["md", "html", "htm"]

    public static func isNote(_ rel: String) -> Bool {
        noteExtensions.contains((rel as NSString).pathExtension.lowercased())
    }

    /// The sidebar's order: Finder's, numbers by value.
    public static func before(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    /// Walks `root` (already standardized) skipping hidden files, packages and `node_modules`.
    /// Paths are taken relative to the root as the enumerator reports them; only a path outside
    /// it (a symlinked folder) is resolved, since resolving every file is what made walks slow.
    public static func walk(_ root: URL) -> VaultListing {
        let fm = FileManager.default
        var out = VaultListing()
        out.isGitRepo = fm.fileExists(atPath: root.appendingPathComponent(".git").path)
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return out
        }
        for case let u as URL in e {
            var path = u.path
            if !path.hasPrefix(base) { path = u.standardizedFileURL.resolvingSymlinksInPath().path }
            guard path.hasPrefix(base) else { continue }
            let rel = String(path.dropFirst(base.count))
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true {
                if u.lastPathComponent == "node_modules" { e.skipDescendants(); continue }
                out.folders.append(rel)
            } else if noteExtensions.contains(u.pathExtension.lowercased()) {
                out.notes.append(Entry(rel: rel, stamp: v?.contentModificationDate, size: v?.fileSize ?? 0))
            } else {
                out.attachments[u.lastPathComponent.lowercased(), default: []].append(rel)
            }
        }
        out.notes.sort { before($0.rel, $1.rel) }
        out.folders.sort(by: before)
        return out
    }

    // MARK: changes Twain makes itself, applied without walking the folder again

    public mutating func insertNote(_ rel: String, stamp: Date? = Date(), size: Int = 0) {
        notes.removeAll { $0.rel == rel }
        let e = Entry(rel: rel, stamp: stamp, size: size)
        let i = notes.firstIndex { Self.before(rel, $0.rel) } ?? notes.endIndex
        notes.insert(e, at: i)
        insertFolder((rel as NSString).deletingLastPathComponent)
    }

    public mutating func removeNote(_ rel: String) {
        notes.removeAll { $0.rel == rel }
    }

    /// Adds `folder` and the folders above it.
    public mutating func insertFolder(_ folder: String) {
        var f = folder
        while !f.isEmpty {
            if !folders.contains(f) {
                let i = folders.firstIndex { Self.before(f, $0) } ?? folders.endIndex
                folders.insert(f, at: i)
            }
            f = (f as NSString).deletingLastPathComponent
        }
    }

    public mutating func insertAttachment(_ rel: String) {
        let name = (rel as NSString).lastPathComponent.lowercased()
        if attachments[name]?.contains(rel) != true { attachments[name, default: []].append(rel) }
        insertFolder((rel as NSString).deletingLastPathComponent)
    }

    /// A folder moved: everything under it moves along.
    public mutating func moveFolder(_ old: String, to new: String) {
        func moved(_ rel: String) -> String? {
            rel == old ? new : rel.hasPrefix(old + "/") ? new + rel.dropFirst(old.count) : nil
        }
        folders = folders.map { moved($0) ?? $0 }.sorted(by: Self.before)
        notes = notes.map { e in moved(e.rel).map { Entry(rel: $0, stamp: e.stamp, size: e.size) } ?? e }.sorted { Self.before($0.rel, $1.rel) }
        attachments = attachments.mapValues { $0.map { moved($0) ?? $0 } }
    }
}
