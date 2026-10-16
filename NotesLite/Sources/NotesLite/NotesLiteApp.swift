import AppKit
import NotesCore
import SwiftUI

@main struct NotesLiteApp: App {
    @NSApplicationDelegateAdaptor(Lifecycle.self) private var lifecycle
    @State private var workspace = Workspace(defaults: .standard)
    var body: some Scene {
        Window("留白 · NotesLite", id: "notes") {
            NoteWindow(workspace: workspace)
                .frame(minWidth: 760, minHeight: 520)
                .onAppear {
                    lifecycle.workspace = workspace
                    guard workspace.root == nil else { return }
                    let args = ProcessInfo.processInfo.arguments
                    let argPath = args.firstIndex(of: "--vault").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
                    if let path = argPath ?? UserDefaults.standard.string(forKey: "library") {
                        do { try workspace.open(URL(fileURLWithPath: path)) } catch { workspace.error = error.localizedDescription }
                    }
                }
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开笔记库…") { chooseLibrary(workspace) }.keyboardShortcut("o")
                Button("新建笔记") { withAnimation(Motion.selection) { performNoteAction(workspace) { try workspace.createNote() } } }.keyboardShortcut("n").disabled(workspace.root == nil)
                Button("保存") { performNoteAction(workspace) { try workspace.save() } }.keyboardShortcut("s")
            }
            CommandMenu("笔记") {
                Button("搜索笔记") { NotificationCenter.default.post(name: .init("NotesLite.search"), object: nil) }.keyboardShortcut("k")
                Button("切换专注模式") { NotificationCenter.default.post(name: .init("NotesLite.focus"), object: nil) }.keyboardShortcut("f", modifiers: [.command, .shift])
                Toggle("Markdown 源码", isOn: $workspace.source).keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor final class Lifecycle: NSObject, NSApplicationDelegate {
    var workspace: Workspace?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace else { return .terminateNow }
        do { try workspace.save(); return .terminateNow }
        catch {
            let alert = NSAlert()
            alert.messageText = "笔记尚未保存"
            alert.informativeText = error.localizedDescription + "\n请先处理保存问题，应用将保留当前输入。"
            alert.addButton(withTitle: "返回笔记")
            alert.runModal()
            workspace.error = error.localizedDescription
            return .terminateCancel
        }
    }
}

@MainActor func performNoteAction(_ workspace: Workspace, _ work: () throws -> Void) {
    do { try work() } catch { workspace.error = error.localizedDescription }
}

@MainActor func chooseLibrary(_ workspace: Workspace) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false; panel.canChooseDirectories = true
    panel.prompt = "打开笔记库"
    if panel.runModal() == .OK, let url = panel.url {
        performNoteAction(workspace) {
            try workspace.open(url)
            UserDefaults.standard.set(url.path, forKey: "library")
        }
    }
}
