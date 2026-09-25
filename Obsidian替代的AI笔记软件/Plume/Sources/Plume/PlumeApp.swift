import AppKit
import SwiftUI

@main
struct PlumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Plume") {
            ContentView(model: model)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear { delegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建笔记") { model.newNote() }.keyboardShortcut("n")
                Button("打开库…") { model.chooseVault() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { model.openSettings(.editor) }.keyboardShortcut(",")
            }
            CommandMenu("视图") {
                Button("命令面板") { model.palette ? (model.palette = false) : model.openPalette() }.keyboardShortcut("k")
                Button(model.zen ? "退出专注模式" : "专注模式") { model.toggleZen() }.keyboardShortcut(".")
                Button("侧边栏") { model.toggleSidebar() }.keyboardShortcut("\\")
                Button("Agent 面板") { model.toggleAgent() }.keyboardShortcut("j")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Esc closes overlays, then leaves zen mode when nothing is being edited.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53, let m = self?.model else { return e }
            if m.palette { m.palette = false; return nil }
            if m.settings { m.settings = false; return nil }
            if m.zen, !(NSApp.keyWindow?.firstResponder is NSTextView) { m.zen = false; return nil }
            return e
        }
        #if DEBUG
        if let out = ProcessInfo.processInfo.environment["PLUME_SNAPSHOT"] { snapshot(to: out) }
        #endif
    }

    #if DEBUG
    /// Development aid: `PLUME_SNAPSHOT=/tmp/a.png PLUME_SCENARIO=diff Plume` renders the
    /// window offscreen to a PNG and quits, so the UI can be checked without screen access.
    private func snapshot(to path: String) {
        let scenario = ProcessInfo.processInfo.environment["PLUME_SCENARIO"] ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let m = self?.model else { return }
            m.onboardingStep = nil
            DebugScenario.apply(scenario, to: m)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let w = NSApp.windows.first(where: { $0.isVisible }), let v = w.contentView?.superview ?? w.contentView,
                      let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(2) }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
        }
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushSave()
    }
}

/// Transparent title bar with content underneath, so the sidebar runs to the top like the design.
struct WindowConfigurator: NSViewRepresentable {
    let zen: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.backgroundColor = Theme.NS.paper
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                w.standardWindowButton(b)?.superview?.animator().alphaValue = zen ? 0 : 1
            }
        }
    }
}
