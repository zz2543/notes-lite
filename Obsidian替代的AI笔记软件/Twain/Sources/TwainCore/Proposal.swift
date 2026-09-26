import Foundation

/// An agent's suggested change to one note. Nothing touches the file until the user accepts
/// hunks in review; the record stays in `.twain/proposals/` afterwards, with what was accepted
/// and why the rest was not, so later runs can learn from it.
public struct Proposal: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        /// Every hunk accepted.
        case accepted
        /// Some hunks accepted, some rejected.
        case partial
        case rejected
        /// The note changed after the proposal was made, so it could not be applied as reviewed.
        case stale
    }

    public var id: String
    public var path: String
    public var createdAt: Date
    public var agent: String?
    public var session: String?
    /// The automation that produced it, if any.
    public var automation: String?
    public var reason: String?
    public var baseline: [String]
    public var proposed: [String]
    public var hunks: [Hunk]
    /// Why each hunk (same index) is there, as the agent explained it.
    public var notes: [String?]
    /// Why the user rejected each hunk (same index), when they said.
    public var feedback: [String?]
    public var status: Status
    public var resolvedAt: Date?
    /// True when the note did not exist before.
    public var isNew: Bool

    public init(id: String = Proposal.newID(), path: String, createdAt: Date = Date(), agent: String? = nil,
                session: String? = nil, automation: String? = nil, reason: String? = nil, baseline: [String], proposed: [String],
                notes: [String?]? = nil, isNew: Bool = false) {
        self.id = id
        self.path = path
        self.createdAt = createdAt
        self.agent = agent
        self.session = session
        self.automation = automation
        self.reason = reason
        self.baseline = baseline
        self.proposed = proposed
        self.hunks = LineDiff.hunks(from: baseline, to: proposed)
        self.notes = notes ?? Array(repeating: nil, count: hunks.count)
        self.feedback = Array(repeating: nil, count: hunks.count)
        self.status = .pending
        self.isNew = isNew
    }

    /// Sortable by time, unique enough for one vault: `20260926-191530-a1b2`.
    public static func newID(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date) + "-" + String(UUID().uuidString.prefix(4)).lowercased()
    }

    /// Marks the proposal resolved from the hunk decisions the user made.
    public mutating func resolve(_ decided: [Hunk], feedback: [String?], at date: Date = Date()) {
        hunks = decided
        self.feedback = (0..<decided.count).map { $0 < feedback.count ? feedback[$0] : nil }
        let accepted = decided.filter { $0.state == .accepted }.count
        status = accepted == decided.count ? .accepted : accepted == 0 ? .rejected : .partial
        resolvedAt = date
    }

    /// What the agent learns about the outcome.
    public var resultJSON: JSONValue {
        .object([
            "id": .string(id),
            "path": .string(path),
            "status": .string(status.rawValue),
            "hunks": .array(hunks.enumerated().map { i, h in
                var o: [String: JSONValue] = [
                    "index": JSONValue(i + 1),
                    "state": .string(h.state.rawValue),
                    "lines": JSONValue(Proposal.lineRange(h)),
                    "new": .string(h.add.joined(separator: "\n")),
                ]
                if i < feedback.count, let f = feedback[i], !f.isEmpty { o["feedback"] = .string(f) }
                return .object(o)
            }),
        ])
    }

    /// "12" or "12–14": the baseline lines a hunk replaces, 1-based.
    public static func lineRange(_ h: Hunk) -> String {
        h.del <= 1 ? "\(h.start + 1)" : "\(h.start + 1)–\(h.start + h.del)"
    }

    /// A message to send back to the agent after a review with rejections; nil when all was accepted.
    public func feedbackMessage() -> String? {
        let rejected = hunks.indices.filter { hunks[$0].state == .rejected }
        guard !rejected.isEmpty else { return nil }
        let accepted = hunks.count - rejected.count
        var lines = ["我审阅了你对 \(path) 的修改：接受 \(accepted) 处，拒绝 \(rejected.count) 处。", "", "被拒绝的修改："]
        for (n, i) in rejected.enumerated() {
            let h = hunks[i]
            let old = baseline[min(h.start, baseline.count)..<min(h.start + h.del, baseline.count)].joined(separator: " / ")
            var item = "\(n + 1). 第 \(Proposal.lineRange(h)) 行"
            if !old.isEmpty { item += "，原文：“\(Proposal.clip(old))”" }
            if !h.add.isEmpty { item += "，你改成：“\(Proposal.clip(h.add.joined(separator: " / ")))”" }
            if i < feedback.count, let f = feedback[i], !f.isEmpty { item += "。原因：\(f)" } else { item += "。（没有写原因）" }
            lines.append(item)
        }
        lines += ["", (accepted == 0 ? "文件保持原样，没有写入任何改动。" : "被接受的 \(accepted) 处已经写入文件。")
                  + "请根据这些意见重新考虑被拒绝的部分；需要修改时用 propose_edit（或 twain propose）提交，并说明理由。"]
        return lines.joined(separator: "\n")
    }

    static func clip(_ s: String, _ n: Int = 60) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }
}

