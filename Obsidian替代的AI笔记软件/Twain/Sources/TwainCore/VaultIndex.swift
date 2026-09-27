import Foundation

/// What Twain reads out of one note. Line numbers start at 1, like editors and `grep -n`.
public struct NoteOutline: Equatable, Sendable {
    public struct Heading: Equatable, Sendable {
        public var level: Int
        public var text: String
        public var line: Int
    }

    public struct Task: Equatable, Sendable {
        public var done: Bool
        public var text: String
        public var line: Int
        /// The nearest heading above the task, if any.
        public var heading: String?
    }

    public struct Link: Equatable, Sendable {
        /// The note part of `[[target#section|alias]]`.
        public var target: String
        public var line: Int
    }

    public var headings: [Heading] = []
    public var tasks: [Task] = []
    public var links: [Link] = []
    public var tags: [String] = []

    static let inlineCode = try! NSRegularExpression(pattern: #"`[^`]*`"#)
    static let tag = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&#/\-])#([\p{L}\p{N}_/\-]+)"#)

    public static func parse(_ text: String) -> NoteOutline {
        parse(lines: Markdown.lines(text))
    }

    public static func parse(lines: [String]) -> NoteOutline {
        var o = NoteOutline()
        var current: String?
        var tagSet = Set<String>()
        let types = Markdown.types(lines)
        for (i, line) in lines.enumerated() {
            let type = types[i]
            if type.isLiteral { continue }
            let ns = line as NSString
            let body = ns.substring(from: Markdown.prefixLength(line))
            switch type {
            case _ where type.isHeading:
                let level = type.headingLevel!
                let text = body.trimmingCharacters(in: .whitespaces)
                o.headings.append(Heading(level: level, text: text, line: i + 1))
                current = text
            case .task:
                o.tasks.append(Task(done: Markdown.isTaskDone(line), text: body.trimmingCharacters(in: .whitespaces),
                                    line: i + 1, heading: current))
            default: break
            }
            for span in Markdown.parseLine(line, type: type).spans {
                if case let .wikilink(raw) = span.kind {
                    let target = linkTarget(raw)
                    if !target.isEmpty { o.links.append(Link(target: target, line: i + 1)) }
                }
            }
            let plain = inlineCode.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: (body as NSString).length), withTemplate: "")
            let pns = plain as NSString
            for m in tag.matches(in: plain, range: NSRange(location: 0, length: pns.length)) {
                let t = pns.substring(with: m.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: "/-"))
                if !t.isEmpty, !t.allSatisfy(\.isNumber), tagSet.insert(t).inserted { o.tags.append(t) }
            }
        }
        return o
    }

    /// `笔记#小节|别名` → `笔记`.
    public static func linkTarget(_ raw: String) -> String {
        var s = Substring(raw)
        if let bar = s.firstIndex(of: "|") { s = s[..<bar] }
        if let hash = s.firstIndex(of: "#") { s = s[..<hash] }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Headings enclosing `line` (1-based), outermost first.
    public func headingPath(at line: Int) -> [String] {
        var stack: [Heading] = []
        for h in headings where h.line <= line {
            while let last = stack.last, last.level >= h.level { stack.removeLast() }
            stack.append(h)
        }
        return stack.map(\.text)
    }
}

/// An in-memory index over a vault folder, rebuilt from the files on demand. It keeps no
/// state on disk: `refresh()` re-reads only the notes whose modification date changed.
public final class VaultIndex {
    public struct Note {
        public let rel: String
        public var title: String { ((rel as NSString).lastPathComponent as NSString).deletingPathExtension }
        public var folder: String { (rel as NSString).deletingLastPathComponent }
        public var lines: [String]
        public var outline: NoteOutline
        var stamp: Date?
    }

    public struct Hit: Equatable, Sendable {
        public var rel: String
        /// nil when the note's title matched rather than a line.
        public var line: Int?
        public var text: String
    }

    public let root: URL
    public private(set) var notes: [String: Note] = [:]
    /// Lowercased title → paths, for resolving `[[links]]`.
    private var byTitle: [String: [String]] = [:]

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Sorted paths of every note, in the same order the sidebar shows them.
    public private(set) var paths: [String] = []

