import XCTest
@testable import TwainCore

private func makeVault(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID())")
    for (rel, text) in files {
        let u = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.standardizedFileURL.resolvingSymlinksInPath()
}

final class VaultListingTests: XCTestCase {
    func testWalkSortsLikeFinderAndSkipsHidden() throws {
        let root = try makeVault(["笔记 10.md": "", "笔记 2.md": "", "a/b.md": "", "a/pic.PNG": "", ".twain/x.md": "", "node_modules/y.md": "", "page.html": ""])
        defer { try? FileManager.default.removeItem(at: root) }
        let l = VaultListing.walk(root)
        let rels = l.notes.map(\.rel)
        XCTAssertEqual(Set(rels), ["a/b.md", "page.html", "笔记 2.md", "笔记 10.md"])
        // Numbers by value, as Finder does (where Chinese sorts against Latin depends on the locale).
        XCTAssertLessThan(rels.firstIndex(of: "笔记 2.md")!, rels.firstIndex(of: "笔记 10.md")!)
        XCTAssertEqual(l.folders, ["a"])
        XCTAssertEqual(l.attachments["pic.png"], ["a/pic.PNG"])
        XCTAssertNotNil(l.notes.first?.stamp)
    }

    func testEditsKeepOrderAndParents() {
        var l = VaultListing()
        l.insertNote("b.md")
        l.insertNote("x/y/a.md")
        l.insertNote("a.md")
        XCTAssertEqual(l.notes.map(\.rel), ["a.md", "b.md", "x/y/a.md"])
        XCTAssertEqual(l.folders, ["x", "x/y"])
        l.moveFolder("x", to: "z")
        XCTAssertEqual(l.notes.map(\.rel), ["a.md", "b.md", "z/y/a.md"])
        XCTAssertEqual(l.folders, ["z", "z/y"])
        l.removeNote("a.md")
        XCTAssertEqual(l.notes.map(\.rel), ["b.md", "z/y/a.md"])
    }
}

@MainActor
final class VaultTests: XCTestCase {
    func testWriteRefusesToOverwriteSomeoneElsesEdit() throws {
        let root = try makeVault(["a.md": "one\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let v = Vault(root: root)
        XCTAssertEqual(v.read("a.md"), "one\n")
        XCTAssertEqual(v.write("a.md", "mine\n"), .ok)
        try "theirs\n".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(v.write("a.md", "mine again\n"), .conflict("theirs\n"))
        XCTAssertEqual(v.diskContent("a.md"), "theirs\n")
    }

    func testOwnChangesShowWithoutAWalk() throws {
        let root = try makeVault(["a.md": ""])
        defer { try? FileManager.default.removeItem(at: root) }
        let v = Vault(root: root)
        let rel = v.create(title: "新", folder: "文件夹", content: "# 新\n")
        XCTAssertEqual(rel, "文件夹/新.md")
        XCTAssertNotNil(v.note(rel))
        XCTAssertEqual(v.tree["文件夹"]?.notes.map(\.rel), [rel])
        XCTAssertEqual(v.tree[""]?.folders, ["文件夹"])

        let renamed = try v.rename(rel, to: "旧")
        XCTAssertEqual(renamed, "文件夹/旧.md")
        XCTAssertNil(v.note(rel))
        XCTAssertEqual(v.knownContent(renamed), "# 新\n")

        let moved = try v.move(renamed, to: "")
        XCTAssertEqual(moved, "旧.md")
        XCTAssertNotNil(v.note(moved))
        XCTAssertThrowsError(try v.rename(moved, to: "a")) { XCTAssertEqual($0 as? Vault.RenameError, .taken("a")) }
        XCTAssertThrowsError(try v.rename(moved, to: "x/y")) { XCTAssertEqual($0 as? Vault.RenameError, .invalid) }
    }

    func testRenameFolderCarriesItsFolderNote() throws {
        let root = try makeVault(["项目/项目.md": "# 项目\n", "项目/计划.md": "x"])
        defer { try? FileManager.default.removeItem(at: root) }
        let v = Vault(root: root)
        v.read("项目/计划.md")
        XCTAssertNotNil(v.folderNote("项目"))
        let new = try v.renameFolder("项目", to: "工程")
        XCTAssertEqual(new, "工程")
        XCTAssertNotNil(v.note("工程/工程.md"))
        XCTAssertNotNil(v.note("工程/计划.md"))
        XCTAssertNil(v.note("项目/计划.md"))
        XCTAssertEqual(v.knownContent("工程/计划.md"), "x")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("工程/工程.md").path))
    }

    func testRefreshDeliversTheIndexOnTheMainThread() throws {
        let root = try makeVault(["a.md": "# A\n- [ ] 任务 #标签\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let v = Vault(root: root)
        let done = expectation(description: "walk")
        v.refresh { index in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(index.tasks().map(\.task.text), ["任务 #标签"])
            XCTAssertEqual(index.tags, ["标签"])
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}

final class VaultServiceTests: XCTestCase {
    func testCallsWaitingTogetherShareOneWalk() throws {
        let root = try makeVault(["a.md": "x"])
        defer { try? FileManager.default.removeItem(at: root) }
        let service = VaultService(root: root)
        let all = expectation(description: "all")
        all.expectedFulfillmentCount = 3
        final class Seen: @unchecked Sendable { let lock = NSLock(); var generations: [Int] = [] }
        let seen = Seen()
        for _ in 0..<3 {
            service.refresh { _, index in
                seen.lock.lock(); seen.generations.append(index.generation); seen.lock.unlock()
                all.fulfill()
            }
        }
        wait(for: [all], timeout: 5)
        XCTAssertEqual(seen.generations.count, 3)
        XCTAssertTrue(seen.generations.allSatisfy { $0 >= 1 })
    }

    func testUnchangedNotesAreNotReread() throws {
        let root = try makeVault(["a.md": "x", "b.md": "y"])
        defer { try? FileManager.default.removeItem(at: root) }
        var index = VaultIndex(root: root)
        index.refresh()
        let g = index.generation
        index.refresh()
        XCTAssertEqual(index.generation, g, "nothing changed on disk")
        try "z".write(to: root.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)
        index.refresh()
        XCTAssertEqual(index.generation, g + 1)
        XCTAssertEqual(index.paths, ["a.md", "b.md", "c.md"])
    }
}

final class VaultSnapshotTests: XCTestCase {
    func testChangesListsEditedAndNewNotes() throws {
        let root = try makeVault(["a.md": "one", "b.md": "two"])
        defer { try? FileManager.default.removeItem(at: root) }
        let snap = VaultSnapshot.take(root: root, rels: ["a.md", "b.md"])
        Thread.sleep(forTimeInterval: 0.01)
        try "one!".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "new".write(to: root.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)
        let changes = snap.changes()
        XCTAssertEqual(changes.map(\.rel), ["a.md", "c.md"])
        XCTAssertEqual(changes.first?.before, "one")
        XCTAssertEqual(changes.first?.after, "one!")
        XCTAssertNil(changes.last?.before)
    }
}
