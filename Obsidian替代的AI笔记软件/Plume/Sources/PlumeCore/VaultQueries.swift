import Foundation

/// The read commands that need only the files. The app and the CLI (when the app is closed)
/// both answer them here, so the two give the same JSON.
public enum VaultQueries {
    public static let ids: Set<String> = ["notes", "search", "backlinks", "outline", "tasks", "reviews"]

    /// `current` is the note open in the app; the CLI has none, so `note` is required there.
    public static func run(_ id: String, _ params: [String: JSONValue], index: VaultIndex, current: String?) throws -> JSONValue {
        switch id {
        case "notes":
            let rels = index.list(folder: params["folder"]?.string)
            return .object(["notes": .array(rels.map { rel in
                let n = index.notes[rel]!
                return .object(["path": .string(rel), "title": .string(n.title), "tasks": JSONValue(n.outline.tasks.filter { !$0.done }.count)])
            })])
        case "search":
            let q = params["query"]?.string ?? ""
            let hits = index.search(q, limit: params["limit"]?.int ?? 20)
            return .object(["query": .string(q), "results": .array(hits.map(json))])
        case "backlinks":
            let rel = try note(params, index: index, current: current)
            return .object(["note": .string(rel), "backlinks": .array(index.backlinks(to: rel).map(json))])
        case "outline":
            let rel = try note(params, index: index, current: current)
            guard let o = index.notes[rel]?.outline else { throw RPCError(RPCError.notFound, "找不到笔记：\(rel)") }
            return .object([
                "note": .string(rel),
                "headings": .array(o.headings.map { .object(["level": JSONValue($0.level), "text": .string($0.text), "line": JSONValue($0.line)]) }),
                "tasks": .array(o.tasks.map(json)),
                "links": .array(o.links.map { l in
                    .object(["target": .string(l.target), "line": JSONValue(l.line), "path": JSONValue(index.resolve(l.target))])
                }),
                "tags": JSONValue(o.tags),
            ])
        case "tasks":
            let hits = index.tasks(folder: params["folder"]?.string, tag: params["tag"]?.string,
                                   includeDone: params["done"]?.bool ?? false)
            return .object(["tasks": .array(hits.map { h in
                var o = json(h.task).object!
                o["path"] = .string(h.rel)
                return .object(o)
            })])
        case "reviews":
            return ProposalStore(vault: index.root).recentReviews(limit: params["limit"]?.int ?? 20)
        default:
            throw RPCError(RPCError.methodNotFound, "没有命令 \(id)")
        }
    }

    /// Resolves the `note` param, falling back to the note open in the app.
    public static func note(_ params: [String: JSONValue], index: VaultIndex, current: String?) throws -> String {
        guard let ref = params["note"]?.string, !ref.isEmpty else {
            guard let current else { throw RPCError(RPCError.invalidParams, "需要指定笔记（Plume 未运行时没有“当前笔记”）") }
            return current
        }
        guard let rel = index.resolve(ref) else { throw RPCError(RPCError.notFound, "找不到笔记：\(ref)") }
        return rel
    }

    static func json(_ h: VaultIndex.Hit) -> JSONValue {
        .object(["path": .string(h.rel), "line": h.line.map { JSONValue($0) } ?? .null, "text": .string(h.text)])
    }

    static func json(_ t: NoteOutline.Task) -> JSONValue {
        .object(["done": .bool(t.done), "text": .string(t.text), "line": JSONValue(t.line), "heading": JSONValue(t.heading)])
    }
}

/// Finds the vault a working directory belongs to: the nearest folder with `.plume/`,
/// else one with both AGENTS.md and CLAUDE.md (what Plume writes into every vault).
public func findVaultRoot(from dir: URL) -> URL? {
    let fm = FileManager.default
    var d = dir.standardizedFileURL.resolvingSymlinksInPath()
    var fallback: URL?
    while true {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: d.appendingPathComponent(".plume").path, isDirectory: &isDir), isDir.boolValue { return d }
        if fallback == nil, fm.fileExists(atPath: d.appendingPathComponent("AGENTS.md").path),
           fm.fileExists(atPath: d.appendingPathComponent("CLAUDE.md").path) {
            fallback = d
        }
        let up = d.deletingLastPathComponent()
        if up.path == d.path { return fallback }
        d = up
    }
}
