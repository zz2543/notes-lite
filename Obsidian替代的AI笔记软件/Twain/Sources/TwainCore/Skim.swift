import Foundation

/// Reading a vault the way skills are read: first a card per note (name, tags, headings, one
/// line of what it is about), then the outline, then the text — each level only when the one
/// above says it's worth it. Cards cost no tokens: the summary line comes from the note's front
/// matter or first paragraph unless an AI or the user wrote a better one (`SummaryStore`).
public struct NoteCard: Equatable, Sendable {
    public var path: String
    public var title: String
    public var tags: [String]
    public var headings: [String]
    public var summary: String
    /// frontmatter · user · ai · auto
    public var source: String
    public var words: Int
    public var hash: String

    public var json: JSONValue {
        ["path": .string(path), "title": .string(title), "tags": JSONValue(tags), "headings": JSONValue(headings),
         "summary": .string(summary), "summarySource": .string(source), "words": JSONValue(words)]
    }
}

/// Summaries written by an AI or edited by the user, kept in `.twain/summaries.json` (committed
/// with the vault: they are the user's words, or paid for). Each remembers the hash of the note
/// it describes, so a changed note is summarized again and an unchanged one never is.
public final class SummaryStore {
    public struct Entry: Codable, Equatable, Sendable {
        public var hash: String
        public var text: String
        public var source: String
        public var updated: Date
    }

    public let url: URL
    public private(set) var entries: [String: Entry] = [:]

    public init(vault: URL) {
        url = vault.appendingPathComponent(".twain/summaries.json")
        reload()
    }

    public func reload() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        entries = (try? Data(contentsOf: url)).flatMap { try? dec.decode([String: Entry].self, from: $0) } ?? [:]
    }

    public func set(_ path: String, text: String, source: String, hash: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[path] = t.isEmpty ? nil : Entry(hash: hash, text: t, source: source, updated: Date())
        save()
    }

    public func rename(_ from: String, to: String) {
        guard let e = entries.removeValue(forKey: from) else { return }
        entries[to] = e
        save()
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? enc.encode(entries) { try? d.write(to: url, options: .atomic) }
    }
}