    public func refresh() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        var seen = Set<String>()
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let u as URL in e {
                let values = try? u.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    if u.lastPathComponent == "node_modules" { e.skipDescendants() }
                    continue
                }
                guard u.pathExtension.lowercased() == "md" else { continue }
                let path = u.standardizedFileURL.resolvingSymlinksInPath().path
                let rel = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : u.lastPathComponent
                seen.insert(rel)
                let stamp = values?.contentModificationDate
                if let old = notes[rel], old.stamp == stamp, stamp != nil { continue }
                let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
                store(rel, text, stamp: stamp)
            }
        }
        for rel in notes.keys where !seen.contains(rel) { notes[rel] = nil }
        rebuildTitles()
    }

    /// Uses `text` for `rel` instead of what is on disk, e.g. the editor's unsaved buffer.
    public func update(_ rel: String, text: String) {
        store(rel, text, stamp: nil)
        rebuildTitles()
    }

    private func store(_ rel: String, _ text: String, stamp: Date?) {
        let lines = Markdown.lines(text)
        notes[rel] = Note(rel: rel, lines: lines, outline: NoteOutline.parse(lines: lines), stamp: stamp)
    }

    private func rebuildTitles() {
        paths = notes.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var t: [String: [String]] = [:]
        for rel in paths {
            t[notes[rel]!.title.lowercased(), default: []].append(rel)
        }
        byTitle = t
    }

    // MARK: queries

    /// Finds a note by path (with or without `.md`) or by title. Shallower paths win title ties.
    public func resolve(_ ref: String) -> String? {
        let r = ref.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !r.isEmpty else { return nil }
        if notes[r] != nil { return r }
        if notes[r + ".md"] != nil { return r + ".md" }
        let stem = r.lowercased().hasSuffix(".md") ? String(r.dropLast(3)) : r
        if stem.contains("/") {
            return paths.first { ($0 as NSString).deletingPathExtension.lowercased() == stem.lowercased() }
        }
        let candidates = byTitle[stem.lowercased()] ?? []
        let exact = candidates.filter { notes[$0]?.title == stem }
        return (exact.isEmpty ? candidates : exact).min { depth($0) < depth($1) || (depth($0) == depth($1) && $0 < $1) }
    }

    private func depth(_ rel: String) -> Int { rel.split(separator: "/").count }

    public func list(folder: String? = nil) -> [String] {
        guard let f = folder?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")), !f.isEmpty else { return paths }
        return paths.filter { $0.hasPrefix(f + "/") }
    }

    /// Lines in other notes that `[[link]]` to `rel`.
    public func backlinks(to rel: String) -> [Hit] {
        var out: [Hit] = []
        for p in paths where p != rel {
            guard let n = notes[p] else { continue }
            var lastLine = 0
            for l in n.outline.links where l.line != lastLine && resolve(l.target) == rel {
                lastLine = l.line
                out.append(Hit(rel: p, line: l.line, text: Self.snippet(n.lines[l.line - 1], around: nil)))
            }
        }
        return out
    }

    /// Every whitespace-separated term must appear in the title or in one line. Titles rank first,
    /// then headings, then body lines.
    public func search(_ query: String, limit: Int = 20) -> [Hit] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        var scored: [(Int, Hit)] = []
        for p in paths {
            guard let n = notes[p] else { continue }
            let title = n.title.lowercased()
            if terms.allSatisfy(title.contains) { scored.append((3, Hit(rel: p, line: nil, text: n.title))) }
            let headingLines = Set(n.outline.headings.map(\.line))
            for (i, line) in n.lines.enumerated() {
                let low = line.lowercased()
                guard terms.allSatisfy(low.contains) else { continue }
                scored.append((headingLines.contains(i + 1) ? 2 : 1,
                               Hit(rel: p, line: i + 1, text: Self.snippet(line, around: terms[0]))))
            }
        }
        // Stable: equal scores keep path and line order.
        let sorted = scored.enumerated().sorted { a, b in
            a.element.0 != b.element.0 ? a.element.0 > b.element.0 : a.offset < b.offset
        }
        return sorted.prefix(max(0, limit)).map(\.element.1)
    }

    public struct TaskHit: Equatable, Sendable {
        public var rel: String
        public var task: NoteOutline.Task
    }

    public func tasks(folder: String? = nil, tag: String? = nil, includeDone: Bool = false) -> [TaskHit] {
        let tag = tag?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased()
        return list(folder: folder).flatMap { p -> [TaskHit] in
            guard let n = notes[p] else { return [] }
            if let tag, !tag.isEmpty, !n.outline.tags.contains(where: { $0.lowercased() == tag }) { return [] }
            return n.outline.tasks.filter { includeDone || !$0.done }.map { TaskHit(rel: p, task: $0) }
        }
    }

    /// One line trimmed for display, cut around `term` when it is long.
    static func snippet(_ line: String, around term: String?, width: Int = 120) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count > width else { return t }
        var start = t.startIndex
        if let term, let r = t.range(of: term, options: .caseInsensitive) {
            start = t.index(r.lowerBound, offsetBy: -min(40, t.distance(from: t.startIndex, to: r.lowerBound)))
        }
        let end = t.index(start, offsetBy: width, limitedBy: t.endIndex) ?? t.endIndex
        return (start > t.startIndex ? "…" : "") + t[start..<end] + (end < t.endIndex ? "…" : "")
    }
}
