import XCTest
@testable import NotesCore
@testable import NotesLite

final class LibraryLayoutTests: XCTestCase {
    func testNarrowWindowPreservesReadableEditorWithStoredWideColumns() {
        let widths = ColumnWidths.fitting(total: 760, sidebar: 280, list: 380)
        XCTAssertGreaterThanOrEqual(widths.sidebar, 180)
        XCTAssertGreaterThanOrEqual(widths.list, 220)
        XCTAssertGreaterThanOrEqual(760 - widths.sidebar - widths.list - 2, 320)
        let restored = ColumnWidths.fitting(total: 1180, sidebar: 246, list: 326)
        XCTAssertEqual(restored.sidebar, 246)
        XCTAssertEqual(restored.list, 326)
    }

    func testCollapsedFoldersHideDescendantsAndRevealAncestorsForDeepSelection() {
        let folders = ["阅读", "阅读/文学", "阅读/文学/摘记", "附件", "归档"]
        XCTAssertEqual(Set(FolderEntry.visible(paths: folders, expanded: []).map(\.path)), ["阅读", "附件", "归档"])
        let ancestors = FolderEntry.ancestors(of: "阅读/文学/摘记")
        XCTAssertEqual(ancestors, ["阅读", "阅读/文学"])
        let visible = FolderEntry.visible(paths: folders, expanded: ancestors)
        XCTAssertEqual(visible.first { $0.path == "阅读/文学/摘记" }?.depth, 2)
        XCTAssertTrue(visible.first { $0.path == "阅读" }?.hasChildren == true)
        XCTAssertFalse(visible.first { $0.path == "附件" }?.hasChildren == true)
    }
    func testFolderTreeKeepsChildrenWithTheirParentBesideSimilarNames() {
        let rows = FolderEntry.visible(paths: ["A", "A B", "A/子目录", "A/子目录/下一层"], expanded: ["A", "A/子目录"])
        XCTAssertEqual(rows.map(\.path), ["A", "A/子目录", "A/子目录/下一层", "A B"])
    }

    func testMixedTreeKeepsEmptyFoldersAndNotesInsideTheirOwnParent() {
        let notes = ["根.md", "A/直属.md", "A/子目录/深层.md", "A B/邻居.md"].map {
            Note(path: $0, modified: .distantPast, preview: "")
        }
        let folders = ["A", "A/子目录", "A/空目录", "A B"]
        XCTAssertEqual(LibraryTreeEntry.visible(folders: folders, notes: notes, expanded: []).map(\.id), ["folder:A", "folder:A B", "note:根.md"])
        let rows = LibraryTreeEntry.visible(folders: folders, notes: notes, expanded: ["A", "A/子目录"])
        XCTAssertEqual(rows.map(\.id), ["folder:A", "folder:A/空目录", "folder:A/子目录", "note:A/子目录/深层.md", "note:A/直属.md", "folder:A B", "note:根.md"])
    }

}
