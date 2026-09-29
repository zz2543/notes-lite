import AppKit
import TwainCore
import SwiftUI

@main
struct TwainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("共笔", id: "main") {
            MainWindow(model: model)
                // Wide enough for the sidebar, the page and the Agent inspector at their minimum
                // widths. Narrower, the split view cannot fit its columns and re-solves them on
                // every layout pass until AppKit aborts ("more Update Constraints passes than views").
                .frame(minWidth: MainWindow.minWidth, minHeight: 480)
                #if DEBUG
                .background(SnapshotWindowHider())
                #endif
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("新建笔记") { model.newNote() }.keyboardShortcut("n")
                Button("重命名笔记…") { model.beginRename() }.disabled(model.editor.activeRel == nil)
                Button("打开库…") { model.chooseVault() }.keyboardShortcut("o")
            }
            CommandGroup(after: .sidebar) {
                Button(model.chrome.agentPanel ? "隐藏 Agent 面板" : "显示 Agent 面板") { model.toggleAgent() }.keyboardShortcut("j")
                Button("命令面板") { model.chrome.palette ? (model.chrome.palette = false) : model.openPalette() }.keyboardShortcut("k")
                Button(model.chrome.zen ? "退出专注模式" : "进入专注模式") { model.toggleZen() }.keyboardShortcut(".")
                Divider()
                Toggle("打字机滚动", isOn: Bindable(model.prefs).typewriter)
                Toggle("段落聚焦", isOn: Bindable(model.prefs).dim)
                Toggle("Tab 行内续写", isOn: Bindable(model.prefs).ghostOn)
                Toggle("伴写（页边提问与思路）", isOn: Binding(get: { model.prefs.companionOn }, set: { if $0 != model.prefs.companionOn { model.toggleCompanion() } }))
                Picker("正文字体", selection: Bindable(model.prefs).font) {
                    ForEach(EditorFont.allCases) { Text($0.cardLabel).tag($0) }
                }
                Divider()
            }
            CommandMenu("Agent") {
                ForEach(model.userCommands, id: \.key) { c in
                    Button(c.title) {
                        do { try model.runUserCommand(c, input: nil) } catch let e as RPCError { model.showToast(e.message) } catch {}
                    }
                }
                if !model.userCommands.isEmpty { Divider() }
                Button("问库…") { model.newDesk() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Button("AI 审阅当前笔记") { model.startAIReview() }.disabled(model.editor.activeRel == nil)
                Divider()
                Button("审阅待定改动") { model.reviewNext() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.agents.pending.isEmpty)
                Button("停止运行") { model.agents.sessions.filter { $0.running && $0.source == .app }.forEach(model.stopAgent) }
                    .disabled(!model.agents.sessions.contains { $0.running && $0.source == .app })
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel? {
        didSet { if !snapshotMode { model?.startServer() } }
    }
    private var monitor: Any?

    private var snapshotMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TWAIN_SNAPSHOT"] != nil
        #else
        false
        #endif
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if snapshotMode { NSApp.setActivationPolicy(.accessory) }
        #if DEBUG
        // Test runs that expect to crash: print why and exit quietly instead of raising the
        // system's crash dialog on the user's screen.
        if ProcessInfo.processInfo.environment["TWAIN_QUIET_CRASH"] != nil {
            NSSetUncaughtExceptionHandler { e in
                FileHandle.standardError.write("CRASH \(e.name.rawValue): \(e.reason ?? "")\n".data(using: .utf8)!)
                _exit(70)
            }
            for sig in [SIGABRT, SIGTRAP, SIGSEGV, SIGBUS] {
                signal(sig) { s in
                    let msg = "CRASH signal \(s)\n"
                    _ = msg.withCString { write(2, $0, strlen($0)) }
                    _exit(71)
                }
            }
        }
        switch ProcessInfo.processInfo.environment["TWAIN_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if snapshotMode {
            // The window is only a bitmap source; keep it invisible and noninteractive.
            for w in NSApp.windows { w.alphaValue = 0; w.ignoresMouseEvents = true }
        } else {
            NSApp.setActivationPolicy(.regular)
            #if DEBUG
            // Automated visual checks open the window without taking the keyboard from the user.
            // SwiftUI still activates the app when the window appears, so hand focus straight
            // back and keystrokes meant for other apps never land in this window.
            if ProcessInfo.processInfo.environment["TWAIN_BACKGROUND"] != nil {
                NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                    NSApp.deactivate()
                }
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            #else
            NSApp.activate(ignoringOtherApps: true)
            #endif
        }
        // Esc closes overlays, then leaves zen mode when nothing is being edited.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53, let m = self?.model else { return e }
            if m.chrome.palette { m.chrome.palette = false; return nil }
            if m.chrome.zen, !(NSApp.keyWindow?.firstResponder is NSTextView) { m.toggleZen(); return nil }
            return e
        }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let out = env["TWAIN_SNAPSHOT"] {
            snapshot(to: out)
        } else if let scenario = env["TWAIN_SCENARIO"] {
            // Same scenarios in a live window, for checks that need real glass rendering.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let m = self?.model else { return }
                DebugScenario.apply(scenario, to: m)
            }
        }
        #endif
    }

    #if DEBUG
    /// Development aid: `TWAIN_SNAPSHOT=/tmp/a.png TWAIN_SCENARIO=diff Twain` renders the
    /// window offscreen to a PNG and quits, so the UI can be checked without screen access.
    private func snapshot(to path: String) {
        let scenario = ProcessInfo.processInfo.environment["TWAIN_SCENARIO"] ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let m = self?.model else { return }
            m.chrome.onboardingStep = nil
            TwainTextView.forceCaret = true
            DebugScenario.apply(scenario, to: m)
            let delay = Double(ProcessInfo.processInfo.environment["TWAIN_SNAPSHOT_DELAY"] ?? "") ?? 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                DebugScenario.textView()?.updateCaret(animated: false)
                // TWAIN_SNAPSHOT_WINDOW=settings captures the Settings window instead of the main one.
                let wantSettings = ProcessInfo.processInfo.environment["TWAIN_SNAPSHOT_WINDOW"] == "settings"
                let settings = NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }
                // TWAIN_SNAPSHOT_SCREEN=1: the real window as the window server shows it (glass
                // included, which cacheDisplay leaves out), taken by `screencapture -l`.
                if ProcessInfo.processInfo.environment["TWAIN_SNAPSHOT_SCREEN"] != nil,
                   let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView?.frame.width ?? 0 > 600 }) {
                    // Shown for the capture only; it may sit behind other windows, -l still gets it.
                    w.alphaValue = 1
                    CATransaction.flush()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    task.arguments = ["-x", "-o", "-l\(w.windowNumber)", path]
                    try? task.run()
                    task.waitUntilExit()
                    exit(0)
                }
                guard let w = wantSettings ? settings : NSApp.orderedWindows.first(where: { $0.isVisible }) ?? NSApp.windows.first(where: { $0.isVisible }), let v = w.contentView?.superview ?? w.contentView,
                      let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(2) }
                v.cacheDisplay(in: v.bounds, to: rep)
                // cacheDisplay skips CALayer sublayers; paint the caret so its placement shows.
                if let tv = DebugScenario.textView(), tv.caret.opacity > 0, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                    let r = tv.convert(tv.caret.frame, to: v)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = ctx
                    let flipped = v.isFlipped ? r : CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
                    NSColor.controlAccentColor.setFill()
                    NSBezierPath(roundedRect: flipped, xRadius: 1.25, yRadius: 1.25).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
        }
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// twain://open?note=…&line=…, twain://new?title=…&folder=…&content=…, twain://ask?q=…,
    /// twain://run?name=…&input=… — links other apps (and notes) can use.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { model?.handleURL(u) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushSave()
        model?.server?.stop()
        model?.http.stop()
    }
}

#if DEBUG
/// Hides the scene as soon as SwiftUI attaches it to a window, before the delayed capture.
private struct SnapshotWindowHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SnapshotHostView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class SnapshotHostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard ProcessInfo.processInfo.environment["TWAIN_SNAPSHOT"] != nil else { return }
            window?.alphaValue = 0
            window?.ignoresMouseEvents = true
        }
    }
}
#endif
