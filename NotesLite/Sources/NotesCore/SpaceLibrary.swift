import Foundation

/// The folders a space looks at, which is also everything its homepage may read and write.
public enum SpaceScope: Equatable, Hashable, Sendable {
    case library
    case folders([String])

    /// `*` for the whole library, otherwise folder paths separated by commas.
    public init(meta: String) {
        let parts = meta.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        self = parts.contains("*") ? .library : .folders(parts.filter { !$0.isEmpty })
    }

    public var meta: String {
        switch self {
        case .library: "*"
        case .folders(let folders): folders.joined(separator: ", ")
        }
    }

    public func contains(_ path: String) -> Bool {
        switch self {
        case .library: true
        case .folders(let folders): folders.contains { $0.isEmpty || path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    public var label: String {
        switch self {
        case .library: "整个笔记库"
        case .folders(let folders): folders.map { $0.isEmpty ? "笔记库根目录" : $0 }.joined(separator: "、")
        }
    }
}

public struct Space: Identifiable, Equatable, Sendable {
    public var name: String
    public var icon: String
    public var scope: SpaceScope
    /// The whole space file, meta included.
    public var html: String
    public var id: String { name }
    public var path: String { SpaceLibrary.directory + "/" + name + ".html" }
    /// False while the file holds nothing but its meta, comments and whitespace.
    public var hasPage: Bool { !SpaceFile.body(html).isEmpty }
}

public enum SpaceError: LocalizedError, Equatable {
    case invalidName, exists(String), missing(String), emptyScope, scopeName(String)
    public var errorDescription: String? {
        switch self {
        case .invalidName: "空间名称不能为空，不能包含斜杠、冒号或以点开头。"
        case .exists(let name): "已经有名为「\(name)」的空间。"
        case .missing(let name): "找不到空间「\(name)」。"
        case .emptyScope: "请至少选择一个文件夹，或选择整个笔记库。"
        case .scopeName(let folder): "文件夹「\(folder)」的名称含有逗号，不能加入范围。"
        }
    }
}

/// Reads and writes the meta at the top of a space file.
enum SpaceFile {
    static let metaRe = try! NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive])
    static let attributeRe = try! NSRegularExpression(pattern: #"([A-Za-z-]+)\s*=\s*"([^"]*)""#)

    static func meta(_ html: String, _ name: String) -> String? {
        let ns = html as NSString
        for match in metaRe.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range) as NSString
            var attributes: [String: String] = [:]
            for a in attributeRe.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                attributes[tag.substring(with: a.range(at: 1)).lowercased()] = unescape(tag.substring(with: a.range(at: 2)))
            }
            if attributes["name"] == name { return attributes["content"] }
        }
        return nil
    }

    /// Replaces (or inserts at the top) one `<meta name=… content=…>`, leaving the page untouched.
    static func setting(_ html: String, _ name: String, _ value: String) -> String {
        let tag = "<meta name=\"\(name)\" content=\"\(escape(value))\">"
        let ns = html as NSString
        for match in metaRe.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let existing = ns.substring(with: match.range)
            if existing.range(of: #"name\s*=\s*"\#(name)""#, options: .regularExpression) != nil {
                return ns.replacingCharacters(in: match.range, with: tag)
            }
        }
        return tag + "\n" + html
    }

    static func body(_ html: String) -> String {
        var rest = metaRe.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "")
        rest = rest.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
    }
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// The spaces of one note library: `.留白/空间/<名称>.html`, their order, the authoring guide and the agent prompt.
public struct SpaceLibrary: Sendable {
    public static let directory = ".留白/空间"
    public static let guideName = "编写说明.md"
    static let orderName = "顺序.json"
    public let root: URL

    public init(root: URL) { self.root = root.resolvingSymlinksInPath().standardizedFileURL }

    public var folder: URL { root.appendingPathComponent(Self.directory) }
    public var guideURL: URL { folder.appendingPathComponent(Self.guideName) }
    public func url(of name: String) -> URL { folder.appendingPathComponent(name + ".html") }

