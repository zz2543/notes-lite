import AppKit
import TwainCore

/// Folders as first-class things: create, rename, move into, delete, and the folder note —
/// `Folder/Folder.md`, opened by clicking the folder (the Obsidian Folder Notes convention).
extension Vault {
    /// `Folder/Folder.md` when it exists.
    func folderNote(_ folder: String) -> NoteRef? {
        guard !folder.isEmpty else { return nil }
        return note(folder + "/" + (folder as NSString).lastPathComponent + ".md")
    }

    func isFolderNote(_ n: NoteRef) -> Bool {
        !n.folder.isEmpty && (n.folder as NSString).lastPathComponent == n.title
    }

    static func validName(_ name: String) throws -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw RenameError.empty }
        guard !t.contains("/"), !t.contains(":"), !t.hasPrefix(".") else { throw RenameError.invalid }
        return t
    }

    func createFolder(in parent: String, name: String) throws -> String {
        let t = try Self.validName(name)
        var rel = parent.isEmpty ? t : parent + "/" + t
        var n = 2
        while FileManager.default.fileExists(atPath: url(rel).path) {
            rel = (parent.isEmpty ? "" : parent + "/") + "\(t) \(n)"
            n += 1
        }
        try FileManager.default.createDirectory(at: url(rel), withIntermediateDirectories: true)
        scan()
        return rel
    }

    /// Renames the folder, and its folder note with it. Returns the new path.
    func renameFolder(_ folder: String, to name: String) throws -> String {
        let t = try Self.validName(name)
        let parent = (folder as NSString).deletingLastPathComponent
        let new = parent.isEmpty ? t : parent + "/" + t
        guard new != folder else { return folder }
        if new.lowercased() != folder.lowercased(), FileManager.default.fileExists(atPath: url(new).path) {
            throw RenameError.taken(t)
        }
        let oldName = (folder as NSString).lastPathComponent
        let hadNote = folderNote(folder) != nil
        try FileManager.default.moveItem(at: url(folder), to: url(new))
        if hadNote {
            try? FileManager.default.moveItem(at: url(new + "/" + oldName + ".md"), to: url(new + "/" + t + ".md"))
        }
        // What we knew of the files moves with them.
        for (k, v) in known where k.hasPrefix(folder + "/") {
            var nk = new + String(k.dropFirst(folder.count))
            if hadNote, nk == new + "/" + oldName + ".md" { nk = new + "/" + t + ".md" }
            forget(k)
            acknowledge(nk, content: v)
        }
        scan()
        return new
    }

    /// Moves a note into `folder`, keeping its name (numbered when taken). Returns the new path.
    func move(_ rel: String, to folder: String) throws -> String {
        guard (rel as NSString).deletingLastPathComponent != folder else { return rel }
        let ref = NoteRef(rel: rel)
        let new = uniqueRel(title: ref.title, folder: folder, ext: ref.ext.isEmpty ? "md" : ref.ext)
        try FileManager.default.createDirectory(at: url(folder), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url(rel), to: url(new))
        let k = known[rel]
        forget(rel)
        acknowledge(new, content: k)
        scan()
        return new
    }
}

extension AppModel {
    func newNote(in folder: String) {
        guard let v = vault else { return }
        flushSave()
        let rel = v.create(title: "未命名", folder: folder, content: "# 未命名\n")
        emit("note.created", source: "user", ["path": .string(rel)])
        palette = false
        revealInSidebar(rel)
        open(rel)
        requestFocus(caret: ("# 未命名\n" as NSString).length)
    }

