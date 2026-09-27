import Foundation

/// A margin note an agent leaves on a passage: a question, a suggestion with replacement text,
/// a fact to check, a remark on structure. Anchored by the quoted text rather than by offsets,
/// so it finds its passage again after the note is edited.
public struct Annotation: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case question, suggestion, fact, structure, praise
        public var label: String {
            switch self {
            case .question: "问题"
            case .suggestion: "建议"
            case .fact: "核实"
            case .structure: "结构"
            case .praise: "亮点"
            }
        }
    }
    public enum Status: String, Codable, Sendable { case open, accepted, dismissed }
    public struct Reply: Codable, Equatable, Sendable {
        public var from: String   // "user" or an agent name
        public var text: String
        public var at: Date
        public init(from: String, text: String, at: Date = Date()) { self.from = from; self.text = text; self.at = at }
    }

    public var id: String
    public var kind: Kind
    /// Exact text of the passage in the note.
    public var quote: String
    /// Where the passage was (1-based), to choose among repeated quotes.
    public var line: Int?
    public var text: String
    /// For suggestions: what to put in place of `quote`.
    public var replacement: String?
    public var agent: String?
    public var session: String?
    public var created: Date
    public var status: Status
    public var replies: [Reply]

    public init(kind: Kind, quote: String, line: Int?, text: String, replacement: String?, agent: String?, session: String?) {
        id = String(UUID().uuidString.prefix(8)).lowercased()
        self.kind = kind
        self.quote = quote
        self.line = line
        self.text = text
        self.replacement = replacement
        self.agent = agent
        self.session = session
        created = Date()
        status = .open
        replies = []
    }

    public var json: JSONValue {
        var o: [String: JSONValue] = ["id": .string(id), "kind": .string(kind.rawValue), "quote": .string(quote),
                                      "text": .string(text), "status": .string(status.rawValue)]
        if let line { o["line"] = JSONValue(line) }
        if let replacement { o["replacement"] = .string(replacement) }
        if !replies.isEmpty { o["replies"] = .array(replies.map { ["from": .string($0.from), "text": .string($0.text)] }) }
        return .object(o)
    }
}

/// Where a quote sits in a note now. Exact matches first (the one nearest the remembered line),
/// then one ignoring differences in whitespace.
public enum Anchor {
    public static func locate(_ quote: String, in text: String, line: Int?) -> NSRange? {
        let q = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let ns = text as NSString
        var hits: [NSRange] = []
        var from = 0
        while from < ns.length {
            let r = ns.range(of: q, options: [], range: NSRange(location: from, length: ns.length - from))
            guard r.location != NSNotFound else { break }
            hits.append(r)
            from = NSMaxRange(r)
        }
        if hits.isEmpty {
            // Whitespace may have been reflowed: match on the characters alone.
            let pattern = q.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
            if let re = try? NSRegularExpression(pattern: pattern) {
                hits = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
            }
        }
        guard !hits.isEmpty else { return nil }
        guard let line, hits.count > 1 else { return hits.first }
        func lineOf(_ loc: Int) -> Int { ns.substring(to: loc).reduce(1) { $1 == "\n" ? $0 + 1 : $0 } }
        return hits.min { abs(lineOf($0.location) - line) < abs(lineOf($1.location) - line) }
    }
}

/// `.twain/annotations/<note path>.json`, one list per note.
public final class AnnotationStore {
    public let root: URL

    public init(vault: URL) { root = vault.appendingPathComponent(".twain/annotations") }

    func url(_ rel: String) -> URL { root.appendingPathComponent(rel + ".json") }

    public func load(_ rel: String) -> [Annotation] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url(rel))).flatMap { try? dec.decode([Annotation].self, from: $0) } ?? []
    }

    public func save(_ rel: String, _ items: [Annotation]) {
        let u = url(rel)
        if items.isEmpty { try? FileManager.default.removeItem(at: u); return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? enc.encode(items) { try? d.write(to: u, options: .atomic) }
    }

    public func rename(_ from: String, to: String) {
        let items = load(from)
        guard !items.isEmpty else { return }
        save(to, items)
        try? FileManager.default.removeItem(at: url(from))
    }

    /// Adds agent annotations to `rel`, anchoring each against `text`. Returns what was added and
    /// the quotes that could not be found (so the agent can correct them).
    public func add(_ rel: String, text: String, items: [JSONValue], agent: String?, session: String?) throws
        -> (added: [Annotation], missing: [String]) {
        var list = load(rel)
        var added: [Annotation] = []
        var missing: [String] = []
        for item in items {
            guard let quote = item["quote"]?.string, let body = item["text"]?.string, !body.isEmpty else {
                throw RPCError(RPCError.invalidParams, "每条批注都需要 quote（原文片段）和 text（批注内容）")
            }
            let kind = item["kind"]?.string.flatMap(Annotation.Kind.init(rawValue:)) ?? (item["replacement"]?.string != nil ? .suggestion : .question)
            guard let r = Anchor.locate(quote, in: text, line: item["line"]?.int) else { missing.append(quote); continue }
            let line = (text as NSString).substring(to: r.location).filter { $0 == "\n" }.count + 1
            let a = Annotation(kind: kind, quote: (text as NSString).substring(with: r), line: line, text: body,
                               replacement: item["replacement"]?.string, agent: agent, session: session)
            list.append(a)
            added.append(a)
        }
        save(rel, list)
        return (added, missing)
    }
}

public extension TwainCommands {
    static let annotate = CommandSpec(
        "annotate", "在笔记的具体位置留下批注，显示在正文旁边，不改动笔记。用于审阅：指出问题、提建议（可附替换文字）、"
            + "提醒核实事实、评论结构。也可以回复用户在某条批注下的追问。", effect: .propose, mcp: "annotate",
        params: [noteParam(true),
                 ParamSpec("items", .json, help: #"新批注：[{"quote": 原文片段（须逐字出现在笔记中）, "text": 批注, "kind": question|suggestion|fact|structure|praise, "replacement": 建议替换成的文字（可选）}]"#,
                           schema: ["type": "array", "items": ["type": "object", "required": ["quote", "text"], "properties": [
                               "quote": ["type": "string", "description": "被批注的原文，逐字复制，尽量短（一句或半句）"],
                               "text": ["type": "string", "description": "批注内容，一两句话"],
                               "kind": ["type": "string", "enum": ["question", "suggestion", "fact", "structure", "praise"]],
                               "replacement": ["type": "string", "description": "kind 为 suggestion 时，建议替换 quote 的文字"],
                               "line": ["type": "integer", "description": "原文所在行号（可选，用于区分重复出现的原文）"],
                           ]]]),
                 ParamSpec("reply_to", help: "回复这条批注（批注 id），与 text 一起用"),
                 ParamSpec("text", help: "回复内容"),
                 ParamSpec("replacement", help: "回复时一并更新建议的替换文字")])
    static let annotations = CommandSpec(
        "annotations", "一篇笔记上的批注：内容、状态（open/accepted/dismissed）和用户的回复。", effect: .read,
        params: [noteParam(false), ParamSpec("all", .bool, help: "也列出已处理的")])
}
