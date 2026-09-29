import XCTest
@testable import TwainCore

final class LineTableTests: XCTestCase {
    func testScan() {
        let t = LineTable("# 标题\n\n- 列表\n最后" as NSString)
        XCTAssertEqual(t.starts, [0, 5, 6, 11])
        XCTAssertEqual(t.count, t.heads.count)
        XCTAssertEqual(t.unit(0, 0), 0x23)
        XCTAssertEqual(t.unit(1, 0), 0)
        XCTAssertEqual(t.unit(2, 1), 0x20)
        XCTAssertEqual(t.line(at: 7), 2)
    }

    /// Random single edits, each checked against a scan of the whole new text.
    func testUpdateMatchesAFullScan() {
        var rng = SystemRandomNumberGenerator()
        let pieces = ["a", "字", "\n", "\n\n", "- ", "|x|", "```\n", "abc\ndef", "", "😀"]
        var text = "开头\n- 一\n- 二\n\n## 标题\n正文正文\n末尾" as NSString
        var t = LineTable(text)
        for _ in 0..<2000 {
            let len = text.length
            let loc = Int.random(in: 0...len, using: &rng)
            // Keep deletions on UTF-16 boundaries that don't split a surrogate pair.
            var del = Int.random(in: 0...min(6, len - loc), using: &rng)
            while del > 0, loc + del < len, CFStringIsSurrogateLowCharacter(text.character(at: loc + del)) { del -= 1 }
            if loc > 0, loc < len, CFStringIsSurrogateLowCharacter(text.character(at: loc)) { continue }
            let ins = pieces.randomElement(using: &rng)!
            let next = text.replacingCharacters(in: NSRange(location: loc, length: del), with: ins) as NSString
            let insLen = (ins as NSString).length
            t.update(next, edited: NSRange(location: loc, length: insLen), delta: insLen - del)
            text = next
            let full = LineTable(text)
            XCTAssertEqual(t, full, "after replacing \(del) at \(loc) with \(ins.debugDescription)")
            if t != full { return }
        }
    }

    func testUpdateFallsBackWhenOutOfStep() {
        var t = LineTable("a\nb" as NSString)
        let other = "x\ny\nz" as NSString
        t.update(other, edited: NSRange(location: 0, length: 1), delta: 0)
        XCTAssertEqual(t, LineTable(other))
    }
}
