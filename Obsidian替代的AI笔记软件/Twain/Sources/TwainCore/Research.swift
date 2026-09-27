import Foundation

/// One finding on the research desk: short, typed, and traceable to the notes it came from.
/// The agent answers a question with many of these instead of one essay; the user picks,
/// questions and assembles them.
public struct ResearchCard: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case claim, evidence, conflict, open
        public var label: String {
            switch self {
            case .claim: "结论"
            case .evidence: "证据"
            case .conflict: "分歧"
            case .open: "待解"
            }
        }
    }
    public struct Source: Codable, Equatable, Sendable, Hashable {
        public var path: String
        public var line: Int?
        public init(path: String, line: Int?) { self.path = path; self.line = line }
    }
    public enum State: String, Codable, Sendable { case new, pinned, discarded, drafted }

    public var id: String
    public var kind: Kind
    public var title: String
    public var body: String
    public var sources: [Source]
    /// The card this one answers, for follow-up questions.
    public var parent: String?
    public var state: State

    public init(kind: Kind, title: String, body: String, sources: [Source], parent: String?) {
        id = String(UUID().uuidString.prefix(8)).lowercased()
        self.kind = kind
        self.title = title
        self.body = body
        self.sources = sources
        self.parent = parent
        state = .new
    }

    /// Reads cards as the agent sends them, keeping only sources that point into the vault.
    public static func parse(_ items: [JSONValue], index: VaultIndex?, parent: String?) throws -> [ResearchCard] {
        try items.map { item in
            guard let title = item["title"]?.string, !title.isEmpty else {
                throw RPCError(RPCError.invalidParams, "每张卡片都需要 title")
            }
            let kind = item["kind"]?.string.flatMap(Kind.init(rawValue:)) ?? .claim
            let sources: [Source] = (item["sources"]?.array ?? []).compactMap { s in
                let raw = s["path"]?.string ?? s.string ?? ""
                let path = index?.resolve(raw) ?? (raw.isEmpty ? nil : raw)
                return path.map { Source(path: $0, line: s["line"]?.int) }
            }
            return ResearchCard(kind: kind, title: title, body: item["body"]?.string ?? "", sources: sources,
                                parent: item["parent"]?.string ?? parent)
        }
    }

    /// How the card reads in a draft note.
    public var markdown: String {
        var out = "### \(title)\n"
        if !body.isEmpty { out += body + "\n" }
        if !sources.isEmpty {
            let links = sources.map { s -> String in
                let t = ((s.path as NSString).lastPathComponent as NSString).deletingPathExtension
                return "[[\(t)]]" + (s.line.map { " 第 \($0) 行" } ?? "")
            }
            out += "> 来源：" + links.joined(separator: "、") + "\n"
        }
        return out
    }
}

public extension TwainCommands {
    static let cards = CommandSpec(
        "cards", "把研究发现作为卡片放到用户的研究台上（问库）。每张卡片短而具体、带出处；分多次提交，边找边交。",
        effect: .propose, mcp: "cards",
        params: [ParamSpec("items", .json, required: true,
                           help: #"[{"kind": claim|evidence|conflict|open, "title": 不超过 20 字, "body": 不超过 120 字, "sources": [{"path": 笔记路径, "line": 行号}]}]"#,
                           schema: ["type": "array", "items": ["type": "object", "required": ["title", "kind", "sources"], "properties": [
                               "kind": ["type": "string", "enum": ["claim", "evidence", "conflict", "open"],
                                        "description": "claim 结论 · evidence 证据（引原文）· conflict 资料间的矛盾 · open 资料没回答的问题"],
                               "title": ["type": "string", "description": "一句话，不超过 20 字"],
                               "body": ["type": "string", "description": "不超过 120 字"],
                               "sources": ["type": "array", "items": ["type": "object", "required": ["path"], "properties": [
                                   "path": ["type": "string"], "line": ["type": "integer"],
                               ]]],
                               "parent": ["type": "string", "description": "回答用户对某张卡片的追问时，填那张卡片的 id"],
                           ]]])])
}
