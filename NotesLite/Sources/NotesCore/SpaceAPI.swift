import Foundation

/// `{今天}` `{年}` `{月}` `{周}` in record table paths and written values.
public enum Placeholders {
    public static func expand(_ text: String, now: Date) -> String {
        guard text.contains("{") else { return text }
        let calendar = Calendar(identifier: .gregorian)
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        var iso = Calendar(identifier: .iso8601); iso.timeZone = calendar.timeZone
        let w = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let pad = { (n: Int?) in String(format: "%02d", n ?? 0) }
        return text
            .replacingOccurrences(of: "{今天}", with: "\(c.year ?? 0)-\(pad(c.month))-\(pad(c.day))")
            .replacingOccurrences(of: "{年}", with: "\(c.year ?? 0)")
            .replacingOccurrences(of: "{月}", with: "\(c.year ?? 0)-\(pad(c.month))")
            .replacingOccurrences(of: "{周}", with: "\(w.yearForWeekOfYear ?? 0)-W\(pad(w.weekOfYear))")
    }
}

/// A refusal or failure reported back to the page as `{code, message}`.
public struct SpaceAPIError: Error, Equatable {
    public var code: String
    public var message: String
    static func outside(_ path: String) -> Self { .init(code: "outside-scope", message: "「\(path)」不在这个空间的范围内，或者是不允许访问的路径。") }
    static func invalid(_ message: String) -> Self { .init(code: "invalid", message: message) }
    static func notFound(_ path: String) -> Self { .init(code: "not-found", message: "找不到「\(path)」。") }
    static func exists(_ path: String) -> Self { .init(code: "exists", message: "「\(path)」已经存在。") }
    static func unknownField(_ field: String) -> Self { .init(code: "unknown-field", message: "记录表里没有字段「\(field)」。") }
    static let scopeChange = Self(code: "scope-change", message: "空间主页不能修改自己的范围（lb-scope）。请在留白里编辑空间。")
    static func conflict(_ message: String) -> Self { .init(code: "conflict", message: message) }
}

/// The native side of the `lb` interface: everything a space homepage can do to the library goes through `handle`.
/// Requests are `{"method": …, "args": […]}`; replies are `{"ok": true, "result": …}` or `{"ok": false, "error": {code, message}}`.
public final class SpaceAPI {
    public let root: URL
    public let spaceName: String
    let log: OperationLog?
    let now: () -> Date
    /// Records and notes changed by the last request, for the 「主页刚修改了 N 条记录」 notice.
    public private(set) var lastChanges = 0

