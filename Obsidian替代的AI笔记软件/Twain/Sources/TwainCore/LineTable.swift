import Foundation

/// Where each line of a text starts (UTF-16 offsets), and each line's first four UTF-16 units
/// packed 16 bits apiece (0 past the line's end): enough to tell what a line can be without
/// asking the string again.
///
/// Built by one pass over the text; after an edit only the lines the edit touched are scanned
/// again and the ones after it are shifted, so typing costs a few lines, not the whole note.
public struct LineTable: Equatable, Sendable {
    public private(set) var starts: [Int] = [0]
    public private(set) var heads: [UInt64] = [0]
    /// The length of the text this table describes.
    public private(set) var length = 0

    public init() {}

    public init(_ ns: NSString) {
        scan(ns)
    }

    public var count: Int { starts.count }

    /// The line containing UTF-16 offset `loc`.
    public func line(at loc: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= loc { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Unit `k` (0–3) of line `i`, 0 past its end.
    @inline(__always) public func unit(_ i: Int, _ k: Int) -> unichar {
        unichar(truncatingIfNeeded: heads[i] >> UInt64(16 * k))
    }

    /// Reads the whole text.
    public mutating func scan(_ ns: NSString) {
        let (s, h) = Self.scan(ns, from: 0, to: ns.length)
        starts = s
        heads = h
        length = ns.length
    }

    /// After one edit: the characters now at `edited` (in the new text) replaced others, and
    /// the text's length changed by `delta`. Falls back to a whole scan when the table does
    /// not describe the text before the edit.
    public mutating func update(_ ns: NSString, edited: NSRange, delta: Int) {
        let len = ns.length
        guard length + delta == len, edited.location >= 0, NSMaxRange(edited) <= len, edited.location <= length else {
            return scan(ns)
        }
        // Lines before the edit are unchanged; so is everything after its end, shifted by delta.
        let a = line(at: edited.location)
        let oldEnd = NSMaxRange(edited) - delta
        guard oldEnd >= 0, oldEnd <= length else { return scan(ns) }
        let b = line(at: oldEnd)
        let from = starts[a]
        let to = b + 1 < starts.count ? starts[b + 1] + delta : len
        guard to >= from, to <= len else { return scan(ns) }
        let (s, h) = Self.scan(ns, from: from, to: to, trailingLine: b + 1 >= starts.count)
        var newStarts = Array(starts[..<a])
        newStarts.reserveCapacity(starts.count + s.count)
        newStarts += s
        newStarts += starts[(b + 1)...].map { $0 + delta }
        var newHeads = Array(heads[..<a])
        newHeads.reserveCapacity(heads.count + h.count)
        newHeads += h
        newHeads += heads[(b + 1)...]
        starts = newStarts
        heads = newHeads
        length = len
    }

    /// Lines starting in `from..<to`. `from` is a line start; `to` is a line start too, unless
    /// `trailingLine`, when it is the text's end and the last line has no newline after it.
    static func scan(_ ns: NSString, from: Int, to: Int, trailingLine: Bool = true) -> ([Int], [UInt64]) {
        var starts = [from]
        var heads: [UInt64] = []
        var head: UInt64 = 0, col = 0
        var buf = [unichar](repeating: 0, count: 8192)
        var pos = from
        buf.withUnsafeMutableBufferPointer { b in
            let p = b.baseAddress!
            while pos < to {
                let n = min(8192, to - pos)
                ns.getCharacters(p, range: NSRange(location: pos, length: n))
                var k = 0
                while k < n {
                    let c = p[k]
                    if c == 0x0A {
                        starts.append(pos + k + 1)
                        heads.append(head)
                        head = 0
                        col = 0
                    } else if col < 4 {
                        head |= UInt64(c) << UInt64(16 * col)
                        col += 1
                    }
                    k += 1
                }
                pos += n
            }
        }
        if trailingLine {
            heads.append(head)
        } else {
            // `to` starts the next (unchanged) line: it belongs to the lines after this range.
            starts.removeLast()
        }
        return (starts, heads)
    }
}