    func newFolder(in parent: String) {
        guard let v = vault else { return }
        do {
            let rel = try v.createFolder(in: parent, name: "未命名文件夹")
            if !parent.isEmpty { openFolders.insert(parent) }
            if columnVisibility == .detailOnly { columnVisibility = .all }
            renaming = "dir:" + rel
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// Opens (creating when needed) the folder's own note.
    func openFolderNote(_ folder: String) {
        guard let v = vault, !folder.isEmpty else { return }
        openFolders.insert(folder)
        if let n = v.folderNote(folder) { open(n.rel); return }
        flushSave()
        let name = (folder as NSString).lastPathComponent
        let head = "# " + name + "\n"
        v.forceWrite(folder + "/" + name + ".md", head)
        v.scan()
        emit("note.created", source: "user", ["path": .string(folder + "/" + name + ".md")])
        open(folder + "/" + name + ".md")
        requestFocus(caret: (head as NSString).length)
    }

    @discardableResult
    func renameFolder(_ folder: String, to name: String) -> Bool {
        guard let v = vault else { return false }
        if writing.contains(where: { $0.hasPrefix(folder + "/") }) { showToast("Agent 正在写入这个文件夹，稍后再改名"); return false }
        if activeRel?.hasPrefix(folder + "/") == true { flushSave() }
        let oldName = (folder as NSString).lastPathComponent
        let new: String
        do { new = try v.renameFolder(folder, to: name) } catch {
            showToast(error.localizedDescription)
            return false
        }
        guard new != folder else { return true }
        func moved(_ rel: String) -> String {
            var r = new + String(rel.dropFirst(folder.count))
            if r == new + "/" + oldName + ".md" { r = new + "/" + (new as NSString).lastPathComponent + ".md" }
            return r
        }
        for rel in pending.keys where rel.hasPrefix(folder + "/") {
            if var p = pending.removeValue(forKey: rel) { p.rel = moved(rel); pending[p.rel] = p }
        }
        for n in v.notes where n.rel.hasPrefix(new + "/") {
            let old = folder + String(n.rel.dropFirst(new.count))
            let before = old == folder + "/" + (new as NSString).lastPathComponent + ".md" ? folder + "/" + oldName + ".md" : old
            carryNoteData(from: before, to: n.rel)
        }
        openFolders = Set(openFolders.map { $0 == folder || $0.hasPrefix(folder + "/") ? new + String($0.dropFirst(folder.count)) : $0 })
        if let a = activeRel, a.hasPrefix(folder + "/") { activeRel = moved(a) }
        if let s = selection, s.hasPrefix(folder + "/") { selection = moved(s) }
        let newName = (new as NSString).lastPathComponent
        var links = 0
        if v.folderNote(new) != nil { links += relinkNotes(from: oldName, to: newName) }
        links += relinkFolder(from: folder, to: new)
        emit("folder.renamed", source: "user", ["path": .string(new), "from": .string(folder)])
        showToast(links > 0 ? "已重命名为「\(newName)」，并更新了 \(links) 处链接" : "已重命名为「\(newName)」")
        return true
    }

    /// `[[旧文件夹/笔记]]` → `[[新文件夹/笔记]]`.
    private func relinkFolder(from old: String, to new: String) -> Int {
        guard let v = vault else { return 0 }
        var total = 0
        for n in v.notes where pending[n.rel] == nil && !writing.contains(n.rel) {
            let text = n.rel == activeRel ? editorText : v.diskContent(n.rel) ?? ""
            guard text.contains("[[" + old + "/") else { continue }
            let (out, count) = Markdown.movingWikiLinks(in: text, from: old, to: new)
            guard count > 0, case .ok = v.write(n.rel, out) else { continue }
            total += count
            if n.rel == activeRel { editorText = out; editorVersion += 1 }
        }
        return total
    }

    func moveNote(_ rel: String, to folder: String) {
        guard let v = vault, v.note(rel) != nil else { return }
        if writing.contains(rel) { showToast("Agent 正在写入这篇笔记，稍后再移动"); return }
        if rel == activeRel { flushSave() }
        do {
            let new = try v.move(rel, to: folder)
            guard new != rel else { return }
            if var p = pending.removeValue(forKey: rel) { p.rel = new; pending[new] = p }
            carryNoteData(from: rel, to: new)
            if activeRel == rel { activeRel = new }
            if selection == rel { selection = new }
            revealInSidebar(new)
            // Title links still resolve; a new number in the name (笔记 2) needs relinking.
            let oldTitle = NoteRef(rel: rel).title, newTitle = NoteRef(rel: new).title
            if oldTitle != newTitle { _ = relinkNotes(from: oldTitle, to: newTitle) }
            emit("note.renamed", source: "user", ["path": .string(new), "from": .string(rel)])
            showToast("已移到「\(folder.isEmpty ? v.name : (folder as NSString).lastPathComponent)」")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func trashFolder(_ folder: String) {
        guard let v = vault, !folder.isEmpty else { return }
        if activeRel?.hasPrefix(folder + "/") == true { flushSave() }
        NSWorkspace.shared.recycle([v.url(folder)]) { _, error in
            DispatchQueue.main.async {
                if let error { self.showToast(error.localizedDescription); return }
                v.scan()
                for rel in self.pending.keys where rel.hasPrefix(folder + "/") { self.pending[rel] = nil }
                self.emit("folder.deleted", source: "user", ["path": .string(folder)])
                if self.activeRel?.hasPrefix(folder + "/") == true, let next = v.notes.first { self.open(next.rel) }
                self.showToast("已把「\((folder as NSString).lastPathComponent)」移到废纸篓")
            }
        }
    }
}
