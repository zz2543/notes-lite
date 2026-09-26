import CryptoKit
import Foundation

/// `---`-fenced `key: value` lines at the top of a Markdown file. Only flat string values:
/// enough for Twain's command and automation files without pulling in a YAML parser.
public enum Frontmatter {
    public static func split(_ text: String) -> (fields: [String: String], body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ([:], text)
        }
        var fields: [String: String] = [:]
        for raw in lines[1..<end] {
            var line = raw
            if let hash = line.range(of: " #") { line = String(line[..<hash.lowerBound]) }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == "\"" || f == "'", value.last == f {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { fields[key] = value }
        }
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (fields, body)
    }
}

/// `{{name}}` placeholders. Unknown names are left as they are, so a typo shows in the prompt.
public enum Template {
    static let placeholder = try! NSRegularExpression(pattern: #"\{\{\s*([A-Za-z_]+)\s*\}\}"#)

    public static func render(_ template: String, _ vars: [String: String]) -> String {
        let ns = template as NSString
        var out = ""
        var last = 0
        for m in placeholder.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let name = ns.substring(with: m.range(at: 1))
            out += vars[name] ?? ns.substring(with: m.range)
            last = NSMaxRange(m.range)
        }
        return out + ns.substring(from: last)
    }

    public static func uses(_ template: String, _ name: String) -> Bool {
        render(template, [name: "\u{0}"]).contains("\u{0}")
    }
}

/// Shell-style path patterns: `*` within a folder, `**` across folders, `?` one character.
/// A pattern without `/` also matches a file of that name in any folder.
public enum Glob {
    public static func match(_ pattern: String, _ path: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return false }
        if !p.contains("/"), match(p, (path as NSString).lastPathComponent, anchoredName: true) { return true }
        return match(p, path, anchoredName: false)
    }

    static func match(_ p: String, _ s: String, anchoredName: Bool) -> Bool {
        var re = "^"
        var chars = Array(p)[...]
        while let c = chars.first {
            chars = chars.dropFirst()
            switch c {
            case "*":
                if chars.first == "*" {
                    chars = chars.dropFirst()
                    if chars.first == "/" { chars = chars.dropFirst(); re += "(?:.*/)?" } else { re += ".*" }
                } else {
                    re += "[^/]*"
                }
            case "?": re += "[^/]"
            default: re += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        re += "$"
        return s.range(of: re, options: .regularExpression) != nil
    }
}

/// A prompt the user keeps in `.twain/commands/<key>.md`; it shows up in ⌘K and the slash menu.
public struct UserCommand: Equatable, Sendable {
    public enum Scope: String, Sendable { case selection, note, vault }

    public var key: String
    public var title: String
    public var agent: AgentKind
    public var model: String?
    public var effort: String?
    public var scope: Scope
    public var icon: String
    public var prompt: String
    /// Path inside the vault, for "edit this command".
    public var file: String

    /// Nil when the file has no prompt or names an agent Twain does not know.
    public static func parse(file: String, text: String) -> UserCommand? {
        let (f, body) = Frontmatter.split(text)
        guard !body.isEmpty else { return nil }
        let stem = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let agent = AgentKind(rawValue: (f["agent"] ?? "claude").lowercased()) else { return nil }
        let key = (f["key"] ?? stem).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return UserCommand(key: key.isEmpty ? stem : key, title: f["title"] ?? stem, agent: agent,
                           model: f["model"].flatMap { $0.isEmpty ? nil : $0 },
                           effort: f["effort"].flatMap { $0.isEmpty ? nil : $0 },
                           scope: Scope(rawValue: f["scope"] ?? "") ?? (Template.uses(body, "selection") ? .selection : .note),
                           icon: f["icon"] ?? "sparkles", prompt: body, file: file)
    }
}

/// A prompt Twain runs by itself when something happens in the vault, from `.twain/automations/<id>.md`.
public struct Automation: Equatable, Sendable {
    public var id: String
    public var title: String
    /// Event names that trigger it (`note.saved`, …).
    public var on: [String]
    /// Paths it cares about; nil means every note.
    public var match: String?
    public var agent: AgentKind
    public var model: String?
    public var effort: String?
    /// Seconds of quiet after the last matching event before it runs.
    public var debounce: Int
    public var prompt: String
    public var file: String
    /// Changes whenever the file does; the user's approval is tied to it.
    public var fingerprint: String

    public static func parse(file: String, text: String) -> Automation? {
        let (f, body) = Frontmatter.split(text)
        let events = (f["on"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !body.isEmpty, !events.isEmpty, let agent = AgentKind(rawValue: (f["agent"] ?? "claude").lowercased()) else { return nil }
        let stem = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        let digest = SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return Automation(id: stem, title: f["title"] ?? stem, on: events,
                          match: f["match"].flatMap { $0.isEmpty ? nil : $0 }, agent: agent,
                          model: f["model"].flatMap { $0.isEmpty ? nil : $0 },
                          effort: f["effort"].flatMap { $0.isEmpty ? nil : $0 },
                          debounce: max(0, Int(f["debounce"] ?? "") ?? 60), prompt: body, file: file, fingerprint: digest)
    }

    /// Whether an event on `path` should (re)start this automation's countdown.
    public func triggers(event: String, path: String?) -> Bool {
        guard on.contains(event) else { return false }
        guard let match else { return true }
        guard let path else { return false }
        return Glob.match(match, path)
    }
}
