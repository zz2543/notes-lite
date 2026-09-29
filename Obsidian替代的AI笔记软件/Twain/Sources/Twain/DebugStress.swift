#if DEBUG
import AppKit
import QuartzCore
import SwiftUI
import TwainCore

/// `TWAIN_SCENARIO=stress[:N]`: the numbers docs/perf-plan.md is judged by, measured in one run
/// on whatever vault is open, so a build before and after a change can be compared line by line.
///
/// - opening N notes one after another (time until the first screen is laid out)
/// - hiding and showing the sidebar and the Agent panel (frames, dropped frames, longest frame)
/// - an idle stretch with a space open (the longest the main thread was unavailable)
/// - typing into and moving the caret at the end of the longest note
/// - memory at the start and the end
///
/// Every line starts with `stress `; `TWAIN_EXIT=1` quits when done.
@MainActor
enum DebugStress {
    static func log(_ s: String) { FileHandle.standardError.write(("stress " + s + "\n").data(using: .utf8)!) }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func stats(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "n=0" }
        let s = xs.sorted()
        return String(format: "n=%d median=%.1fms p90=%.1fms max=%.1fms", s.count, s[s.count / 2], s[min(s.count - 1, Int(Double(s.count) * 0.9))], s.last!)
    }

    /// Frame intervals from the display link while an animation runs.
    @MainActor final class FrameMeter: NSObject {
        private var link: CADisplayLink?
        private var stamps: [CFTimeInterval] = []
        private var frame: CFTimeInterval = 1.0 / 60

        func start(on view: NSView) {
            stamps = []
            let l = view.displayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            link = l
        }

        @objc private func tick(_ l: CADisplayLink) {
            stamps.append(l.timestamp)
            if l.targetTimestamp > l.timestamp { frame = l.targetTimestamp - l.timestamp }
        }

        /// Frames seen, frames that took longer than one and a half refreshes, and the longest.
        func stop() -> (frames: Int, hitches: Int, longest: Double) {
            link?.invalidate()
            link = nil
            let gaps = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
            return (gaps.count, gaps.filter { $0 > frame * 1.5 }.count, (gaps.max() ?? 0) * 1000)
        }
    }

    /// The longest the main thread made a 5 ms timer wait beyond its time.
    @MainActor final class StallMeter {
        private var timer: Timer?
        private var last = CACurrentMediaTime()
        private(set) var worst = 0.0
        private(set) var stalls = 0

        func start() {
            last = CACurrentMediaTime()
            let t = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.fire() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }

        private func fire() {
            let now = CACurrentMediaTime()
            let late = (now - last - 0.005) * 1000
            if late > 16 { stalls += 1 }
            worst = max(worst, late)
            last = now
        }

        func stop() { timer?.invalidate(); timer = nil }
    }

    private static var activity: NSObjectProtocol?

    static func run(_ m: AppModel, count: Int) {
        guard let v = m.vault, let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView?.frame.width ?? 0 > 600 }),
              let content = window.contentView else { log("no vault or window"); return }
        // The window runs without focus; keep App Nap from throttling timers and the display link.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "stress")
        let startMB = footprintMB()
        let readable = v.notes.filter { !$0.isHTML && AppModel.unreadableReason(v.url($0.rel)) == nil }
        let picks = Array(readable.prefix(count))
        var steps: [(@escaping () -> Void) -> Void] = []

        // 1. Opening notes.
        var opens: [Double] = []
        steps.append { next in
            var queue = picks
            @MainActor func one() {
                guard !queue.isEmpty else {
                    log("open " + stats(opens))
                    return next()
                }
                let n = queue.removeFirst()
                let t = CACurrentMediaTime()
                m.open(n.rel)
                DispatchQueue.main.async {
                    DispatchQueue.main.async {
                        if let tv = DebugScenario.textView(), let lm = tv.layoutManager, let tc = tv.textContainer {
                            lm.ensureLayout(forBoundingRect: tv.visibleRect, in: tc)
                        }
                        opens.append((CACurrentMediaTime() - t) * 1000)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { one() }
                    }
                }
            }
            one()
        }

        // 2. Panels, the way the toolbar buttons and ⌘J move them.
        func panel(_ name: String, _ toggle: @escaping () -> Void) -> (@escaping () -> Void) -> Void {
            { next in
                var round = 0
                var hide: [(Int, Int, Double)] = [], show: [(Int, Int, Double)] = []
                @MainActor func once() {
                    guard round < 8 else {
                        @MainActor func sum(_ xs: [(Int, Int, Double)]) -> String {
                            String(format: "frames=%d dropped=%d longest=%.1fms", xs.map(\.0).reduce(0, +), xs.map(\.1).reduce(0, +), xs.map(\.2).max() ?? 0)
                        }
                        log("\(name) hide " + sum(hide))
                        log("\(name) show " + sum(show))
                        return next()
                    }
                    let meter = FrameMeter()
                    meter.start(on: content)
                    toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        let r = meter.stop()
                        if round % 2 == 0 { hide.append(r) } else { show.append(r) }
                        round += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { once() }
                    }
                }
                once()
            }
        }
        steps.append(panel("sidebar") { NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil) })
        steps.append(panel("agent") { m.toggleAgent() })

        // 3. Idle with a space open, then with a note open.
        func idle(_ name: String, _ setup: @escaping () -> Void) -> (@escaping () -> Void) -> Void {
            { next in
                setup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let s = StallMeter()
                    s.start()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
                        s.stop()
                        log(String(format: "idle %@ worst=%.1fms stalls>16ms=%d", name, s.worst, s.stalls))
                        next()
                    }
                }
            }
        }
        if let space = m.spaces.first {
            steps.append(idle("space") { m.openSpace(space.id) })
        }
        steps.append(idle("note") { if let n = picks.first { m.open(n.rel) } })

        // 4. Typing and caret moves in the longest note.
        let longest = readable.filter { v.fileSize($0.rel) < 400_000 }.max { v.fileSize($0.rel) < v.fileSize($1.rel) }
        steps.append { next in
            guard let longest else { return next() }
            m.open(longest.rel)
            let len = (m.editorText as NSString).length
            m.requestFocus(caret: len / 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let tv = DebugScenario.textView() else { return next() }
                var keys: [Double] = []
                @MainActor func type(_ i: Int) {
                    guard i < 80 else {
                        log("type \(len) chars " + stats(keys))
                        return moves()
                    }
                    let t = CACurrentMediaTime()
                    if i % 15 == 14 { tv.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
                    else { tv.insertText(i % 2 == 0 ? "字" : "a", replacementRange: tv.selectedRange()) }
                    DispatchQueue.main.async { DispatchQueue.main.async {
                        keys.append((CACurrentMediaTime() - t) * 1000)
                        type(i + 1)
                    } }
                }
                @MainActor func moves() {
                    var near: [Double] = [], far: [Double] = []
                    @MainActor func move(_ at: Int, _ i: Int, into: @escaping ([Double]) -> Void, then: @escaping () -> Void) {
                        var xs: [Double] = []
                        @MainActor func step(_ k: Int) {
                            guard k < i else { into(xs); return then() }
                            let t = CACurrentMediaTime()
                            tv.doCommand(by: k % 2 == 0 ? #selector(NSResponder.moveDown(_:)) : #selector(NSResponder.moveUp(_:)))
                            DispatchQueue.main.async { DispatchQueue.main.async {
                                xs.append((CACurrentMediaTime() - t) * 1000)
                                step(k + 1)
                            } }
                        }
                        tv.setSelectedRange(NSRange(location: at, length: 0))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { step(0) }
                    }
                    move(10, 30, into: { near = $0 }) {
                        move(max(0, (tv.string as NSString).length - 10), 30, into: { far = $0 }) {
                            log("caret start " + stats(near))
                            log("caret end " + stats(far))
                            focus()
                        }
                    }
                }
                // Focus in and out with paragraph dimming on: every line's colour depends on it.
                @MainActor func focus() {
                    let wasDim = m.dim
                    m.dim = true
                    var xs: [Double] = []
                    @MainActor func step(_ k: Int) {
                        guard k < 12 else {
                            log("focus dim " + stats(xs))
                            m.dim = wasDim
                            tv.window?.makeFirstResponder(tv)
                            return finish()
                        }
                        let t = CACurrentMediaTime()
                        tv.window?.makeFirstResponder(k % 2 == 0 ? nil : tv)
                        DispatchQueue.main.async { DispatchQueue.main.async {
                            xs.append((CACurrentMediaTime() - t) * 1000)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { step(k + 1) }
                        } }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { step(0) }
                }
                @MainActor func finish() {
                    tv.undoManager?.removeAllActions()
                    m.dirty = false
                    m.reloadActiveFromDisk()
                    next()
                }
                type(0)
            }
        }

        // 5. Memory.
        steps.append { next in
            log(String(format: "memory start=%.0fMB end=%.0fMB", startMB, footprintMB()))
            next()
        }

        func runStep(_ i: Int) {
            guard i < steps.count else {
                log("done")
                if ProcessInfo.processInfo.environment["TWAIN_EXIT"] != nil { exit(0) }
                return
            }
            steps[i]({ DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { runStep(i + 1) } })
        }
        log("vault notes=\(v.notes.count) picks=\(picks.count) dim=\(m.dim)")
        runStep(0)
    }
}

extension Vault {
    func fileSize(_ rel: String) -> Int {
        (try? url(rel).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
#endif
