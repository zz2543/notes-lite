import Foundation

/// Every write a space homepage makes, kept in the library so it can be undone one entry at a time, even after a restart.
public final class OperationLog {
    public let root: URL
    public init(root: URL) { self.root = root.resolvingSymlinksInPath().standardizedFileURL }
}
