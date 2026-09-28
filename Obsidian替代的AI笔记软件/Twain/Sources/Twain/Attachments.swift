import AppKit
import TwainCore

/// Pictures and videos in notes: where pasted ones go, and how `![[…]]` finds its file.
extension AppModel {
    /// Obsidian's `attachmentFolderPath` when the vault has one, so both apps agree; else 附件/.
    var attachmentFolder: String {
        guard let v = vault else { return "附件" }
        let config = v.root.appendingPathComponent(".obsidian/app.json")
        let setting = (try? Data(contentsOf: config))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["attachmentFolderPath"] as? String
        let noteFolder = activeRel.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        switch setting {
        case nil, "": return "附件"
        case "/": return ""
        case let s? where s == "./" || s == ".": return noteFolder
        case let s? where s.hasPrefix("./"):
            return (noteFolder as NSString).appendingPathComponent(String(s.dropFirst(2)))
        case let s?: return s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }

    func resolveEmbed(_ target: String) -> URL? {
        let t = target.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return URL(string: t) }
        if t.hasPrefix("file://") { return URL(string: t) }
        guard let v = vault, let rel = v.attachment(t, from: activeRel) else { return nil }
        return v.url(rel)
    }

    /// `![[另一篇笔记]]`, `![[笔记#小节]]`, `![[文件夹/笔记|别名]]` → that note and its text.
    func resolveEmbeddedNote(_ target: String) -> (rel: String, title: String, text: String)? {
        guard let v = vault else { return nil }
        var name = target.split(separator: "|", maxSplits: 1).first.map(String.init) ?? target
        name = (name.split(separator: "#", maxSplits: 1).first.map(String.init) ?? name).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let ref: NoteRef?
        if name.contains("/") {
            let rel = name.hasSuffix(".md") ? name : name + ".md"
            ref = v.note(rel) ?? v.notes.first { $0.rel.lowercased().hasSuffix(rel.lowercased()) }
        } else {
            ref = v.note(titled: name.hasSuffix(".md") ? String(name.dropLast(3)) : name)
        }
        guard let ref, !ref.isHTML, ref.rel != activeRel, let text = v.diskContent(ref.rel) else { return nil }
        return (ref.rel, ref.title, text)
    }

    /// The plugin page that renders fenced blocks of `lang` (manifest `"blocks": {"chart": "blocks/chart.html"}`).
    func blockRendererPage(_ lang: String) -> String? {
        for p in plugins {
            if let page = p.raw["blocks"]?[lang]?.string { return p.dir + "/" + page }
        }
        return nil
    }

    /// A free path for `name` in the attachment folder.
    private func attachmentPath(_ name: String) -> String {
        guard let v = vault else { return name }
        let folder = attachmentFolder
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 1
        while true {
            let file = n == 1 ? name : "\(base) \(n).\(ext)"
            let rel = folder.isEmpty ? file : folder + "/" + file
            if !FileManager.default.fileExists(atPath: v.url(rel).path) { return rel }
            n += 1
        }
    }

    /// How a note should refer to `rel`: by name when that is unambiguous, else by path.
    private func embedName(_ rel: String) -> String {
        guard let v = vault else { return rel }
        let name = (rel as NSString).lastPathComponent
        return (v.attachments[name.lowercased()]?.count ?? 0) > 1 ? rel : name
    }

    /// Saves pasted image data; returns the name to embed.
    func saveAttachment(_ data: Data, ext: String) -> String? {
        guard let v = vault else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        let rel = attachmentPath("Pasted image \(f.string(from: Date())).\(ext)")
        do {
            try FileManager.default.createDirectory(at: v.url(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: v.url(rel))
        } catch {
            showToast("没能保存图片：\(error.localizedDescription)")
            return nil
        }
        v.scan()
        return embedName(rel)
    }

    /// A file dropped or pasted in: linked where it is when it's already in the vault, copied in otherwise.
    func importAttachment(_ url: URL) -> String? {
        guard let v = vault else { return nil }
        let inside = v.relative(url.path)
        if !inside.hasPrefix("/"), FileManager.default.fileExists(atPath: v.url(inside).path) { return embedName(inside) }
        let rel = attachmentPath(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: v.url(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: v.url(rel))
        } catch {
            showToast("没能复制 \(url.lastPathComponent)：\(error.localizedDescription)")
            return nil
        }
        v.scan()
        return embedName(rel)
    }
}
