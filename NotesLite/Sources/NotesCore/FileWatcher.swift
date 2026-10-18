import CoreServices
import Foundation

/// Continuous FSEvents watching of one library, reporting library-relative paths (hidden ones included).
/// Events are delivered on the main queue, already coalesced by FSEvents' latency window.
public final class FileWatcher: @unchecked Sendable {
    private let root: URL
    private let handler: @MainActor ([String]) -> Void
    private var stream: FSEventStreamRef?

    public init(root: URL, handler: @escaping @MainActor ([String]) -> Void) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.handler = handler
    }

    deinit { stop() }

    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let raw = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.deliver(Array(raw.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags) else { return }
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
        stream = created
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func deliver(_ absolute: [String]) {
        // FSEvents reports real paths (`/private/var/…`), while a resolved root may omit `/private`.
        let prefixes = [root.path + "/", root.path.hasPrefix("/private/") ? String(root.path.dropFirst(8)) + "/" : "/private" + root.path + "/"]
        var relative: [String] = []
        for path in absolute {
            guard let prefix = prefixes.first(where: { path.hasPrefix($0) }) else { continue }
            let item = String(path.dropFirst(prefix.count))
            if !relative.contains(item) { relative.append(item) }
        }
        guard !relative.isEmpty else { return }
        MainActor.assumeIsolated { handler(relative) }
    }
}

/// One pass over a library's visible Markdown, reusing bodies whose modification date and size are unchanged.
struct LibraryScan: Sendable {
    struct Cached: Sendable { var modified: Date; var size: Int; var body: String }
    var notes: [Note] = []
    var folders: [String] = []
    var cache: [String: Cached] = [:]

    static func run(root: URL, previous: [String: Cached]) throws -> LibraryScan {
        var result = LibraryScan()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return result }
        for case let u as URL in entries {
            let values = try u.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { entries.skipDescendants(); continue }
            let canonicalPath = u.resolvingSymlinksInPath().path
            guard canonicalPath.hasPrefix(root.path + "/") else { continue }
            let relative = String(canonicalPath.dropFirst(root.path.count + 1))
            if values.isDirectory == true { result.folders.append(relative); continue }
            guard u.pathExtension.lowercased() == "md" else { continue }
            let modified = values.contentModificationDate ?? .distantPast, size = values.fileSize ?? -1
            let body: String
            if let hit = previous[relative], hit.modified == modified, hit.size == size { body = hit.body }
            else { body = (try? String(contentsOf: u, encoding: .utf8)) ?? "" }
            result.cache[relative] = Cached(modified: modified, size: size, body: body)
            result.notes.append(Note(path: relative, modified: modified, preview: NotePreview.text(body)))
        }
        result.notes.sort { $0.modified > $1.modified }
        result.folders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return result
    }
}
