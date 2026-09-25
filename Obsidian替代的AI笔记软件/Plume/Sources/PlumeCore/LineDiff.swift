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
    case deleted(String)
    case added(String)
    case bar(hunk: Int)
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
        return result
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

    /// Rows for the review screen, in baseline order, with a decision bar after each hunk.
    public static func rows(base: [String], hunks: [Hunk]) -> [DiffRow] {
        var rows: [DiffRow] = []
        var i = 0
        let byStart = Dictionary(grouping: hunks.indices, by: { hunks[$0].start })
        while i <= base.count {
            var consumed = 0
            for idx in byStart[i] ?? [] {
                let h = hunks[idx]
                if h.state != .accepted {
                    for t in base[min(i, base.count)..<min(i + h.del, base.count)] {
                        rows.append(h.state == .rejected ? .context(t) : .deleted(t))
                    }
                }
                if h.state != .rejected {
                    rows.append(contentsOf: h.add.map(DiffRow.added))
                }
                rows.append(.bar(hunk: idx))
                consumed = max(consumed, h.del)
            }
            if consumed > 0 {
                i += consumed
                continue
            }
            if i < base.count { rows.append(.context(base[i])) }
            i += 1
        }
        return rows
    }
}