public enum ProposalBuilder {
    public struct Edit: Equatable, Sendable {
        public var old: String
        public var new: String
        public var reason: String?
        public init(old: String, new: String, reason: String? = nil) {
            self.old = old
            self.new = new
            self.reason = reason
        }
    }

    /// Reads `edits` as sent by agents: `[{"old", "new", "reason"?}]`.
    public static func edits(_ v: JSONValue) throws -> [Edit] {
        guard let arr = v.array, !arr.isEmpty else { throw RPCError(RPCError.invalidParams, "edits 应为非空数组") }
        return try arr.enumerated().map { i, e in
            guard let old = e["old"]?.string, let new = e["new"]?.string else {
                throw RPCError(RPCError.invalidParams, "edits 第 \(i + 1) 项需要 old 和 new 两个字符串")
            }
            return Edit(old: old, new: new, reason: e["reason"]?.string)
        }
    }

    /// Applies non-overlapping replacements, each found exactly once in `text`. Returns the new
    /// text and, per edit with a reason, the baseline lines (0-based, inclusive) it touches.
    public static func apply(_ edits: [Edit], to text: String) throws -> (text: String, anchors: [(ClosedRange<Int>, String)]) {
        let ns = text as NSString
        var placed: [(NSRange, Edit)] = []
        for (i, e) in edits.enumerated() {
            guard !e.old.isEmpty else { throw RPCError(RPCError.invalidParams, "edits 第 \(i + 1) 项的 old 为空") }
            let first = ns.range(of: e.old)
            guard first.location != NSNotFound else {
                throw RPCError(RPCError.notFound, "edits 第 \(i + 1) 项的原文在笔记中找不到：“\(Proposal.clip(e.old, 40))”")
            }
            // Searching from one past the start also catches overlapping repeats ("aa" in "aaa").
            let rest = NSRange(location: first.location + 1, length: ns.length - first.location - 1)
            if ns.range(of: e.old, range: rest).location != NSNotFound {
                throw RPCError(RPCError.invalidParams, "edits 第 \(i + 1) 项的原文在笔记中出现了不止一次，请多带一些上下文：“\(Proposal.clip(e.old, 40))”")
            }
            if placed.contains(where: { NSIntersectionRange($0.0, first).length > 0 }) {
                throw RPCError(RPCError.invalidParams, "edits 第 \(i + 1) 项和前面的替换重叠")
            }
            placed.append((first, e))
        }
        func line(_ loc: Int) -> Int { (ns.substring(to: loc) as NSString).components(separatedBy: "\n").count - 1 }
        let anchors = placed.compactMap { r, e -> (ClosedRange<Int>, String)? in
            guard let reason = e.reason, !reason.isEmpty else { return nil }
            return (line(r.location)...line(max(r.location, NSMaxRange(r) - 1)), reason)
        }
        let out = NSMutableString(string: text)
        for (r, e) in placed.sorted(by: { $0.0.location > $1.0.location }) {
            out.replaceCharacters(in: r, with: e.new)
        }
        return (out as String, anchors)
    }

