import Foundation
import TwainCore

/// Files dropped into `.twain/inbox/<collection>/` become records of that collection, then move
/// to `.twain/inbox/<collection>/已导入/`. Any app that can write a file can feed Twain this way.
extension AppModel {
    func importInbox() {
        guard let v = vault else { return }
        let root = v.root
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            let inbox = root.appendingPathComponent(".twain/inbox")
            var done: [(String, Int)] = []
            var failed: [String] = []
            for dir in (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
                guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let collection = dir.lastPathComponent
                for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                    where ["json", "jsonl", "csv"].contains(f.pathExtension.lowercased()) {
                    do {
                        let text = try String(contentsOf: f, encoding: .utf8)
                        let n = try DataStore(vault: root).add(collection, records: try DataStore.parse(text, ext: f.pathExtension))
                        let archive = dir.appendingPathComponent("已导入")
                        try? fm.createDirectory(at: archive, withIntermediateDirectories: true)
                        let stamp = Int(Date().timeIntervalSince1970)
                        try? fm.moveItem(at: f, to: archive.appendingPathComponent("\(stamp)-" + f.lastPathComponent))
                        done.append((collection, n))
                    } catch {
                        failed.append(f.lastPathComponent)
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (c, n) in done { self.dataChanged(c, added: n, source: "inbox") }
                if !done.isEmpty { self.showToast("已导入 " + done.map { "\($0.0) \($0.1) 条" }.joined(separator: "、")) }
                if !failed.isEmpty { self.showToast("没能导入：" + failed.joined(separator: "、")) }
            }
        }
    }
}
