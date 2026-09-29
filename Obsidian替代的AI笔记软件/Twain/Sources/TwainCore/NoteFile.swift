import Foundation

/// Facts about a note file and its text that decide how the editor can show it.
public enum NoteFile {
    /// Longer lines are more than TextKit can typeset and edit smoothly.
    public static let oversizedLine = 100_000
    /// How much of an oversized line is shown.
    public static let shownOfLongLine = 2000

    /// Why `u` can't be shown as text (binary, far too large); nil when it can.
    public static func unreadableReason(_ u: URL) -> String? {
        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 8 * 1024 * 1024 { return "这个文件有 \(size / 1024 / 1024) MB，超出了编辑器能流畅打开的大小。" }
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        let head = h.readData(ofLength: 8192)
        if head.contains(0) { return "这个文件含有二进制内容（例如全是空字节），不是文本笔记，可能已经损坏。" }
        return nil
    }

    /// Whether some line of `text` is longer than `oversizedLine` bytes.
    public static func hasOversizedLine(_ text: String) -> Bool {
        guard text.utf8.count > oversizedLine else { return false }
        var run = 0
        for b in text.utf8 {
            if b == 0x0A { run = 0 } else { run += 1; if run > oversizedLine { return true } }
        }
        return false
    }

    /// `text` with each huge line cut to its start and a note of what was left out. Shown
    /// read-only; the file is never written from it.
    public static func clippedForDisplay(_ text: String) -> String {
        Markdown.lines(text).map { line -> String in
            let n = (line as NSString).length
            guard n > shownOfLongLine else { return line }
            return (line as NSString).substring(to: shownOfLongLine) + " …（此行还有 \(n - shownOfLongLine) 个字符未显示）"
        }.joined(separator: "\n")
    }

    /// UTF-16 offset of the start of 1-based `line`, clamped to the text.
    public static func offset(ofLine line: Int, in text: String) -> Int {
        let ns = text as NSString
        var loc = 0, n = 1
        while n < line, loc < ns.length {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(r)
            n += 1
        }
        return min(loc, ns.length)
    }

    /// Where a proposal for a note that doesn't exist yet goes. Refuses paths outside the vault
    /// and hidden ones.
    public static func newNotePath(_ ref: String) throws -> String {
        var rel = ref.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = rel.split(separator: "/")
        guard !rel.isEmpty, !parts.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else {
            throw RPCError(RPCError.invalidParams, "笔记路径不合法：\(ref)")
        }
        if !rel.lowercased().hasSuffix(".md") { rel += ".md" }
        return rel
    }
}

/// Who wrote a file: a terminal agent gets the credit only when its transcript shows the write.
public enum WriteAttribution {
    /// What an agent's recent steps touched: paths its edit tools wrote, and the text of the
    /// steps (shell commands, patches), from the last `window` events.
    public static func recent(_ events: [AgentEvent], window: Int = 40) -> (paths: Set<String>, steps: [String]) {
        var paths = Set<String>()
        var steps: [String] = []
        for e in events.suffix(window) {
            if case let .step(_, text, write) = e {
                if let write { paths.insert(write) }
                steps.append(text)
            }
        }
        return (paths, steps)
    }

    /// Whether those steps account for a change to `rel` (vault-relative) in the vault at `root`.
    public static func explains(_ rel: String, root: String, paths: Set<String>, steps: [String]) -> Bool {
        let abs = (root as NSString).appendingPathComponent(rel)
        let name = (rel as NSString).lastPathComponent
        return paths.contains(abs) || paths.contains(rel) || steps.contains { $0.contains(name) }
    }
}

public extension ClaudeStream {
    /// The folder under `~/.claude/projects` where Claude Code keeps the sessions it ran in `cwd`.
    static func projectFolderName(cwd: String) -> String {
        String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }
}

/// Keeps a cache folder from growing forever.
public enum CacheFolder {
    /// Removes sibling folders of `dir` in `base` that share its prefix before the last "-" (older
    /// versions of the same cache), then files not used for `maxAge`, then the oldest until the
    /// folder is under `maxBytes`. "Used" is the modification date; readers touch it on a hit.
    public static func prune(_ dir: URL, olderVersionsIn base: URL, now: Date = Date(), maxAge: TimeInterval, maxBytes: Int) {
        let fm = FileManager.default
        let name = dir.lastPathComponent
        let prefix = name.split(separator: "-").dropLast().joined(separator: "-") + "-"
        for old in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix(prefix) && old.lastPathComponent != name {
            try? fm.removeItem(at: old)
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        var files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []).compactMap { u -> (URL, Date, Int)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
        }
        files.sort { $0.1 < $1.1 }
        var total = files.reduce(0) { $0 + $1.2 }
        for (u, date, size) in files where now.timeIntervalSince(date) > maxAge || total > maxBytes {
            try? fm.removeItem(at: u)
            total -= size
        }
    }
}
