import Foundation

/// Every write a space homepage makes, kept in the library (`.留白/操作记录.json`) so it can be undone
/// one entry at a time, even after a restart. Record writes log one entry per record; entries expire after 30 days.
public final class OperationLog {
    public enum Kind: String, Codable, Sendable {
        case recordAppend, recordUpdate, recordRemove, noteCreate, noteWrite, noteRename, noteMove, noteTrash, pageWrite
    }

    /// A rewrite of another note made alongside a rename or move (updated links).
    public struct FileChange: Codable, Equatable, Sendable {
        public var path: String
        public var before: String
        public var after: String
    }

    public struct Entry: Codable, Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var date: Date
        public var space: String
        public var kind: Kind
        /// The note (or space file) written; for a rename or move, where it was before.
        public var path: String
        public var heading: String?
        public var header: [String]?
        /// Record cells, or a note's full text, before and after the write.
        public var before: [String]?
        public var after: [String]?
        public var row: Int?
        public var newPath: String?
        public var trashed: String?
        public var related: [FileChange]?
        public var undone = false

        public var summary: String {
            let table = path + (heading.map { "#" + $0 } ?? "")
            let cells = { (row: [String]?) in (row ?? []).filter { !$0.isEmpty }.joined(separator: " · ") }
            switch kind {
            case .recordAppend: return "新增记录 \(cells(after)) → \(table)"
            case .recordUpdate: return "修改记录 \(cells(before)) → \(cells(after))（\(table)）"
            case .recordRemove: return "删除记录 \(cells(before))（\(table)）"
            case .noteCreate: return "新建笔记 \(path)"
            case .noteWrite: return "改写笔记 \(path)"
            case .noteRename: return "改名 \(path) → \(newPath ?? "")"
            case .noteMove: return "移动 \(path) → \(newPath ?? "")"
            case .noteTrash: return "移到废纸篓 \(path)"
            case .pageWrite: return "重写空间主页 \(path)"
            }
        }
    }

    public static let fileName = "操作记录.json"
    public static let retention: TimeInterval = 30 * 86_400
    public let root: URL
    let now: () -> Date

    public init(root: URL, now: @escaping () -> Date = Date.init) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.now = now
    }

    var file: URL { root.appendingPathComponent(".留白").appendingPathComponent(Self.fileName) }

    /// Unexpired entries, newest first.
    public func entries() -> [Entry] { stored().reversed() }

    /// Unexpired entries in the order they were written.
    func stored() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let all = (try? decoder.decode([Entry].self, from: data)) ?? []
        let cutoff = now().addingTimeInterval(-Self.retention)
        return all.filter { $0.date >= cutoff }
    }

    func save(_ entries: [Entry]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }

    public func record(_ new: [Entry]) throws {
        guard !new.isEmpty else { return }
        try save(stored() + new)
    }

    // MARK: undo

    public func undo(_ id: UUID) throws {
        var all = stored()
        guard let index = all.firstIndex(where: { $0.id == id }) else { throw SpaceAPIError.notFound("操作记录") }
        let entry = all[index]
        guard !entry.undone else { throw SpaceAPIError.conflict("这条操作已经撤销过了。") }
        try revert(entry)
        all[index].undone = true
        try save(all)
    }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    func text(_ path: String) -> String? { try? String(contentsOf: url(path), encoding: .utf8) }
    func write(_ text: String, _ path: String) throws {
        try FileManager.default.createDirectory(at: url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url(path), options: .atomic)
    }
    static let changed = SpaceAPIError.conflict("目标在这次操作之后又被修改过，为避免覆盖，没有撤销。")

    private func revert(_ entry: Entry) throws {
        switch entry.kind {
        case .recordAppend, .recordUpdate, .recordRemove: try revertRecord(entry)
        case .noteCreate:
            guard text(entry.path) == entry.after?.first else { throw Self.changed }
            try FileManager.default.trashItem(at: url(entry.path), resultingItemURL: nil)
        case .noteWrite, .pageWrite:
            guard text(entry.path) == entry.after?.first else { throw Self.changed }
            if let before = entry.before?.first { try write(before, entry.path) }
            else { try FileManager.default.trashItem(at: url(entry.path), resultingItemURL: nil) }
        case .noteRename, .noteMove:
            guard let newPath = entry.newPath, FileManager.default.fileExists(atPath: url(newPath).path),
                  !FileManager.default.fileExists(atPath: url(entry.path).path) else { throw Self.changed }
            for change in entry.related ?? [] where text(change.path) != change.after { _ = change; throw Self.changed }
            try FileManager.default.moveItem(at: url(newPath), to: url(entry.path))
            for change in entry.related ?? [] {
                let target = change.path == newPath ? entry.path : change.path
                try write(change.before, target)
            }
        case .noteTrash:
            guard let trashed = entry.trashed, FileManager.default.fileExists(atPath: trashed),
                  !FileManager.default.fileExists(atPath: url(entry.path).path) else { throw Self.changed }
            try FileManager.default.createDirectory(at: url(entry.path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: URL(fileURLWithPath: trashed), to: url(entry.path))
        }
    }

    private func revertRecord(_ entry: Entry) throws {
        guard let text = text(entry.path), let table = RecordTable.find(in: text, heading: entry.heading) else { throw Self.changed }
        let width = table.header.count
        let rows = table.rows.map { RecordEdit.padded($0, width) }
        switch entry.kind {
        case .recordAppend:
            guard let after = entry.after, let i = rows.lastIndex(of: RecordEdit.padded(after, width)) else { throw Self.changed }
            try write(RecordEdit.rewrite(text, table: table, rows: [i]) { _, _ in nil }, entry.path)
        case .recordUpdate:
            guard let after = entry.after, let before = entry.before else { throw Self.changed }
            let target = RecordEdit.padded(after, width)
            let candidates = rows.indices.filter { rows[$0] == target }
            guard let i = candidates.min(by: { abs($0 - (entry.row ?? 0)) < abs($1 - (entry.row ?? 0)) }) else { throw Self.changed }
            try write(RecordEdit.rewrite(text, table: table, rows: [i]) { _, _ in RecordEdit.padded(before, width) }, entry.path)
        default:
            guard let before = entry.before else { throw Self.changed }
            try write(RecordEdit.insert(text, table: table, row: RecordEdit.padded(before, width), at: entry.row ?? rows.count), entry.path)
        }
    }
}
