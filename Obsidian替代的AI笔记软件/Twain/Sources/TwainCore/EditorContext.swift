import Foundation

/// Where the user is inside the note they are editing, in the terms `twain context` reports.
public enum EditorContext {
    /// Selected text beyond this many characters is cut, and `truncated` says so.
    public static let selectionLimit = 20_000

    /// `lines`, `cursor`, `headingPath` and `selection` for `text` with `selection` (UTF-16, as
    /// NSTextView reports it). Out-of-range selections are clamped rather than trusted.
    public static func describe(text: String, selection: NSRange) -> [String: JSONValue] {
        let ns = text as NSString
        let loc = min(max(0, selection.location), ns.length)
        let sel = NSRange(location: loc, length: min(max(0, selection.length), ns.length - loc))
        let caret = position(loc, in: ns)
        var out: [String: JSONValue] = [
            "lines": JSONValue(Markdown.lines(text).count),
            "cursor": json(caret),
            "headingPath": JSONValue(NoteOutline.parse(text).headingPath(at: caret.line)),
            "selection": .null,
        ]
        if sel.length > 0 {
            let selected = ns.substring(with: sel)
            out["selection"] = [
                "text": .string(String(selected.prefix(selectionLimit))),
                "truncated": .bool(selected.count > selectionLimit),
                "start": json(caret),
                "end": json(position(NSMaxRange(sel), in: ns)),
            ]
        }
        return out
    }

    /// 1-based line and column (in UTF-16 units) of a text offset.
    public static func position(_ loc: Int, in ns: NSString) -> (line: Int, column: Int) {
        let before = ns.substring(to: loc) as NSString
        let nl = before.range(of: "\n", options: .backwards)
        let lineStart = nl.location == NSNotFound ? 0 : nl.location + 1
        return (before.components(separatedBy: "\n").count, before.length - lineStart + 1)
    }

    static func json(_ p: (line: Int, column: Int)) -> JSONValue {
        ["line": JSONValue(p.line), "column": JSONValue(p.column)]
    }
}
