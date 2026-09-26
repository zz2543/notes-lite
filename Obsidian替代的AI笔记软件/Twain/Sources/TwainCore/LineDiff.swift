import Foundation

public enum HunkState: String, Codable, Sendable {
    case pending, accepted, rejected
}

/// A contiguous change: replace `del` lines of the baseline starting at `start` with `add`.
public struct Hunk: Equatable, Codable, Sendable {
    public var start: Int
    public var del: Int
    public var add: [String]
    public var state: HunkState

    public init(start: Int, del: Int, add: [String], state: HunkState = .pending) {
        self.start = start
        self.del = del
        self.add = add
        self.state = state
    }
}

public enum DiffRow: Equatable, Sendable {
    case context(String)
    /// `changed`: character offsets that differ from the paired line, empty when the whole line is new.
    case deleted(String, changed: [Range<Int>] = [])
    case added(String, changed: [Range<Int>] = [])
    case bar(hunk: Int)
    /// `count` unchanged baseline lines from `line` on, folded away.
    case gap(line: Int, count: Int)
}

/// The review page in order: unchanged runs between changes, and one block per hunk.
public enum DiffBlock: Equatable, Sendable {
    case context([DiffRow])
    case hunk(index: Int, rows: [DiffRow])
}

public enum LineDiff {
    public static func hunks(from old: [String], to new: [String]) -> [Hunk] {
        let diff = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var result: [Hunk] = []
        var current: Hunk?
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) {
                if current == nil { current = Hunk(start: i, del: 0, add: []) }
                current!.del += 1
                i += 1
            } else if j < new.count, inserted.contains(j) {
                if current == nil { current = Hunk(start: i, del: 0, add: []) }
                current!.add.append(new[j])
                j += 1
            } else {
                if let c = current { result.append(c); current = nil }
                i += 1
                j += 1
            }
        }
        if let c = current { result.append(c) }
        return joiningParagraphs(result, base: old)
    }

    /// Edits separated only by blank lines are one change: a rewritten passage should come back
    /// as one card, not one per paragraph. The blank lines between them ride along unchanged.
    static func joiningParagraphs(_ hunks: [Hunk], base: [String]) -> [Hunk] {
        var out: [Hunk] = []
        for h in hunks {
            if var last = out.last {
                let gapStart = last.start + last.del
                let gap = base[min(gapStart, base.count)..<min(h.start, base.count)]
                if gap.allSatisfy(isBlank) {
                    last.add += gap + h.add
                    last.del = h.start + h.del - last.start
                    out[out.count - 1] = last
                    continue
                }
            }
            out.append(h)
        }
        return out
    }

    /// Applies accepted hunks to `base`. Pending hunks count as `pendingAs`.
    public static func apply(_ hunks: [Hunk], to base: [String], pendingAs: HunkState = .rejected) -> [String] {
        var out = base
        let accepted = hunks.enumerated().filter { h in
            h.element.state == .accepted || (h.element.state == .pending && pendingAs == .accepted)
        }
        for (_, h) in accepted.sorted(by: { $0.element.start != $1.element.start ? $0.element.start > $1.element.start : $0.offset > $1.offset }) {
            let lo = min(h.start, out.count)
            let hi = min(h.start + h.del, out.count)
            out.replaceSubrange(lo..<hi, with: h.add)
        }
        return out
    }

    /// Lines the hunk really adds and removes, leaving out the unchanged lines a joined hunk spans.
    public static func counts(_ h: Hunk, base: [String]) -> (plus: Int, minus: Int) {
        var plus = 0, minus = 0
        for change in h.add.difference(from: baseline(h, base)) {
            if case .insert = change { plus += 1 } else { minus += 1 }
        }
        return (plus, minus)
    }

    /// Rows for the review screen, in baseline order, with a decision bar after each hunk.
    public static func rows(base: [String], hunks: [Hunk], context: Int? = nil, expanded: Set<Int> = []) -> [DiffRow] {
        blocks(base: base, hunks: hunks, context: context, expanded: expanded).flatMap { block -> [DiffRow] in
            switch block {
            case let .context(rows): rows
            case let .hunk(index, rows): rows + [.bar(hunk: index)]
            }
        }
    }

    /// With `context`, unchanged runs keep that many lines next to each change and fold the rest
    /// into a `.gap`, unless the gap's first line is in `expanded`.
    public static func blocks(base: [String], hunks: [Hunk], context: Int? = nil, expanded: Set<Int> = []) -> [DiffBlock] {
        var out: [DiffBlock] = []
        var i = 0
        func unchanged(_ upTo: Int, before: Bool, after: Bool) {
            guard upTo > i else { return }
            out.append(.context(fold(base, i..<upTo, keepHead: before ? context : nil, keepTail: after ? context : nil,
                                     folding: context != nil, expanded: expanded)))
        }
        let order = hunks.indices.sorted { hunks[$0].start != hunks[$1].start ? hunks[$0].start < hunks[$1].start : $0 < $1 }
        for idx in order {
            let h = hunks[idx]
            unchanged(min(h.start, base.count), before: !out.isEmpty, after: true)
            out.append(.hunk(index: idx, rows: hunkRows(h, base: base)))
            i = max(i, min(h.start + h.del, base.count))
        }
        unchanged(base.count, before: !out.isEmpty, after: false)
        return out
    }

    private static func fold(_ base: [String], _ r: Range<Int>, keepHead: Int?, keepTail: Int?, folding: Bool,
                             expanded: Set<Int>) -> [DiffRow] {
        let all = { (s: Range<Int>) in base[s].map(DiffRow.context) }
        guard folding else { return all(r) }
        let lo = r.lowerBound + (keepHead ?? 0)
        let hi = r.upperBound - (keepTail ?? 0)
        // Folding one or two lines saves nothing and costs a click.
        guard hi - lo >= 3, !expanded.contains(lo) else { return all(r) }
        return all(r.lowerBound..<lo) + [.gap(line: lo, count: hi - lo)] + all(hi..<r.upperBound)
    }

    private static func baseline(_ h: Hunk, _ base: [String]) -> [String] {
        Array(base[min(h.start, base.count)..<min(h.start + h.del, base.count)])
    }

    private static func hunkRows(_ h: Hunk, base: [String]) -> [DiffRow] {
        let old = baseline(h, base)
        switch h.state {
        case .rejected:
            return old.map(DiffRow.context)
        case .accepted:
            return aligned(old, h.add).filter { if case .deleted = $0 { false } else { true } }
        case .pending:
            return aligned(old, h.add)
        }
    }

    /// Lines both sides share (the blank lines a joined hunk spans) stay context; the rest are
    /// paired by similarity so a reworded line shows next to its original with the words marked.
    static func aligned(_ old: [String], _ new: [String]) -> [DiffRow] {
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var rows: [DiffRow] = []
        var dels: [String] = [], adds: [String] = []
        func flush() {
            rows += paired(dels, adds)
            dels.removeAll()
            adds.removeAll()
        }
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) {
                dels.append(old[i]); i += 1
            } else if j < new.count, inserted.contains(j) {
                adds.append(new[j]); j += 1
            } else {
                flush()
                rows.append(.context(old[i]))
                i += 1; j += 1
            }
        }
        flush()
        return rows
    }

    /// Order-preserving pairing that maximises total similarity. Unpaired lines between two pairs
    /// are listed removals first, then additions.
    private static func paired(_ dels: [String], _ adds: [String]) -> [DiffRow] {
        let n = dels.count, m = adds.count
        guard n > 0, m > 0, n * m <= 40_000 else {
            return dels.map { DiffRow.deleted($0) } + adds.map { DiffRow.added($0) }
        }
        var sim = [[Double]](repeating: [Double](repeating: 0, count: m), count: n)
        for a in 0..<n { for b in 0..<m { sim[a][b] = similarity(dels[a], adds[b]) } }
        var best = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        for a in 1...n {
            for b in 1...m {
                var v = max(best[a - 1][b], best[a][b - 1])
                if sim[a - 1][b - 1] >= 0.5 { v = max(v, best[a - 1][b - 1] + sim[a - 1][b - 1]) }
                best[a][b] = v
            }
        }
        var pairs: [(Int, Int)] = []
        var a = n, b = m
        while a > 0, b > 0 {
            if sim[a - 1][b - 1] >= 0.5, best[a][b] == best[a - 1][b - 1] + sim[a - 1][b - 1] {
                pairs.append((a - 1, b - 1)); a -= 1; b -= 1
            } else if best[a][b] == best[a - 1][b] {
                a -= 1
            } else {
                b -= 1
            }
        }
        var rows: [DiffRow] = []
        var x = 0, y = 0
        for (pa, pb) in pairs.reversed() {
            rows += dels[x..<pa].map { DiffRow.deleted($0) }
            rows += adds[y..<pb].map { DiffRow.added($0) }
            let marks = inline(dels[pa], adds[pb])
            rows += [.deleted(dels[pa], changed: marks?.old ?? []), .added(adds[pb], changed: marks?.new ?? [])]
            x = pa + 1; y = pb + 1
        }
        rows += dels[x...].map { DiffRow.deleted($0) }
        rows += adds[y...].map { DiffRow.added($0) }
        return rows
    }

    /// Dice coefficient over the two lines' characters: cheap enough to run for every pair.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for c in a { counts[c, default: 0] += 1 }
        var common = 0
        for c in b where (counts[c] ?? 0) > 0 {
            counts[c]! -= 1
            common += 1
        }
        return 2 * Double(common) / Double(a.count + b.count)
    }

    /// Character ranges that differ between two versions of a line, compared word by word
    /// (each CJK character is its own word). Nil when too little survives for marks to help.
    public static func inline(_ a: String, _ b: String) -> (old: [Range<Int>], new: [Range<Int>])? {
        let ca = Array(a), cb = Array(b)
        let ta = tokens(ca), tb = tokens(cb)
        var removed: [Int] = [], inserted: [Int] = []
        for change in tb.map({ String(cb[$0]) }).difference(from: ta.map { String(ca[$0]) }) {
            switch change {
            case let .remove(offset, _, _): removed.append(offset)
            case let .insert(offset, _, _): inserted.append(offset)
            }
        }
        let old = spans(removed.sorted().map { ta[$0] }, in: ca)
        let new = spans(inserted.sorted().map { tb[$0] }, in: cb)
        let kept = ca.count - removed.reduce(0) { $0 + ta[$1].count }
        guard Double(kept) >= 0.4 * Double(max(ca.count, cb.count)) else { return nil }
        return (old, new)
    }

    private static func tokens(_ s: [Character]) -> [Range<Int>] {
        func isWord(_ c: Character) -> Bool {
            (c.isLetter || c.isNumber) && !(c.unicodeScalars.first?.properties.isIdeographic ?? false)
        }
        var out: [Range<Int>] = []
        var i = 0
        while i < s.count {
            var j = i + 1
            if isWord(s[i]) {
                while j < s.count, isWord(s[j]) { j += 1 }
            } else if s[i].isWhitespace {
                while j < s.count, s[j].isWhitespace { j += 1 }
            }
            out.append(i..<j)
            i = j
        }
        return out
    }

    /// Joins ranges separated by at most one visible character, so a reworded phrase is one mark
    /// rather than fragments around a character that happens to survive.
    private static func spans(_ ranges: [Range<Int>], in s: [Character]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for r in ranges {
            if let last = out.last, s[last.upperBound..<r.lowerBound].filter({ !$0.isWhitespace }).count <= 1 {
                out[out.count - 1] = last.lowerBound..<r.upperBound
            } else {
                out.append(r)
            }
        }
        return out
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }
}
