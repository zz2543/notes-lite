import Foundation

/// Keeps one vault's listing and index current off the main thread. A refresh walks the folder
/// once, re-reads only the notes whose date changed, and hands every caller that asked while it
/// was pending the same result: a burst of file events or of agent queries costs one walk.
///
/// Thread safety: `working` and `listing` are only touched on `queue`; `waiters` and
/// `scheduled` only under `lock`. Results are values, safe to read anywhere.
public final class VaultService: @unchecked Sendable {
    public typealias Done = @Sendable (VaultListing, VaultIndex) -> Void

    public let root: URL
    private let queue = DispatchQueue(label: "twain.vault", qos: .userInitiated)
    private var working: VaultIndex
    private var seed: VaultListing?
    private let lock = NSLock()
    private var waiters: [Done] = []
    private var scheduled = false

    /// `listing`, when given, is a walk just made (the sidebar's), used for the first refresh.
    public init(root: URL, listing: VaultListing? = nil) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        working = VaultIndex(root: self.root)
        seed = listing
    }

    /// Walks the folder and brings the index up to date, then calls `done` on the service's
    /// queue. Calls made before that walk starts share it.
    public func refresh(_ done: @escaping Done) {
        lock.lock()
        waiters.append(done)
        let start = !scheduled
        scheduled = true
        lock.unlock()
        guard start else { return }
        queue.async { self.run() }
    }

    private func run() {
        lock.lock()
        let now = waiters
        waiters = []
        scheduled = false
        lock.unlock()
        let listing = seed ?? VaultListing.walk(root)
        seed = nil
        working.apply(listing)
        let copy = working
        for w in now { w(listing, copy) }
    }
}
