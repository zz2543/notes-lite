import Foundation

/// A model a CLI accepts for `--model` / `-m`. An empty `id` means "let the CLI decide".
public struct AgentModel: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// One line on what the model is for, as the CLI's own picker shows it.
    public let detail: String?
    /// Short family name the CLI also accepts as an alias ("Opus" for `--model opus`).
    public let family: String?
    /// False for models the CLI tucks behind "more models".
    public let primary: Bool
    /// Thinking levels, lightest first. Empty when the model has no adjustable thinking.
    public let efforts: [String]
    /// The level the model runs at when none is given.
    public let defaultEffort: String?

    public init(id: String, name: String, detail: String? = nil, family: String? = nil, primary: Bool = true,
                efforts: [String] = [], defaultEffort: String? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.family = family
        self.primary = primary
        self.efforts = efforts
        self.defaultEffort = defaultEffort
    }

    /// Whether `id` names this model, either exactly or by its family alias.
    public func matches(_ id: String) -> Bool {
        self.id == id || (family.map { $0.lowercased() == id.lowercased() } ?? false)
    }
}

/// Compares dotted version numbers found anywhere in two strings ("codex-cli 0.148.0" vs "0.155.0").
public func versionIsOlder(_ a: String, than b: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        guard let r = s.range(of: #"\d+(\.\d+)+"#, options: .regularExpression) else { return [] }
        return s[r].split(separator: ".").compactMap { Int($0) }
    }
    let x = parts(a), y = parts(b)
    guard !x.isEmpty, !y.isEmpty else { return false }
    for i in 0..<max(x.count, y.count) {
        let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
        if l != r { return l < r }
    }
    return false
}

public enum Effort {
    public static let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]

    public static func name(_ id: String) -> String {
        ["none": "关闭", "minimal": "最低", "low": "低", "medium": "中", "high": "高",
         "xhigh": "超高", "max": "最高", "ultra": "极限"][id] ?? id
    }

    /// `wanted` if the model offers it, else the nearest level it does offer.
    public static func clamp(_ wanted: String, to levels: [String]) -> String? {
        if levels.contains(wanted) { return wanted }
        guard let w = order.firstIndex(of: wanted) else { return levels.last }
        return levels.min { abs((order.firstIndex(of: $0) ?? 0) - w) < abs((order.firstIndex(of: $1) ?? 0) - w) }
    }
}

public extension [AgentModel] {
    /// Exact id first, then family alias among the primary models.
    func find(_ id: String) -> AgentModel? {
        first { $0.id == id } ?? first { $0.primary && $0.matches(id) } ?? first { $0.matches(id) }
    }
}

public extension AgentKind {
    /// Models offered when the CLI's own model list can't be read.
    var builtinModels: [AgentModel] {
        switch self {
        case .claude:
            // `claude --model` takes these aliases and resolves them to the latest model of each family.
            let levels = ["low", "medium", "high", "xhigh", "max"]
            return [
                AgentModel(id: "opus", name: "Opus（最新）", family: "Opus", efforts: levels),
                AgentModel(id: "sonnet", name: "Sonnet（最新）", family: "Sonnet", efforts: levels),
                AgentModel(id: "fable", name: "Fable（最新）", family: "Fable", efforts: levels),
                AgentModel(id: "haiku", name: "Haiku（最新）", family: "Haiku"),
            ]
        case .codex:
            return []
        }
    }
}

public enum ClaudeModels {
    /// Reads a file from `~/.claude/cache/model-catalog/`: the list Claude Code's own `/model` picker shows.
    public static func parseCatalog(_ data: Data) -> [AgentModel] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let catalog = obj["catalog"] as? [String: Any],
              let config = catalog["config"] as? [String: Any],
              let models = config["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { m in
            guard let id = m["id"] as? String, !id.isEmpty else { return nil }
            let thinking = m["thinking"] as? [String: Any]
            let options = thinking?["effort_options"] as? [[String: Any]] ?? []
            let def = options.first { ($0["badge"] as? [String: Any])?["message"] as? String == "Default" }
            return AgentModel(id: id,
                              name: m["name"] as? String ?? id,
                              detail: m["description"] as? String,
                              family: m["short_name"] as? String,
                              primary: (m["section"] as? String ?? "main") == "main",
                              efforts: options.compactMap { $0["id"] as? String },
                              defaultEffort: def?["id"] as? String)
        }
    }

    /// The newest catalog Claude Code wrote, preferring the CLI's (`-cc.json`) over the desktop app's.
    public static func latestCatalog(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        let json = files.filter { $0.pathExtension == "json" }.sorted { date($0) > date($1) }
        return json.first { $0.lastPathComponent.hasSuffix("-cc.json") } ?? json.first
    }

    /// `model` and `effortLevel` from `~/.claude/settings.json`: what `claude` uses without flags.
    public static func configured(_ settings: Data) -> (model: String?, effort: String?) {
        guard let obj = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] else { return (nil, nil) }
        func s(_ k: String) -> String? { (obj[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return (s("model"), s("effortLevel"))
    }
}

public enum CodexModels {
    /// Reads `~/.codex/models_cache.json`: the models Codex shows in its own picker, best first.
    public static func parseCache(_ data: Data) -> [AgentModel] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models
            .filter { ($0["visibility"] as? String ?? "list") == "list" }
            .compactMap { m -> (Int, AgentModel)? in
                guard let slug = m["slug"] as? String, !slug.isEmpty else { return nil }
                let levels = (m["supported_reasoning_levels"] as? [[String: Any]] ?? []).compactMap { $0["effort"] as? String }
                return (m["priority"] as? Int ?? .max,
                        AgentModel(id: slug, name: m["display_name"] as? String ?? slug, detail: m["description"] as? String,
                                   efforts: levels, defaultEffort: m["default_reasoning_level"] as? String))
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    /// The Codex version that wrote the cache. A newer one than the CLI on PATH may list models that CLI can't run.
    public static func cacheClientVersion(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["client_version"] as? String
    }

    /// The top-level `model = "…"` in `~/.codex/config.toml`, i.e. what Codex uses without `-m`.
    public static func configuredModel(_ toml: String) -> String? { topLevel("model", in: toml) }

    /// The top-level `model_reasoning_effort = "…"` in `~/.codex/config.toml`.
    public static func configuredEffort(_ toml: String) -> String? { topLevel("model_reasoning_effort", in: toml) }

    private static func topLevel(_ key: String, in toml: String) -> String? {
        for raw in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            guard line.hasPrefix(key), let eq = line.firstIndex(of: "=") else { continue }
            guard line[..<eq].trimmingCharacters(in: .whitespaces) == key else { continue }
            let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return v.isEmpty ? nil : v
        }
        return nil
    }
}
