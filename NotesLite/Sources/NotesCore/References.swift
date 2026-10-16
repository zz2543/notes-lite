import Foundation

/// Rewrites supported local Markdown references while preserving their labels and anchors.
/// Resolution always uses the document's location before the move.
enum References {
    static func updating(_ text: String, document: URL, destination: URL, old: URL, new: URL, root: URL, notes: [Note]) -> String {
        var output = text
        let patterns = [(#"\[\[([^\]\n]+)\]\]"#, true), (#"!?\[[^\]\n]*\]\(([^)\n]+)\)"#, false)]
        for (pattern, wiki) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = output as NSString
            var excluded: [NSRange] = []
            let lines = Markdown.lines(output)
            let types = Markdown.types(lines)
            var offset = 0
            for (line, type) in zip(lines, types) {
                let length = (line as NSString).length
                if type.isLiteral {
                    excluded.append(NSRange(location: offset, length: length))
                } else {
                    for span in Markdown.parseLine(line).spans where span.kind == .code {
                        excluded.append(NSRange(location: offset + span.content.location, length: span.content.length))
                    }
                }
                offset += length + 1
            }
            for match in regex.matches(in: output, range: NSRange(location: 0, length: ns.length)).reversed() {
                let range = match.range(at: 1)
                guard !excluded.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { continue }
                let original = ns.substring(with: range)
                let target = original.components(separatedBy: "|")[0].components(separatedBy: "#")[0]
                guard !target.isEmpty, !target.contains("://"), !target.hasPrefix("mailto:"), !target.hasPrefix("data:") else { continue }
                let decoded = target.removingPercentEncoding ?? target
                let named = wiki && (decoded as NSString).pathExtension.isEmpty ? decoded + ".md" : decoded
                let local = document.deletingLastPathComponent().appendingPathComponent(named).standardizedFileURL.resolvingSymlinksInPath()
                let rooted = root.appendingPathComponent(named).standardizedFileURL.resolvingSymlinksInPath()
                let resolved: URL?
                if FileManager.default.fileExists(atPath: local.path) { resolved = local }
                else if FileManager.default.fileExists(atPath: rooted.path) { resolved = rooted }
                else if wiki && !decoded.contains("/") {
                    let title = decoded.lowercased().hasSuffix(".md") ? String(decoded.dropLast(3)) : decoded
                    let matching = notes.filter { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
                    resolved = matching.count == 1 ? root.appendingPathComponent(matching[0].path) : nil
                } else { resolved = nil }
                guard let resolved, resolved.path.hasPrefix(root.path + "/") else { continue }
                guard resolved == old || document != destination else { continue }
                let finalTarget = resolved == old ? new : resolved
                var replacement: String
                if wiki {
                    replacement = String(finalTarget.path.dropFirst(root.path.count + 1))
                    if replacement.lowercased().hasSuffix(".md") { replacement = String(replacement.dropLast(3)) }
                } else {
                    replacement = relativePath(to: finalTarget, from: destination.deletingLastPathComponent())
                    replacement = replacement.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#()[] "))) ?? replacement
                }
                let suffix = String(original.dropFirst(target.count))
                let updated = replacement + suffix
                if let swiftRange = Range(range, in: output) { output.replaceSubrange(swiftRange, with: updated) }
            }
        }
        return output
    }

    static func relativePath(to target: URL, from directory: URL) -> String {
        let a = directory.standardizedFileURL.pathComponents
        let b = target.standardizedFileURL.pathComponents
        var shared = 0
        while shared < min(a.count, b.count), a[shared] == b[shared] { shared += 1 }
        return (Array(repeating: "..", count: a.count - shared) + b.dropFirst(shared)).joined(separator: "/")
    }
}
