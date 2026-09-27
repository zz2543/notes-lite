import Foundation

/// Data that isn't prose — sleep, workouts, habits, reading, spending — kept beside the notes
/// in `.twain/data/<collection>.jsonl`, one JSON object per line. Collections need no schema
/// and no code: anything that can send JSON (the `twain` command, the local HTTP API, a file
/// dropped into `.twain/inbox/<collection>/`) can add to one, and spaces chart them.
public final class DataStore {
    public let dir: URL

    public init(vault: URL) { dir = vault.appendingPathComponent(".twain/data") }

    public struct Info: Equatable, Sendable {
        public var name: String
        public var count: Int
        public var fields: [String]
        public var last: String?
    }

    public static func validName(_ name: String) throws -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.count <= 64, n.range(of: #"^[\p{L}\p{N}_\-]+$"#, options: .regularExpression) != nil else {
            throw RPCError(RPCError.invalidParams, "集合名只能用文字、数字、- 和 _：\(name)")
        }
        return n
    }

    func url(_ name: String) -> URL { dir.appendingPathComponent(name + ".jsonl") }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// A record's moment: its `time` (ISO 8601) or `date` (yyyy-MM-dd) field.
    public static func time(of r: JSONValue) -> Date? {
        if let t = r["time"]?.string {
            return iso.date(from: t) ?? day.date(from: String(t.prefix(10)))
        }
        return r["date"]?.string.flatMap { day.date(from: String($0.prefix(10))) }
    }

    /// Appends records (objects). Each gets a `time` when it has neither `time` nor `date`.
    @discardableResult
    public func add(_ name: String, records: [JSONValue], now: Date = Date()) throws -> Int {
        let n = try Self.validName(name)
        var out = Data()
        for r in records {
            guard var o = r.object else { throw RPCError(RPCError.invalidParams, "每条记录都应该是 JSON 对象") }
            if o["time"] == nil && o["date"] == nil { o["time"] = .string(Self.iso.string(from: now)) }
            out.append(JSONValue.object(o).encoded())
            out.append(0x0A)
        }
        guard !out.isEmpty else { return 0 }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = url(n)
        if !FileManager.default.fileExists(atPath: u.path) { FileManager.default.createFile(atPath: u.path, contents: nil) }
        let h = try FileHandle(forWritingTo: u)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: out)
        return records.count
    }

    public func all(_ name: String) -> [JSONValue] {
        guard let n = try? Self.validName(name), let d = try? Data(contentsOf: url(n)) else { return [] }
        var buf = d
        buf.append(0x0A)
        return RPC.drainLines(&buf).compactMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }

    /// Records between `since` and `until`, newest last, at most `limit` (the latest ones).
    public func query(_ name: String, since: Date? = nil, until: Date? = nil, limit: Int? = nil,
                      match: [String: String] = [:]) -> [JSONValue] {
        var rows = all(name).filter { r in
            let t = Self.time(of: r)
            if let since, let t, t < since { return false }
            if let until, let t, t > until { return false }
            for (k, v) in match where r[k].map({ $0.string ?? $0.text() }) != v { return false }
            return true
        }
        if let limit, rows.count > limit { rows = Array(rows.suffix(limit)) }
        return rows
    }

    public func collections() -> [Info] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.map { u in
            let name = u.deletingPathExtension().lastPathComponent
            let rows = all(name)
            var fields: [String] = []
            for r in rows.suffix(50) { for k in (r.object?.keys.sorted() ?? []) where !fields.contains(k) { fields.append(k) } }
            return Info(name: name, count: rows.count, fields: fields, last: rows.last.flatMap { Self.time(of: $0) }.map(Self.iso.string))
        }.sorted { $0.name < $1.name }
    }

    /// `7d`, `4w`, `3m`, `1y` before now, or a date.
    public static func parseSince(_ s: String?, now: Date = Date()) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let d = day.date(from: s) ?? iso.date(from: s) { return d }
        guard let unit = s.last, let n = Int(s.dropLast()) else { return nil }
        let days: Int
        switch unit {
        case "d": days = n
        case "w": days = n * 7
        case "m": days = n * 30
        case "y": days = n * 365
        default: return nil
        }
        return Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: now))
    }

    // MARK: import

    /// Records in a JSON array, a JSON object, JSON Lines, or CSV with a header row.
    public static func parse(_ text: String, ext: String) throws -> [JSONValue] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ext.lowercased() == "csv" { return csv(t) }
        if t.hasPrefix("["), let v = try? JSONDecoder().decode(JSONValue.self, from: Data(t.utf8)), let a = v.array { return a }
        if t.hasPrefix("{"), let v = try? JSONDecoder().decode(JSONValue.self, from: Data(t.utf8)), v.object != nil { return [v] }
        var buf = Data(t.utf8)
        buf.append(0x0A)
        let rows = RPC.drainLines(&buf).compactMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        guard !rows.isEmpty else { throw RPCError(RPCError.invalidParams, "读不出记录：需要 JSON、JSON Lines 或带表头的 CSV") }
        return rows
    }

    static func csv(_ text: String) -> [JSONValue] {
        var lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return [] }
        let header = splitCSV(lines.removeFirst())
        return lines.map { line in
            let cells = splitCSV(line)
            var o: [String: JSONValue] = [:]
            for (i, k) in header.enumerated() where i < cells.count && !k.isEmpty {
                let c = cells[i]
                o[k] = Double(c).map { $0 == $0.rounded() && abs($0) < 1e15 ? JSONValue(Int($0)) : .number($0) } ?? .string(c)
            }
            return .object(o)
        }
    }

    static func splitCSV(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        var it = Array(line)[...]
        while let c = it.first {
            it = it.dropFirst()
            if c == "\"" {
                if quoted, it.first == "\"" { cur.append("\""); it = it.dropFirst() } else { quoted.toggle() }
            } else if c == ",", !quoted {
                out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""
            } else {
                cur.append(c)
            }
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }

    /// Daily totals (or averages, or last values) of a numeric field over the last `days` days.
    public func daily(_ name: String, field: String, days: Int, reduce: String = "sum", now: Date = Date()) -> [(day: String, value: Double?)] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now))!
        var buckets: [String: [Double]] = [:]
        for r in query(name, since: start) {
            guard let t = Self.time(of: r) else { continue }
            let v = r[field]?.number ?? (r[field]?.bool == true ? 1 : nil) ?? (field == "count" ? 1 : nil)
            guard let v else { continue }
            buckets[Self.day.string(from: t), default: []].append(v)
        }
        return (0..<days).map { i in
            let d = Self.day.string(from: cal.date(byAdding: .day, value: i, to: start)!)
            guard let vs = buckets[d], !vs.isEmpty else { return (d, nil) }
            switch reduce {
            case "avg": return (d, vs.reduce(0, +) / Double(vs.count))
            case "last": return (d, vs.last)
            case "max": return (d, vs.max())
            default: return (d, vs.reduce(0, +))
            }
        }
    }
}

