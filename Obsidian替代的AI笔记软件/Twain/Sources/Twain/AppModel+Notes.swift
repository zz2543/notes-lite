import AppKit
import Observation
import TwainCore
import SwiftUI

/// Renaming, relinking and the note data that travels with a note.
extension AppModel {
    // MARK: rename

    /// Edits the open note's name in its sidebar row.
    func beginRename() {
        guard let rel = editor.activeRel, vault?.note(rel) != nil else { return }
        chrome.palette = false
        chrome.sidebarFilter = ""
        if chrome.zen { toggleZen() }
        chrome.columnVisibility = .all
        revealInSidebar(rel)
        chrome.renaming = rel
    }

    /// Renames the note's file and the `[[links]]` pointing at it. False when it didn't happen
    /// (the reason is shown), so an inline editor can stay open.
    @discardableResult
    func renameNote(_ rel: String, to title: String) -> Bool {
        guard let v = vault else { return false }
        if agents.writing.contains(rel) { showToast("Agent 正在写入这篇笔记，稍后再改名"); return false }
        if rel == editor.activeRel { flushSave() }
        let old = NoteRef(rel: rel).title
        let new: String
        do { new = try v.rename(rel, to: title) } catch {
            showToast(error.localizedDescription)
            return false
        }
        guard new != rel else { return true }
        if var p = agents.pending.removeValue(forKey: rel) { p.rel = new; agents.pending[new] = p }
        carryNoteData(from: rel, to: new)
        if editor.activeRel == rel { editor.activeRel = new }
        if chrome.selection == rel { chrome.selection = new }
        let name = NoteRef(rel: new).title
        let links = relinkNotes(from: old, to: name)
        emit("note.renamed", source: "user", ["path": .string(new), "from": .string(rel)])
        showToast(links > 0 ? "已重命名为「\(name)」，并更新了 \(links) 处链接" : "已重命名为「\(name)」")
        return true
    }

    /// Points `[[old]]` links at `new`, unless another note still answers to `old`.
    func relinkNotes(from old: String, to new: String) -> Int {
        guard let v = vault, v.note(titled: old) == nil else { return 0 }
        var total = 0
        for n in v.notes where agents.pending[n.rel] == nil && !agents.writing.contains(n.rel) {
            let text = n.rel == editor.activeRel ? editor.editorText : v.diskContent(n.rel) ?? ""
            let (out, count) = Markdown.renamingWikiLinks(in: text, from: old, to: new)
            guard count > 0, case .ok = v.write(n.rel, out) else { continue }
            total += count
            if n.rel == editor.activeRel {
                editor.editorText = out
                editor.editorVersion += 1
            }
        }
        return total
    }

    /// A note still named 未命名 takes its first heading as its name once the caret leaves
    /// that heading, or the note is closed.
    func adoptHeadingTitle(leaving: Bool = false) {
        guard let v = vault, let rel = editor.activeRel, !agents.writing.contains(rel), agents.pending[rel] == nil,
              Self.isUntitled(NoteRef(rel: rel).title),
              let heading = Markdown.titleHeading(editor.editorText), !Self.isUntitled(heading) else { return }
        let firstLine = (editor.editorText.prefix { $0 != "\n" } as Substring).utf16.count
        guard leaving || editor.editorSelection.location > firstLine else { return }
        var name = heading.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name.removeFirst() }
        guard !name.isEmpty else { return }
        let folder = (rel as NSString).deletingLastPathComponent
        renameNote(rel, to: NoteRef(rel: v.uniqueRel(title: name, folder: folder)).title)
    }

    /// Twain's own files under `.twain/` changed (plugins, data drops); extended by later features.
    func twainFilesChanged(_ paths: Set<String>) {
        if paths.contains(where: { $0.hasPrefix(".twain/annotations") }) { loadAnnotations() }
        if paths.contains(where: { $0.hasPrefix(".twain/pipelines") }) { loadPipelines() }
        if paths.contains(where: { $0.hasPrefix(".twain/plugins") }) { loadPlugins(); loadPipelines(); loadVaultConfig() }
        if paths.contains(where: { $0.hasPrefix(".twain/inbox/") && !$0.contains("/已导入") }) { importInbox() }
        if paths.contains(where: { $0.hasPrefix(".twain/data/") }) { dataVersion += 1 }
    }

    func dataChanged(_ collection: String, added: Int, source: String) {
        dataVersion += 1
        if added > 0 { emit("data.added", source: source, ["collection": .string(collection), "count": JSONValue(added)]) }
    }

    /// What Twain keeps about a note outside it (summary, annotations) follows the note when it moves.
    func carryNoteData(from old: String, to new: String) {
        guard let v = vault, old != new else { return }
        SummaryStore(vault: v.root).rename(old, to: new)
        AnnotationStore(vault: v.root).rename(old, to: new)
    }

    func selectAnnotation(_ id: String) {
        editor.selectedAnnotation = id
        guard let a = editor.annotations.first(where: { $0.id == id }), let r = Anchor.locate(a.quote, in: editor.editorText, line: a.line) else { return }
        selectEditorRange?(r)
    }

    static func isUntitled(_ title: String) -> Bool {
        title.range(of: #"^未命名( \d+)?$"#, options: .regularExpression) != nil
    }
}