    /// Spaces in the user's order; spaces missing from the order follow alphabetically.
    public func spaces() throws -> [Space] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        var found: [Space] = []
        for file in files where file.pathExtension.lowercased() == "html" {
            let name = file.deletingPathExtension().lastPathComponent
            guard !name.hasPrefix("."), let html = try? String(contentsOf: file, encoding: .utf8) else { continue }
            found.append(Self.space(name: name, html: html))
        }
        let order = self.order()
        return found.sorted { a, b in
            switch (order.firstIndex(of: a.name), order.firstIndex(of: b.name)) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    public func space(named name: String) throws -> Space {
        guard let html = try? String(contentsOf: url(of: name), encoding: .utf8) else { throw SpaceError.missing(name) }
        return Self.space(name: name, html: html)
    }

    static func space(name: String, html: String) -> Space {
        Space(name: name, icon: SpaceFile.meta(html, "lb-icon") ?? "", scope: SpaceScope(meta: SpaceFile.meta(html, "lb-scope") ?? ""), html: html)
    }

    @discardableResult public func create(name: String, icon: String, scope: SpaceScope) throws -> Space {
        try validate(name: name, scope: scope)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: url(of: name).path) else { throw SpaceError.exists(name) }
        let html = "<meta name=\"lb-scope\" content=\"\(SpaceFile.escape(scope.meta))\">\n<meta name=\"lb-icon\" content=\"\(SpaceFile.escape(icon))\">\n"
        try Data(html.utf8).write(to: url(of: name), options: .withoutOverwriting)
        try saveOrder(order().filter { $0 != name } + [name])
        try installGuide()
        return Self.space(name: name, html: html)
    }

    /// Renames and re-scopes a space, keeping its page.
    @discardableResult public func update(_ name: String, newName: String, icon: String, scope: SpaceScope) throws -> Space {
        try validate(name: newName, scope: scope)
        var html = try space(named: name).html
        html = SpaceFile.setting(SpaceFile.setting(html, "lb-icon", icon), "lb-scope", scope.meta)
        if newName != name {
            guard !FileManager.default.fileExists(atPath: url(of: newName).path) else { throw SpaceError.exists(newName) }
            try FileManager.default.moveItem(at: url(of: name), to: url(of: newName))
            try saveOrder(order().map { $0 == name ? newName : $0 })
        }
        try Data(html.utf8).write(to: url(of: newName), options: .atomic)
        return Self.space(name: newName, html: html)
    }

    /// Deletes only the space file; no note is touched.
    public func delete(_ name: String) throws {
        guard FileManager.default.fileExists(atPath: url(of: name).path) else { throw SpaceError.missing(name) }
        try FileManager.default.removeItem(at: url(of: name))
        try saveOrder(order().filter { $0 != name })
    }

    public func reorder(_ names: [String]) throws { try saveOrder(names) }

    func order() -> [String] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.orderName)),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return names
    }

    private func saveOrder(_ names: [String]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(names).write(to: folder.appendingPathComponent(Self.orderName), options: .atomic)
    }

    /// Writes the authoring guide when it is missing or differs from this version's.
    public func installGuide() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if (try? String(contentsOf: guideURL, encoding: .utf8)) == SpaceGuide.text { return }
        try Data(SpaceGuide.text.utf8).write(to: guideURL, options: .atomic)
    }

    private func validate(name: String, scope: SpaceScope) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"), !name.contains("\n") else { throw SpaceError.invalidName }
        if case .folders(let folders) = scope {
            guard !folders.isEmpty else { throw SpaceError.emptyScope }
            if let bad = folders.first(where: { $0.contains(",") }) { throw SpaceError.scopeName(bad) }
        }
    }

    /// Record tables inside the scope, as `路径#标题` with their header.
    public func recordTables(in scope: SpaceScope) -> [(source: String, header: [String])] {
        guard let scan = try? LibraryScan.run(root: root, previous: [:]) else { return [] }
        var result: [(String, [String])] = []
        for note in scan.notes.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) where scope.contains(note.path) {
            let body = scan.cache[note.path]?.body ?? ""
            let tables = RecordTable.all(in: body)
            for (index, table) in tables.enumerated() {
                let addressable = index == 0 || (table.heading.map { h in tables.first { $0.heading == h } == table } ?? false)
                guard addressable else { continue }
                let source = index == 0 && table.heading == nil ? note.path : note.path + (table.heading.map { "#" + $0 } ?? "")
                result.append((source, table.header))
            }
        }
        return result
    }

    /// What the user pastes to an external agent so it can write the homepage.
    public func prompt(for space: Space) throws -> String {
        try installGuide()
        let tables = recordTables(in: space.scope)
        var lines = [
            "请为留白笔记应用编写「\(space.name)」空间的空间主页。",
            "",
            "- 编写说明：\(guideURL.path)（请先完整阅读并遵守）",
            "- 空间文件：\(url(of: space.name).path)（保留开头的 meta，在其后写主页；不要修改 lb-scope）",
            "- 空间名称：\(space.name)",
            "- 范围：\(space.scope.label)",
            "- 范围内现有记录表：",
        ]
        if tables.isEmpty {
            lines.append("  - 暂无。可以用 lb-quick-add 或 lb.append 指定目标笔记和表头，留白会自动新建记录表。")
        } else {
            lines += tables.map { "  - \($0.source)：\($0.header.joined(separator: " | "))" }
        }
        lines += ["", "请围绕我每天的进展设计这个主页：用美观的图表展示进展，并提供快捷录入。数据只能存进范围内的记录表。"]
        return lines.joined(separator: "\n")
    }
}