public extension TwainCommands {
    static let dataAdd = CommandSpec(
        "data.add", "往数据集合里追加记录（睡眠、运动、打卡……任何 JSON 对象都行，集合不存在时自动创建）。",
        effect: .write, needsApp: false,
        params: [ParamSpec("collection", required: true, positional: true, help: "集合名，例如 sleep"),
                 ParamSpec("record", .json, required: true, help: #"一条记录 {"hours": 7.5} 或多条 [{…}, {…}]；没有 time/date 字段时记为现在"#)])
    static let dataQuery = CommandSpec(
        "data.query", "读数据集合里的记录。", effect: .read, needsApp: false,
        params: [ParamSpec("collection", required: true, positional: true, help: "集合名"),
                 ParamSpec("since", help: "从何时起：7d、4w、3m、1y 或日期 2026-09-01"),
                 ParamSpec("limit", .int, help: "最多返回最近的几条，默认 200"),
                 ParamSpec("field", help: "给出时按天汇总这个数值字段"),
                 ParamSpec("reduce", help: "按天汇总的方式：sum（默认）、avg、max、last")])
    static let dataImport = CommandSpec(
        "data.import", "把一个 JSON、JSON Lines 或 CSV 文件导入数据集合。", effect: .write, needsApp: false,
        params: [ParamSpec("collection", required: true, positional: true, help: "集合名"),
                 ParamSpec("file", required: true, help: "文件路径")])
    static let dataCollections = CommandSpec(
        "data", "列出库里的数据集合：记录数、字段、最近一条的时间。", effect: .read, needsApp: false)

    static let dataCommands = [dataCollections, dataAdd, dataQuery, dataImport]
}

public enum DataQueries {
    public static let ids: Set<String> = ["data", "data.add", "data.query", "data.import"]

    public static func run(_ id: String, _ p: [String: JSONValue], root: URL) throws -> JSONValue {
        let store = DataStore(vault: root)
        switch id {
        case "data":
            return ["collections": .array(store.collections().map { c in
                ["name": .string(c.name), "count": JSONValue(c.count), "fields": JSONValue(c.fields), "last": JSONValue(c.last)]
            })]
        case "data.add":
            let name = p["collection"]?.string ?? ""
            let rec = p["record"] ?? .null
            let n = try store.add(name, records: rec.array ?? [rec])
            return ["collection": .string(name), "added": JSONValue(n)]
        case "data.import":
            let name = p["collection"]?.string ?? ""
            let path = (p["file"]?.string ?? "") as NSString
            guard let text = try? String(contentsOfFile: path.expandingTildeInPath, encoding: .utf8) else {
                throw RPCError(RPCError.notFound, "读不到文件：\(path)")
            }
            let rows = try DataStore.parse(text, ext: path.pathExtension)
            let n = try store.add(name, records: rows)
            return ["collection": .string(name), "added": JSONValue(n)]
        case "data.query":
            let name = try DataStore.validName(p["collection"]?.string ?? "")
            if let field = p["field"]?.string {
                let since = DataStore.parseSince(p["since"]?.string ?? "30d") ?? Date()
                let days = max(1, (Calendar.current.dateComponents([.day], from: since, to: Date()).day ?? 30) + 1)
                let series = store.daily(name, field: field, days: min(days, 3660), reduce: p["reduce"]?.string ?? "sum")
                return ["collection": .string(name), "field": .string(field), "days": .array(series.map { d in
                    ["date": .string(d.day), "value": d.value.map { JSONValue.number($0) } ?? .null]
                })]
            }
            let rows = store.query(name, since: DataStore.parseSince(p["since"]?.string), limit: p["limit"]?.int ?? 200)
            return ["collection": .string(name), "records": .array(rows)]
        default:
            throw RPCError(RPCError.methodNotFound, "没有命令 \(id)")
        }
    }
}
