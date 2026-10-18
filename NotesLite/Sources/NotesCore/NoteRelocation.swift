import Foundation

/// Moves one note and rewrites every reference to it, all or nothing.
enum NoteRelocation {
    struct Change { var source: URL; var destination: URL; var before: Data; var after: Data }

    /// Returns the documents whose text changed (the moved note at its new location).
    @discardableResult
    static func move(root: URL, notes: [Note], from oldURL: URL, to newURL: URL) throws -> [Change] {
        var changes: [Change] = []
        for note in notes {
            let source = root.appendingPathComponent(note.path)
            let before = try Data(contentsOf: source)
            guard let body = String(data: before, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            let destination = source == oldURL ? newURL : source
            let updated = References.updating(body, document: source, destination: destination, old: oldURL, new: newURL, root: root, notes: notes)
            if body != updated { changes.append(Change(source: source, destination: destination, before: before, after: Data(updated.utf8))) }
        }
        // Preflight every referenced document before moving anything.
        for change in changes where try Data(contentsOf: change.source) != change.before { throw NoteError.conflict }
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        var written: [Change] = []
        do {
            for change in changes {
                guard try Data(contentsOf: change.destination) == change.before else { throw NoteError.conflict }
                try change.after.write(to: change.destination, options: .atomic)
                written.append(change)
            }
        } catch {
            for change in written.reversed() { try? change.before.write(to: change.destination, options: .atomic) }
            try? FileManager.default.moveItem(at: newURL, to: oldURL)
            throw error
        }
        return changes
    }
}
