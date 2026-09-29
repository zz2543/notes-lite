import AppKit
import TwainCore

/// How a pasted picture's file is named.
enum AttachmentNaming: String, CaseIterable, Identifiable {
    /// `Pasted image 20260928103000.png`, as Obsidian names them.
    case pasted
    /// `笔记名 20260928103000.png`
    case noteTime
    /// `笔记名-1.png`, `笔记名-2.png`…
    case noteNumber

    var id: String { rawValue }
    var label: String {
        switch self {
        case .pasted: "Pasted image 时间"
        case .noteTime: "笔记名 时间"
        case .noteNumber: "笔记名-序号"
        }
    }
}

/// Where pasted pictures go, in the terms of Obsidian's `attachmentFolderPath`.
enum AttachmentPlace: String, CaseIterable, Identifiable {
    /// One folder in the vault ("附件").
    case folder
    /// Next to the note ("./").
    case noteFolder
    /// A folder next to the note ("./assets").
    case subfolder
    /// The vault's top level ("/").
    case root

    var id: String { rawValue }
    var label: String {
        switch self {
        case .folder: "库里的固定文件夹"
        case .noteFolder: "当前笔记所在的文件夹"
        case .subfolder: "当前笔记旁的子文件夹"
        case .root: "库的根目录"
        }
    }

    /// Reads a stored `attachmentFolderPath`.
    static func parse(_ setting: String) -> (AttachmentPlace, String) {
        switch setting {
        case "": return (.folder, "附件")
        case "/": return (.root, "")
        case "./", ".": return (.noteFolder, "")
        case let s where s.hasPrefix("./"): return (.subfolder, String(s.dropFirst(2)))
        default: return (.folder, setting.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
    }

    /// The `attachmentFolderPath` for this place and folder name.
    func setting(_ name: String) -> String {
        let n = name.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).replacingOccurrences(of: "..", with: "")
        switch self {
        case .folder: return n.isEmpty ? "附件" : n
        case .noteFolder: return "./"
        case .subfolder: return "./" + (n.isEmpty ? "assets" : n)
        case .root: return "/"
        }
    }
}

/// Pictures and videos in notes: where pasted ones go, and how `![[…]]` finds its file.
extension AppModel {
    private var obsidianConfig: URL? { vault?.root.appendingPathComponent(".obsidian/app.json") }
    private var attachmentDefaultsKey: String { "attachmentFolderPath." + (vault?.rootPath ?? "") }

    /// The vault's `attachmentFolderPath`. Kept in `.obsidian/app.json` when the vault is also an
    /// Obsidian vault, so both apps put pictures in the same place; otherwise in Twain's settings.
    var attachmentSetting: String {
        get {
            if let config = obsidianConfig, let data = try? Data(contentsOf: config),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json["attachmentFolderPath"] as? String ?? ""
            }
            return UserDefaults.standard.string(forKey: attachmentDefaultsKey) ?? ""
        }
        set {
            guard let v = vault else { return }
            let dir = v.root.appendingPathComponent(".obsidian")
            guard FileManager.default.fileExists(atPath: dir.path), let config = obsidianConfig else {
                UserDefaults.standard.set(newValue, forKey: attachmentDefaultsKey)
                return
            }
            // Keep every other Obsidian setting as it is.
            var json = (try? Data(contentsOf: config)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            json["attachmentFolderPath"] = newValue
            if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                do { try data.write(to: config, options: .atomic) } catch { showToast("没能写入 .obsidian/app.json：\(error.localizedDescription)") }
            }
        }
    }

    /// Whether the setting lives in `.obsidian/app.json`.
    var attachmentSettingIsShared: Bool {
        guard let v = vault else { return false }
        return FileManager.default.fileExists(atPath: v.root.appendingPathComponent(".obsidian").path)
    }

    /// The folder (vault-relative) a picture pasted into the open note goes to.
    var attachmentFolder: String {
        let noteFolder = editor.activeRel.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        let (place, name) = AttachmentPlace.parse(attachmentSetting)
        switch place {
        case .folder: return name
        case .root: return ""
        case .noteFolder: return noteFolder
        case .subfolder: return (noteFolder as NSString).appendingPathComponent(name)
        }
    }

    /// The file name for a pasted picture, following `attachmentNaming`.
    func pastedName(ext: String, date: Date = Date()) -> String {
        let f = DateFormatter()
        // Fixed digits whatever the user's locale: a 12-hour clock would put 上午/PM in the name.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        let stamp = f.string(from: date)
        let note = editor.activeRel.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? "未命名"
        switch prefs.attachmentNaming {
        case .pasted: return "Pasted image \(stamp).\(ext)"
        case .noteTime: return "\(note) \(stamp).\(ext)"
        case .noteNumber: return "\(note)-1.\(ext)"
        }
    }

    func resolveEmbed(_ target: String) -> URL? {
        let t = target.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return URL(string: t) }
        if t.hasPrefix("file://") { return URL(string: t) }
        guard let v = vault, let rel = v.attachment(t, from: editor.activeRel) else { return nil }
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
        guard let ref, !ref.isHTML, ref.rel != editor.activeRel, let text = v.diskContent(ref.rel) else { return nil }
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
    /// `numbered`: the name ends in `-1` and counts up instead of getting ` 2`, ` 3`.
    private func attachmentPath(_ name: String, numbered: Bool = false) -> String {
        guard let v = vault else { return name }
        let folder = attachmentFolder
        var base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        // `笔记-1.png` counts up from its own number; other names get ` 2`, ` 3`…
        var n = 1
        if numbered, let dash = base.range(of: "-", options: .backwards), let k = Int(base[dash.upperBound...]) {
            n = k
            base = String(base[..<dash.lowerBound])
        }
        while true {
            let file = numbered ? "\(base)-\(n).\(ext)" : n == 1 ? name : "\(base) \(n).\(ext)"
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
        let rel = attachmentPath(pastedName(ext: ext), numbered: prefs.attachmentNaming == .noteNumber)
        do {
            try FileManager.default.createDirectory(at: v.url(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: v.url(rel))
        } catch {
            showToast("没能保存图片：\(error.localizedDescription)")
            return nil
        }
        v.attachmentAdded(rel)
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
        v.attachmentAdded(rel)
        return embedName(rel)
    }
}
