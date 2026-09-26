import Foundation

/// Where the `plume` command lives and how it gets onto agents' PATH.
///
/// Plume keeps its own `bin/plume` link in Application Support, refreshed at every launch, so
/// the link survives the app being moved. Agents Plume starts get that folder on their PATH;
/// the user can also link it from `~/.local/bin` to use `plume` in any terminal.
enum PlumeTool {
    /// The real binary: inside the bundle, or next to the app binary in a `swift build` folder.
    static var binary: URL? {
        let fm = FileManager.default
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/plume")
        if fm.isExecutableFile(atPath: bundled.path) { return bundled }
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("plume-cli"),
           fm.isExecutableFile(atPath: exe.path) {
            return exe
        }
        return nil
    }

    static let binDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Plume/bin")
    static var managedLink: URL { binDir.appendingPathComponent("plume") }
    static let userLink = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/plume")

    /// Points `bin/plume` at this copy of the app. Returns the folder to put on PATH.
    @discardableResult
    static func prepare() -> URL? {
        guard let target = binary else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        if (try? fm.destinationOfSymbolicLink(atPath: managedLink.path)) != target.path {
            try? fm.removeItem(at: managedLink)
            try? fm.createSymbolicLink(at: managedLink, withDestinationURL: target)
        }
        return fm.isExecutableFile(atPath: managedLink.path) ? binDir : nil
    }

    enum Install: Equatable {
        case missing
        case installed
        /// Something else already sits at `~/.local/bin/plume`.
        case other(String)
    }

    static var installState: Install {
        let fm = FileManager.default
        if let dest = try? fm.destinationOfSymbolicLink(atPath: userLink.path) {
            return dest == managedLink.path ? .installed : .other(dest)
        }
        return fm.fileExists(atPath: userLink.path) ? .other(userLink.path) : .missing
    }

    /// Links `~/.local/bin/plume` to Plume's own link. Never replaces a file that isn't a link.
    static func install() throws {
        guard prepare() != nil else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        try fm.createDirectory(at: userLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fm.destinationOfSymbolicLink(atPath: userLink.path)) != nil {
            try fm.removeItem(at: userLink)
        } else if fm.fileExists(atPath: userLink.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.createSymbolicLink(at: userLink, withDestinationURL: managedLink)
    }

    static func uninstall() {
        if installState == .installed { try? FileManager.default.removeItem(at: userLink) }
    }
}