public enum Skim {
    /// FNV-1a over the text: cheap, stable across launches.
    public static func hash(_ lines: [String]) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for line in lines {
            for b in line.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            h = (h ^ 0x0A) &* 0x100000001b3
        }
        return String(h, radix: 16)
    }

    /// `key: value` pairs of YAML front matter (flat keys only, lists as `a, b`).
    public static func frontmatter(_ lines: [String]) -> [String: String] {
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else { return [:] }
        var out: [String: String] = [:]
        var lastKey: String?
        for line in lines[1..<end] {
            if line.hasPrefix("  - ") || line.hasPrefix("- "), let k = lastKey {
                let item = line.drop { $0 == " " || $0 == "-" }.trimmingCharacters(in: .whitespaces)
                out[k] = (out[k].map { $0.isEmpty ? "" : $0 + ", " } ?? "") + item
                continue
            }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("["), v.hasSuffix("]") { v = String(v.dropFirst().dropLast()) }
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            out[k] = v
            lastKey = k
        }
        return out
    }

    /// First real paragraph, trimmed to about `limit` characters: a free summary.
    public static func autoSummary(_ lines: [String], limit: Int = 90) -> String {
        // Block types only run forward, so each line is typed as it is reached and the walk
        // stops once the summary is long enough, instead of typing the whole note first.
        var ctx = BlockContext.none
        var parts: [String] = []
        var chars = 0
        for (i, line) in lines.enumerated() {
            let (forced, next) = Markdown.role(of: line, index: i, context: ctx)
            ctx = next
            let t = forced ?? Markdown.blockType(line)
            if t.isLiteral || t.isHeading || t == .hr || t == .table {
                if t.isHeading, chars >= 30 { break }
                continue
            }
            let m = Markdown.parseLine(line, type: t)
            var text = (line as NSString).substring(from: m.prefix.length)
            for mk in m.spans.flatMap(\.marks).sorted(by: { $0.location > $1.location }) where NSMaxRange(mk) <= (line as NSString).length {
                let r = NSRange(location: mk.location - m.prefix.length, length: mk.length)
                if r.location >= 0, NSMaxRange(r) <= (text as NSString).length { text = (text as NSString).replacingCharacters(in: r, with: "") }
            }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { if chars >= 30 { break }; continue }
            parts.append(text)
            chars += text.count
            if chars >= limit { break }
        }
        let s = parts.joined(separator: " ")
        return s.count > limit ? String(s.prefix(limit)) + "…" : s
    }

    public static func card(_ note: VaultIndex.Note, store: SummaryStore?) -> NoteCard {
        let lines = note.lines
        let h = hash(lines)
        let fm = frontmatter(lines)
        var tags = note.outline.tags
        for t in (fm["tags"] ?? fm["tag"] ?? "").split(whereSeparator: { $0 == "," || $0 == " " }) {
            let s = t.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            if !s.isEmpty, !tags.contains(s) { tags.append(s) }
        }
        var summary = "", source = "auto"
        if let s = fm["summary"] ?? fm["description"], !s.isEmpty {
            (summary, source) = (s, "frontmatter")
        } else if let e = store?.entries[note.rel], e.source == "user" || e.hash == h {
            (summary, source) = (e.text, e.source)
        } else {
            summary = autoSummary(lines)
        }
        let heads = note.outline.headings.filter { $0.level <= 2 && $0.text != note.title }.prefix(8)
            .map { $0.text.count > 40 ? String($0.text.prefix(40)) + "…" : $0.text }
        return NoteCard(path: note.rel, title: note.title, tags: tags, headings: Array(heads), summary: summary, source: source,
                        words: Markdown.countWords(lines), hash: h)
    }

    /// Whether an AI summary would add anything: the note is long enough and has none that is current.
    public static func wantsSummary(_ note: VaultIndex.Note, store: SummaryStore) -> Bool {
        let chars = note.lines.reduce(0) { $0 + $1.count }
        guard chars >= 300 else { return false }
        if let s = frontmatter(note.lines)["summary"], !s.isEmpty { return false }
        guard let e = store.entries[note.rel] else { return true }
        return e.source != "user" && e.hash != hash(note.lines)
    }

    /// Lines of the section under `heading` (heading line included), 0-based range.
    public static func section(_ note: VaultIndex.Note, heading: String) -> Range<Int>? {
        let want = heading.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased()
        let hs = note.outline.headings
        guard let i = hs.firstIndex(where: { $0.text.lowercased() == want }) ?? hs.firstIndex(where: { $0.text.lowercased().contains(want) }) else { return nil }
        let h = hs[i]
        let end = hs[(i + 1)...].first { $0.level <= h.level }?.line ?? note.lines.count + 1
        return (h.line - 1)..<(end - 1)
    }

    /// `read` at a level: 1 the card, 2 the outline with each section's opening, 3 the text
    /// (of one section when `section` is given), with 1-based line numbers.
    public static func read(_ rel: String, level: Int, section name: String?, index: VaultIndex, store: SummaryStore?) throws -> JSONValue {
        guard let note = index.notes[rel] else { throw RPCError(RPCError.notFound, "找不到笔记：\(rel)") }
        var out: [String: JSONValue] = ["note": .string(rel), "level": JSONValue(level)]
        switch level {
        case ...1:
            out["card"] = card(note, store: store).json
        case 2:
            let hs = note.outline.headings
            let types = Markdown.types(note.lines)
            out["card"] = card(note, store: store).json
            out["outline"] = .array(hs.enumerated().map { i, h in
                let end = hs[(i + 1)...].first?.line ?? note.lines.count + 1
                let body = (h.line..<(end - 1)).filter { !types[$0].isLiteral && !note.lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
                let opening = body.first.map { VaultIndex.snippet(note.lines[$0], around: nil, width: 60) } ?? ""
                return ["level": JSONValue(h.level), "text": .string(h.text), "line": JSONValue(h.line),
                        "lines": JSONValue(end - h.line), "opening": .string(opening)]
            })
            out["tasks"] = JSONValue(note.outline.tasks.filter { !$0.done }.count)
            out["links"] = JSONValue(Array(Set(note.outline.links.map(\.target))).sorted())
        default:
            var range = 0..<note.lines.count
            if let name, !name.isEmpty {
                guard let r = section(note, heading: name) else { throw RPCError(RPCError.notFound, "\(rel) 里没有标题：\(name)") }
                range = r
                out["section"] = .string(name)
            }
            out["from"] = JSONValue(range.lowerBound + 1)
            out["lines"] = JSONValue(Array(note.lines[range]))
        }
        return .object(out)
    }
}