    public init(root: URL, space: String, log: OperationLog? = nil, now: @escaping () -> Date = Date.init) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.spaceName = space
        self.log = log
        self.now = now
    }

    var library: SpaceLibrary { SpaceLibrary(root: root) }

    /// The scope is read from the space file on every request, so it always matches what the user set.
    func scope() throws -> SpaceScope {
        guard let space = try? library.space(named: spaceName) else { throw SpaceAPIError.notFound(spaceName) }
        return space.scope
    }

    public func handle(_ request: Data) -> Data {
        lastChanges = 0
        let reply: [String: Any]
        do {
            guard let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
                  let method = object["method"] as? String else { throw SpaceAPIError.invalid("请求格式不正确。") }
            let result = try dispatch(method, Arguments(object["args"] as? [Any] ?? []))
            reply = ["ok": true, "result": result]
        } catch let error as SpaceAPIError {
            reply = ["ok": false, "error": ["code": error.code, "message": error.message]]
        } catch {
            reply = ["ok": false, "error": ["code": "failed", "message": error.localizedDescription]]
        }
        return (try? JSONSerialization.data(withJSONObject: reply, options: [.fragmentsAllowed])) ?? Data(#"{"ok":false,"error":{"code":"failed","message":"无法编码结果。"}}"#.utf8)
    }

    struct Arguments {
        let values: [Any]
        init(_ values: [Any]) { self.values = values }
        subscript(_ i: Int) -> Any? { i < values.count && !(values[i] is NSNull) ? values[i] : nil }
        func string(_ i: Int, _ name: String) throws -> String {
            guard let s = self[i] as? String, !s.isEmpty else { throw SpaceAPIError.invalid("缺少参数 \(name)。") }
            return s
        }
        func object(_ i: Int) -> [String: Any] { self[i] as? [String: Any] ?? [:] }
    }

    func dispatch(_ method: String, _ args: Arguments) throws -> Any {
        switch method {
        case "scope": return try scopeResult()
        case "notes": return try notes(in: args[0] as? String)
        case "read": return try read(args.string(0, "path"))
        case "tables": return try tables(args[0] as? String)
        case "query": return try query(args.string(0, "source"), args.object(1))
        case "page": return try library.space(named: spaceName).html
        default:
            if let result = try writeDispatch(method, args) { return result }
            throw SpaceAPIError.invalid("没有方法 lb.\(method)。")
        }
    }

    func writeDispatch(_ method: String, _ args: Arguments) throws -> Any? {
        switch method {
        case "append": return try append(args.string(0, "target"), args[1], args.object(2))
        case "update": return try update(args.string(0, "target"), args.object(1), args.object(2))
        case "remove": return try update(args.string(0, "target"), args.object(1), nil)
        default: return try noteDispatch(method, args)
        }
    }

    /// Filled in by the note half of the interface.
    func noteDispatch(_ method: String, _ args: Arguments) throws -> Any? { nil }

    func entry(_ kind: OperationLog.Kind, _ path: String) -> OperationLog.Entry {
        OperationLog.Entry(date: now(), space: spaceName, kind: kind, path: path)
    }

    func commit(_ text: String, to url: URL, entries: [OperationLog.Entry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        try log?.record(entries)
        lastChanges += entries.count
    }

    /// String values may use placeholders; every value is stored as its cell text.
    func cellValues(_ record: [String: Any]) -> [String: String] {
        record.reduce(into: [:]) { result, pair in
            guard pair.key != "_row" else { return }
            let text = Self.text(of: pair.value)
            result[pair.key] = pair.value is String ? Placeholders.expand(text, now: now()) : text
        }
    }

    func append(_ target: String, _ value: Any?, _ options: [String: Any]) throws -> [String: Any] {
        let source = try source(target)
        let records: [[String: Any]]
        if let one = value as? [String: Any] { records = [one] }
        else if let many = value as? [[String: Any]] { records = many }
        else { throw SpaceAPIError.invalid("lb.append 需要一条记录（对象）或记录数组。") }
        guard !records.isEmpty else { return ["count": 0] }
        let values = records.map(cellValues)
        var header = (options["header"] as? [Any])?.map { Self.text(of: $0) }.filter { !$0.isEmpty } ?? []
        if header.isEmpty { for record in records { for key in record.keys.sorted() where key != "_row" && !header.contains(key) { header.append(key) } } }
        let title = ((source.path as NSString).lastPathComponent as NSString).deletingPathExtension
        let result = try RecordEdit.append(try text(at: source.url), title: title, heading: source.heading, header: header, records: values)
        let entries = result.rows.map { row -> OperationLog.Entry in
            var e = entry(.recordAppend, source.path); e.heading = source.heading; e.header = result.header; e.after = row; return e
        }
        try commit(result.text, to: source.url, entries: entries)
        return ["count": entries.count]
    }

    /// `changes == nil` removes the matching records.
    func update(_ target: String, _ match: [String: Any], _ changes: [String: Any]?) throws -> [String: Any] {
        let source = try source(target)
        guard !match.isEmpty else { throw SpaceAPIError.invalid("需要用 match 指定要修改的记录，例如 { 日期: \"2026-10-18\" } 或 { _row: 0 }。") }
        guard let text = try text(at: source.url), let table = RecordTable.find(in: text, heading: source.heading) else { throw SpaceAPIError.notFound(target) }
        let width = table.header.count
        let types = table.types
        let updates = changes.map(cellValues)
        if let updates, let unknown = updates.keys.sorted().first(where: { !table.header.contains($0) }) { throw SpaceAPIError.unknownField(unknown) }
        if let unknown = match.keys.sorted().first(where: { $0 != "_row" && !table.header.contains($0) }) { throw SpaceAPIError.unknownField(unknown) }
        let indices = table.rows.indices.filter { i in
            if let row = match["_row"] as? Int, row != i { return false }
            return match.allSatisfy { key, wanted in
                guard key != "_row", let c = table.header.firstIndex(of: key) else { return true }
                return Self.matches(Self.value(c < table.rows[i].count ? table.rows[i][c] : "", type: types[c]), wanted)
            }
        }
        guard !indices.isEmpty else { return ["count": 0] }
        var entries: [OperationLog.Entry] = []
        let updated = RecordEdit.rewrite(text, table: table, rows: indices) { index, before in
            var e = entry(updates == nil ? .recordRemove : .recordUpdate, source.path)
            e.heading = source.heading; e.header = table.header; e.before = before; e.row = index
            guard let updates else { entries.append(e); return nil }
            var after = before
            for (key, value) in updates { if let c = table.header.firstIndex(of: key), c < width { after[c] = RecordEdit.normalized(value) } }
            e.after = after; entries.append(e)
            return after
        }
        try commit(updated, to: source.url, entries: entries.reversed().filter { $0.before != $0.after })
        return ["count": indices.count]
    }

    // MARK: paths

    /// A library-relative path inside the scope, with `..`, hidden segments, `.留白` and symlink escapes refused.
    func resolve(_ raw: String, requireNote: Bool = true) throws -> (path: String, url: URL) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.contains("\\"),
              !parts.contains(where: { $0.isEmpty || $0.hasPrefix(".") }) else { throw SpaceAPIError.outside(raw) }
        let path = parts.joined(separator: "/")
        guard try scope().contains(path) else { throw SpaceAPIError.outside(raw) }
        if requireNote, !path.lowercased().hasSuffix(".md") { throw SpaceAPIError.invalid("「\(raw)」不是笔记（.md）。") }
        let url = root.appendingPathComponent(path)
        // Resolve symlinks through the deepest existing ancestor; the real location must stay in scope too.
        var existing = url, tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path.count > root.path.count {
            tail.insert(existing.lastPathComponent, at: 0); existing.deleteLastPathComponent()
        }
        var real = existing.resolvingSymlinksInPath().standardizedFileURL
        for part in tail { real.appendPathComponent(part) }
        let prefixes = [root.path + "/", "/private" + root.path + "/"]
        guard let prefix = prefixes.first(where: { real.path.hasPrefix($0) }) else { throw SpaceAPIError.outside(raw) }
        let realRelative = String(real.path.dropFirst(prefix.count))
        guard !realRelative.split(separator: "/").contains(where: { $0.hasPrefix(".") }), try scope().contains(realRelative) else { throw SpaceAPIError.outside(raw) }
        return (path, url)
    }

    func resolveFolder(_ raw: String?) throws -> String? {
        guard let raw = raw?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")), !raw.isEmpty else { return nil }
        let resolved = try resolve(raw, requireNote: false)
        return resolved.path
    }

    /// `路径#标题` with placeholders expanded; `.md` is implied.
    func source(_ raw: String) throws -> (path: String, url: URL, heading: String?) {
        let expanded = Placeholders.expand(raw, now: now())
        let pieces = expanded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        var path = pieces[0].trimmingCharacters(in: .whitespaces)
        if !path.lowercased().hasSuffix(".md") { path += ".md" }
        let heading = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : nil
        let resolved = try resolve(path)
        return (resolved.path, resolved.url, heading?.isEmpty == true ? nil : heading)
    }

    func text(at url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else { throw SpaceAPIError.invalid("笔记不是 UTF-8 文本。") }
        return text
    }

    // MARK: reads

    func scopeResult() throws -> [String: Any] {
        switch try scope() {
        case .library: ["library": true]
        case .folders(let folders): ["library": false, "folders": folders]
        }
    }

    func scopedNotes() throws -> [Note] {
        let scope = try scope()
        return try LibraryScan.run(root: root, previous: [:]).notes.filter { scope.contains($0.path) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func notes(in folder: String?) throws -> [[String: Any]] {
        let folder = try resolveFolder(folder)
        let formatter = ISO8601DateFormatter()
        return try scopedNotes().filter { note in folder.map { note.path.hasPrefix($0 + "/") } ?? true }
            .map { ["path": $0.path, "title": $0.title, "modified": formatter.string(from: $0.modified)] }
    }

    func read(_ raw: String) throws -> String {
        let resolved = try resolve(raw)
        guard let text = try text(at: resolved.url) else { throw SpaceAPIError.notFound(raw) }
        return text
    }

    func tables(_ raw: String?) throws -> [[String: Any]] {
        let only = try raw.map { try resolve($0).path }
        return library.recordTables(in: try scope()).filter { table in
            only.map { table.source == $0 || table.source.hasPrefix($0 + "#") } ?? true
        }.map { ["source": $0.source, "header": $0.header] }
    }

    func query(_ raw: String, _ options: [String: Any]) throws -> [String: Any] {
        let source = try source(raw)
        guard let text = try text(at: source.url), let table = RecordTable.find(in: text, heading: source.heading) else {
            return ["records": [], "fields": []]
        }
        let types = table.types
        var records: [[String: Any]] = table.rows.enumerated().map { index, row in
            var record: [String: Any] = ["_row": index]
            for (c, name) in table.header.enumerated() where !name.isEmpty {
                record[name] = Self.value(c < row.count ? row[c] : "", type: types[c])
            }
            return record
        }
        if let filter = options["filter"] as? [String: Any] {
            records = records.filter { record in filter.allSatisfy { Self.matches(record[$0.key], $0.value) } }
        }
        if let sort = options["sort"] as? String, !sort.isEmpty {
            let descending = sort.hasPrefix("-")
            let field = descending ? String(sort.dropFirst()) : sort
            records = records.enumerated().sorted { a, b in
                let order = Self.compare(a.element[field], b.element[field])
                return order == .orderedSame ? a.offset < b.offset : (descending ? order == .orderedDescending : order == .orderedAscending)
            }.map(\.element)
        }
        if let limit = options["limit"] as? Int, limit >= 0 { records = Array(records.prefix(limit)) }
        return ["records": records, "fields": zip(table.header, types).map { ["name": $0, "type": $1.rawValue] }]
    }

    static func value(_ cell: String, type: RecordTable.FieldType) -> Any {
        let t = cell.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return NSNull() }
        if type == .number, let n = RecordTable.number(t) { return n }
        return t
    }

    static func text(of value: Any?) -> String {
        switch value {
        case nil, is NSNull: ""
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): n.boolValue ? "true" : "false"
        case let n as NSNumber:
            n.doubleValue.rounded() == n.doubleValue && abs(n.doubleValue) < 1e15 ? String(Int64(n.doubleValue)) : "\(n.doubleValue)"
        case let s as String: s
        default: "\(value!)"
        }
    }

    static func matches(_ cell: Any?, _ wanted: Any) -> Bool {
        if let n = cell as? Double, let w = wanted as? NSNumber { return n == w.doubleValue }
        return text(of: cell) == text(of: wanted)
    }

    static func compare(_ a: Any?, _ b: Any?) -> ComparisonResult {
        switch (a, b) {
        case let (x as Double, y as Double): x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
        case (nil, nil), (is NSNull, is NSNull): .orderedSame
        case (nil, _), (is NSNull, _): .orderedAscending
        case (_, nil), (_, is NSNull): .orderedDescending
        default: text(of: a).localizedStandardCompare(text(of: b))
        }
    }
}
