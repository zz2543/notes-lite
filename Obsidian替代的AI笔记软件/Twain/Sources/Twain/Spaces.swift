import AppKit
import TwainCore

/// Spaces: modes the user builds (日记, 自律, 子弹笔记, LLM Wiki, or their own), each a plugin
/// folder with a dashboard. They add capability — entries from templates, data from anywhere,
/// charts, rules agents follow, pipelines — rather than rearranging the same panels.
extension AppModel {
    var pluginsDir: URL? { vault?.root.appendingPathComponent(".twain/plugins") }

    func loadPlugins() {
        guard let v = vault, let dir = pluginsDir else { plugins = []; return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            // First time: the workbench, so the feature is visible and editable from day one.
            _ = try? installTemplate(SpaceTemplate.workbench, name: "工作台", folder: "", open: false)
        }
        var found: [Plugin] = []
        for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            let manifest = u.appendingPathComponent("manifest.json")
            guard !fm.fileExists(atPath: u.appendingPathComponent(".disabled").path),
                  let data = try? Data(contentsOf: manifest) else { continue }
            do { found.append(try Plugin.parse(dir: v.relative(u.path), json: data)) } catch let e as RPCError {
                showToast(e.message)
            } catch {}
        }
        // The workbench first, then by name.
        plugins = found.sorted { ($0.id == "workbench" ? 0 : 1, $0.name) < ($1.id == "workbench" ? 0 : 1, $1.name) }
        // Code blocks a plugin draws are drawn again with its current page.
        BlockRenderer.shared.reloadPlugins()
        noteFilesChanged?()
    }

    var spaces: [Plugin] { plugins.filter { $0.space != nil } }
    var currentSpace: Plugin? { activeSpace.flatMap { id in plugins.first { $0.id == id } } }

    /// Commands and pipelines plugins bring along, read like the vault's own.
    func pluginFiles(_ sub: String) -> [(String, String)] {
        guard let v = vault else { return [] }
        return plugins.flatMap { p -> [(String, String)] in
            let dir = v.root.appendingPathComponent(p.dir).appendingPathComponent(sub)
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "md" }
                .compactMap { u in (try? String(contentsOf: u, encoding: .utf8)).map { (v.relative(u.path), $0) } }
        }
    }

    /// Creates a space from a template: its plugin folder, the space folder, starter notes.
    @discardableResult
    func installTemplate(_ t: SpaceTemplate, name: String, folder: String, open: Bool = true) throws -> String {
        guard let v = vault, let dir = pluginsDir else { throw RPCError(RPCError.noVault, "没有打开库") }
        let fm = FileManager.default
        var id = t.id == "blank" ? Self.slug(name) : t.id
        var n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(id).path) { id = (t.id == "blank" ? Self.slug(name) : t.id) + "-\(n)"; n += 1 }
        let folder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        func fill(_ s: String) -> String {
            s.replacingOccurrences(of: "%FOLDER%", with: folder).replacingOccurrences(of: "%ID%", with: id)
                .replacingOccurrences(of: "%NAME%", with: name)
        }
        let pdir = dir.appendingPathComponent(id)
        for (path, text) in t.files {
            var body = fill(text)
            if path == "manifest.json", var o = (try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)))?.object {
                o["id"] = .string(id)
                o["name"] = .string(name)
                body = JSONValue.object(o).text(pretty: true)
            }
            let u = pdir.appendingPathComponent(path)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (body.hasSuffix("\n") ? body : body + "\n").write(to: u, atomically: true, encoding: .utf8)
        }
        if !folder.isEmpty { try? fm.createDirectory(at: v.url(folder), withIntermediateDirectories: true) }
        for (path, text) in t.notes {
            let rel = fill(path)
            if !fm.fileExists(atPath: v.url(rel).path) { v.forceWrite(rel, fill(text)) }
        }
        v.scanSoon()
        loadPlugins()
        loadPipelines()
        loadVaultConfig()
        if open { openSpace(id) }
        return id
    }

    static func slug(_ name: String) -> String {
        let s = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let t = s.split(separator: "-").joined(separator: "-")
        return t.isEmpty ? "space" : String(t.prefix(40))
    }

    func openSpace(_ id: String) {
        flushSave()
        openDesk = nil
        activeSpace = id
        if selection != "space:" + id { selection = "space:" + id }
    }

    /// Opens the space's entry for today (or `date`), creating it from the template if needed.
    func openEntry(_ p: Plugin, date: Date = Date()) {
        guard let v = vault, let s = p.space, let titleTemplate = s.entryTitle else { return }
        let vars = DateVars.vars(date)
        var title = Template.render(titleTemplate, vars).replacingOccurrences(of: "/", with: "-")
        if title.isEmpty { title = vars["date"]! }
        let rel = (s.folder.isEmpty ? "" : s.folder + "/") + title + ".md"
        if v.note(rel) == nil && !FileManager.default.fileExists(atPath: v.url(rel).path) {
            var text = "# \(title)\n"
            if let t = s.entryTemplate, let raw = try? String(contentsOf: v.root.appendingPathComponent(p.dir).appendingPathComponent(t), encoding: .utf8) {
                text = Template.render(raw, vars.merging(["title": title]) { a, _ in a })
            }
            v.forceWrite(rel, text)
            emit("note.created", source: "user", ["path": .string(rel)])
        }
        open(rel)
        requestFocus(caret: (editorText as NSString).length)
    }

    /// The entry note for a day, when it exists.
    func entryRel(_ p: Plugin, date: Date) -> String? {
        guard let v = vault, let s = p.space, let t = s.entryTitle else { return nil }
        let title = Template.render(t, DateVars.vars(date)).replacingOccurrences(of: "/", with: "-")
        let rel = (s.folder.isEmpty ? "" : s.folder + "/") + title + ".md"
        return v.note(rel) != nil ? rel : nil
    }

    /// Rules of the space the open note belongs to, for agents working on it.
    func spaceRules(for rel: String?) -> (name: String, rules: String)? {
        guard let rel, let v = vault else { return nil }
        let owner = spaces.filter { p in
            guard let f = p.space?.folder, !f.isEmpty else { return false }
            return rel.hasPrefix(f + "/")
        }.max { $0.space!.folder.count < $1.space!.folder.count }
        guard let p = owner, let file = p.space?.rules,
              let text = try? String(contentsOf: v.root.appendingPathComponent(p.dir).appendingPathComponent(file), encoding: .utf8) else { return nil }
        return (p.name, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Writes a space's edited module list back into its manifest.
    func saveModules(_ plugin: Plugin, _ modules: [JSONValue]) {
        guard let v = vault else { return }
        let u = v.root.appendingPathComponent(plugin.dir).appendingPathComponent("manifest.json")
        try? (plugin.withModules(modules).text(pretty: true) + "\n").write(to: u, atomically: true, encoding: .utf8)
        loadPlugins()
    }

    func setPluginEnabled(_ p: Plugin, _ on: Bool) {
        guard let v = vault else { return }
        let marker = v.root.appendingPathComponent(p.dir).appendingPathComponent(".disabled")
        if on { try? FileManager.default.removeItem(at: marker) } else { FileManager.default.createFile(atPath: marker.path, contents: nil) }
        if !on, activeSpace == p.id { activeSpace = nil }
        loadPlugins()
        loadPipelines()
        loadVaultConfig()
    }

    /// Checks or unchecks a task in any note: through the editor when it is the open note (undoable), else on disk.
    func toggleTask(rel: String, line: Int) {
        guard let v = vault else { return }
        if rel == activeRel {
            var lines = Markdown.lines(editorText)
            guard lines.indices.contains(line - 1) else { return }
            lines[line - 1] = Markdown.toggleTask(lines[line - 1])
            editorDidChange(lines.joined(separator: "\n"))
            editorVersion += 1
            return
        }
        guard pending[rel] == nil, !writing.contains(rel), let text = v.diskContent(rel) else { return }
        var lines = Markdown.lines(text)
        guard lines.indices.contains(line - 1) else { return }
        lines[line - 1] = Markdown.toggleTask(lines[line - 1])
        _ = v.write(rel, lines.joined(separator: "\n"))
        tick += 1
    }
}
