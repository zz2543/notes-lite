import Foundation

/// One-time moves from the app's old name, Plume. Delete once no one upgrades from a Plume build.
enum LegacyPlume {
    /// Preferences lived under the old bundle id, or under the bare executable name in `swift run`.
    static func migrateDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromPlume") else { return }
        d.set(true, forKey: "migratedFromPlume")
        let old = Bundle.main.bundleIdentifier == nil ? "Plume" : "app.plume.notes"
        guard let values = d.persistentDomain(forName: old) else { return }
        for (key, value) in values where d.object(forKey: key) == nil { d.set(value, forKey: key) }
    }

    /// Swaps a `~/.local/bin/plume` the user installed for `twain`, and drops Plume's support
    /// folder, which only ever held the command link and the socket.
    static func migrateTool() {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let oldSupport = home.appendingPathComponent("Library/Application Support/Plume")
        let oldUserLink = home.appendingPathComponent(".local/bin/plume")
        if (try? fm.destinationOfSymbolicLink(atPath: oldUserLink.path)) == oldSupport.appendingPathComponent("bin/plume").path {
            try? fm.removeItem(at: oldUserLink)
            if TwainTool.installState == .missing { try? TwainTool.install() }
        }
        if let items = try? fm.contentsOfDirectory(atPath: oldSupport.path),
           Set(items).isSubset(of: ["bin", "run", ".DS_Store"]) {
            try? fm.removeItem(at: oldSupport)
        }
    }

    /// Moves a vault's `.plume/` (commands, automations, proposals) to `.twain/`. The files Plume
    /// wrote there and in AGENTS.md tell agents to run `plume`, so those are renamed too.
    static func migrateVault(_ root: URL) {
        let fm = FileManager.default
        let old = root.appendingPathComponent(".plume"), new = root.appendingPathComponent(".twain")
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path),
              (try? fm.moveItem(at: old, to: new)) != nil else { return }
        let written = ["commands", "automations"].flatMap {
            (try? fm.contentsOfDirectory(at: new.appendingPathComponent($0), includingPropertiesForKeys: nil)) ?? []
        }
        for u in [root.appendingPathComponent("AGENTS.md")] + written
        where u.pathExtension == "md" || u.lastPathComponent.hasSuffix(".md.example") {
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let renamed = rename(text)
            if renamed != text { try? renamed.write(to: u, atomically: true, encoding: .utf8) }
        }
    }

    /// `plume` becomes `twain`; the product name in Chinese prose becomes 共笔, without the
    /// spaces that separated it from the surrounding Chinese.
    static func rename(_ text: String) -> String {
        text.replacingOccurrences(of: #"\bplume\b"#, with: "twain", options: .regularExpression)
            .replacingOccurrences(of: #"\bPlume\b"#, with: "共笔", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\p{Han}) +(?=共笔)|(?<=共笔) +(?=\p{Han})"#, with: "", options: .regularExpression)
    }
}
