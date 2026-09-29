import SwiftUI

/// Shows `content` with a value computed off the main thread, and computes it again when `key`
/// changes. The previous value stays on screen while the next one loads, so nothing flashes
/// empty, and the change animates. For cards that read files (data collections, the disk):
/// the view's body never waits on the disk.
struct Loaded<Key: Equatable & Sendable, Value: Sendable, Content: View>: View {
    let key: Key
    let load: @Sendable (Key) -> Value
    @ViewBuilder var content: (Value?) -> Content
    @State private var value: Value?

    var body: some View {
        content(value)
            .task(id: key) {
                let k = key, f = load
                let v = await Task.detached(priority: .userInitiated) { f(k) }.value
                guard !Task.isCancelled else { return }
                if value == nil {
                    value = v
                } else {
                    withAnimation(Motion.content) { value = v }
                }
            }
    }
}
