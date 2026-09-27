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
                .frame(minWidth: 760, minHeight: 480)
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
                Button("重命名笔记…") { model.beginRename() }.disabled(model.activeRel == nil)
                Button("打开库…") { model.chooseVault() }.keyboardShortcut("o")
            }
            CommandGroup(after: .sidebar) {
                Button(model.agentPanel ? "隐藏 Agent 面板" : "显示 Agent 面板") { model.toggleAgent() }.keyboardShortcut("j")
                Button("命令面板") { model.palette ? (model.palette = false) : model.openPalette() }.keyboardShortcut("k")
                Button(model.zen ? "退出专注模式" : "进入专注模式") { model.toggleZen() }.keyboardShortcut(".")
                Divider()
                Toggle("打字机滚动", isOn: $model.typewriter)
                Toggle("段落聚焦", isOn: $model.dim)
                Toggle("Tab 行内续写", isOn: $model.ghostOn)
                Toggle("伴写（页边提问与思路）", isOn: Binding(get: { model.companionOn }, set: { if $0 != model.companionOn { model.toggleCompanion() } }))
                Picker("正文字体", selection: $model.font) {
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
                Button("审阅待定改动") { model.reviewNext() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.pending.isEmpty)
                Button("停止运行") { model.sessions.filter { $0.running && $0.source == .app }.forEach(model.stopAgent) }
                    .disabled(!model.sessions.contains { $0.running && $0.source == .app })
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

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
            if m.palette { m.palette = false; return nil }
            if m.zen, !(NSApp.keyWindow?.firstResponder is NSTextView) { m.toggleZen(); return nil }
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
            m.onboardingStep = nil
            TwainTextView.forceCaret = true
            DebugScenario.apply(scenario, to: m)
            let delay = Double(ProcessInfo.processInfo.environment["TWAIN_SNAPSHOT_DELAY"] ?? "") ?? 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                DebugScenario.textView()?.updateCaret(animated: false)
                guard let w = NSApp.orderedWindows.first(where: { $0.isVisible }) ?? NSApp.windows.first(where: { $0.isVisible }), let v = w.contentView?.superview ?? w.contentView,
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

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushSave()
        model?.server?.stop()
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
