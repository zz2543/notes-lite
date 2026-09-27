import Foundation

/// A plugin is a folder, `.twain/plugins/<id>/`, with a `manifest.json`. It can bring a space
/// (a mode like 日记 or 自律: a folder, a template for new entries, a dashboard of modules, rules
/// for agents), and its own commands and pipelines (`commands/*.md`, `pipelines/*.md`).
/// Modules are declarative JSON the app draws natively; `html` modules run the plugin's own page.
public struct Plugin: Equatable, Sendable {
    public struct Space: Equatable, Sendable {
        /// Notes of this space live here ("" is the whole vault).
        public var folder: String
        /// Title template for a new entry, e.g. "{{date}}"; nil when the space has no entries.
        public var entryTitle: String?
        /// Template file (inside the plugin) for a new entry's text.
        public var entryTemplate: String?
        public var modules: [JSONValue]
        /// File (inside the plugin) with rules agents follow when working on this space's notes.
        public var rules: String?
    }

    public var id: String
    public var name: String
    public var icon: String
    public var summary: String
    public var space: Space?
    /// Labels and units for data collections, e.g. {"sleep": {"label": "睡眠", "fields": {"hours": {"unit": "小时"}}}}
    public var collections: [String: JSONValue]
    /// The folder, relative to the vault.
    public var dir: String
    /// The manifest as written, so edits keep fields Twain doesn't know.
    public var raw: JSONValue

    public static func parse(dir: String, json: Data) throws -> Plugin {
        guard let raw = try? JSONDecoder().decode(JSONValue.self, from: json), raw.object != nil else {
            throw RPCError(RPCError.invalidParams, "\(dir)/manifest.json 不是合法的 JSON 对象")
        }
        let id = raw["id"]?.string ?? (dir as NSString).lastPathComponent
        var space: Space?
        if let s = raw["space"], s.object != nil {
            space = Space(folder: (s["folder"]?.string ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
                          entryTitle: s["entry"]?["title"]?.string, entryTemplate: s["entry"]?["template"]?.string,
                          modules: s["modules"]?.array ?? [], rules: s["rules"]?.string)
        }
        return Plugin(id: id, name: raw["name"]?.string ?? id, icon: raw["icon"]?.string ?? "square.grid.2x2",
                      summary: raw["description"]?.string ?? "", space: space,
                      collections: raw["collections"]?.object ?? [:], dir: dir, raw: raw)
    }

    /// The manifest with `space.modules` replaced, for saving an edited dashboard.
    public func withModules(_ modules: [JSONValue]) -> JSONValue {
        guard var o = raw.object else { return raw }
        var s = o["space"]?.object ?? [:]
        s["modules"] = .array(modules)
        o["space"] = .object(s)
        return .object(o)
    }

    /// Label and unit for a collection field, from the manifest.
    public func label(collection: String, field: String?) -> (label: String, unit: String) {
        let c = collections[collection]
        guard let field else { return (c?["label"]?.string ?? collection, "") }
        let f = c?["fields"]?[field]
        return (f?["label"]?.string ?? field, f?["unit"]?.string ?? "")
    }
}

/// Values for entry titles and templates: {{date}} 2026-09-27, {{time}} 21:30, {{weekday}} 星期日,
/// {{week}} 2026-W39, {{month}} 2026-09, {{year}} 2026, {{yesterday}}, {{tomorrow}}.
public enum DateVars {
    public static func vars(_ d: Date = Date()) -> [String: String] {
        let cal = Calendar(identifier: .iso8601)
        func f(_ fmt: String, _ date: Date = d) -> String {
            let x = DateFormatter()
            x.locale = Locale(identifier: "zh_CN")
            x.dateFormat = fmt
            return x.string(from: date)
        }
        let week = cal.component(.weekOfYear, from: d), wy = cal.component(.yearForWeekOfYear, from: d)
        return ["date": f("yyyy-MM-dd"), "time": f("HH:mm"), "weekday": f("EEEE"), "week": String(format: "%d-W%02d", wy, week),
                "month": f("yyyy-MM"), "year": f("yyyy"),
                "yesterday": f("yyyy-MM-dd", cal.date(byAdding: .day, value: -1, to: d)!),
                "tomorrow": f("yyyy-MM-dd", cal.date(byAdding: .day, value: 1, to: d)!)]
    }
}
