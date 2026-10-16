import AppKit
import NotesCore
import SwiftUI

/// Preserve SwiftUI's window delegate while intercepting only the save-before-close decision.
struct WindowCloseGuard: NSViewRepresentable {
    let workspace: Workspace
    func makeCoordinator() -> Guard { Guard(workspace) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.previous = window.delegate
            window.delegate = context.coordinator
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
    final class Guard: NSObject, NSWindowDelegate {
        let workspace: Workspace
        weak var previous: NSWindowDelegate?
        init(_ workspace: Workspace) { self.workspace = workspace }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            do { try workspace.save() }
            catch {
                workspace.error = error.localizedDescription
                return false
            }
            return previous?.windowShouldClose?(sender) ?? true
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (previous?.responds(to: selector) ?? false) }
        override func forwardingTarget(for selector: Selector!) -> Any? { previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector) }
    }
}