    /// Attaches reasons to hunks. `anchors` name baseline lines (from edits); `lineNotes` name
    /// 1-based lines of the new text (from `notes`). A reason that lands on no hunk goes to the nearest.
    public static func notes(hunks: [Hunk], anchors: [(ClosedRange<Int>, String)], lineNotes: [(Int, String)]) -> [String?] {
        guard !hunks.isEmpty else { return [] }
        var out = [[String]](repeating: [], count: hunks.count)
        // Where each hunk sits in the new text.
        var shift = 0
        var newStart = [Int](repeating: 0, count: hunks.count)
        for i in hunks.indices.sorted(by: { hunks[$0].start < hunks[$1].start }) {
            newStart[i] = hunks[i].start + shift
            shift += hunks[i].add.count - hunks[i].del
        }
        func nearest(_ distance: (Int) -> Int) -> Int {
            hunks.indices.min { distance($0) < distance($1) }!
        }
        for (range, text) in anchors {
            let hit = hunks.indices.first { i in
                let h = hunks[i]
                let lo = h.start, hi = h.start + max(h.del, 1) - 1
                return lo <= range.upperBound && range.lowerBound <= hi
            } ?? nearest { abs(hunks[$0].start - range.lowerBound) }
            out[hit].append(text)
        }
        for (line, text) in lineNotes {
            let l = line - 1
            let hit = hunks.indices.first { i in
                l >= newStart[i] && l < newStart[i] + max(hunks[i].add.count, 1)
            } ?? nearest { abs(newStart[$0] - l) }
            out[hit].append(text)
        }
        return out.map { $0.isEmpty ? nil : $0.joined(separator: "\n") }
    }
}

/// `.twain/proposals/<id>.json`, one file per proposal.
public struct ProposalStore {
    public let dir: URL

    public init(vault: URL) {
        dir = vault.appendingPathComponent(".twain/proposals")
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func save(_ p: Proposal) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(p) else { return }
        try? data.write(to: dir.appendingPathComponent(p.id + ".json"), options: .atomic)
    }

    public func load(_ id: String) -> Proposal? {
        (try? Data(contentsOf: dir.appendingPathComponent(id + ".json"))).flatMap { try? Self.decoder.decode(Proposal.self, from: $0) }
    }

    /// Oldest first.
    public func all() -> [Proposal] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? Self.decoder.decode(Proposal.self, from: $0) } }
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id < $1.id }
    }

    /// Resolved proposals, newest first, for `twain reviews`.
    public func recentReviews(limit: Int) -> JSONValue {
        let done = all().filter { $0.status != .pending }.reversed().prefix(max(0, limit))
        return .object(["reviews": .array(done.map { p in
            var o = p.resultJSON.object ?? [:]
            o["agent"] = JSONValue(p.agent)
            o["reason"] = JSONValue(p.reason)
            o["hunks"] = .array(p.hunks.enumerated().map { i, h in
                var hj: [String: JSONValue] = [
                    "state": .string(h.state.rawValue),
                    "lines": .string(Proposal.lineRange(h)),
                    "old": .string(p.baseline[min(h.start, p.baseline.count)..<min(h.start + h.del, p.baseline.count)].joined(separator: "\n")),
                    "new": .string(h.add.joined(separator: "\n")),
                ]
                if i < p.notes.count, let n = p.notes[i] { hj["why"] = .string(n) }
                if i < p.feedback.count, let f = p.feedback[i], !f.isEmpty { hj["feedback"] = .string(f) }
                return .object(hj)
            })
            return .object(o)
        })])
    }
}
