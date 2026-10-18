import AppKit
import CryptoKit
import NotesCore
import SwiftUI
import WebKit

/// Bundled style kit, `lb` shim and widgets injected into every space homepage.
enum SpaceAssets {
    static let directory: URL? = {
        let name = "NotesLite_NotesLite.bundle"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent(),
                     Bundle(for: SpacePageController.self).bundleURL.deletingLastPathComponent()]
        for case let base? in bases {
            for sub in ["Space", "Contents/Resources/Space"] {
                let u = base.appendingPathComponent(name).appendingPathComponent(sub)
                if FileManager.default.fileExists(atPath: u.appendingPathComponent("lb.js").path) { return u }
            }
        }
        return nil
    }()

    static func text(_ file: String) -> String {
        directory.flatMap { try? String(contentsOf: $0.appendingPathComponent(file), encoding: .utf8) } ?? ""
    }

    /// The page as WebKit loads it: the injected kit first, so errors in the page's own scripts are already caught.
    static func document(for space: Space) -> String {
        """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(SpaceText.escape(space.name))</title>
        <style>\(text("style.css"))</style>
        <script>\(text("lb.js"))</script>
        <script>\(text("components.js"))</script>
        </head><body class="lb-page">
        \(space.html)
        </body></html>
        """
    }
}

enum SpaceText {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// A page error, ready to hand to an agent.
struct SpacePageError: Equatable, Identifiable {
    let id = UUID()
    var message: String
    var location: String
    var stack: String
    static func == (a: Self, b: Self) -> Bool { a.message == b.message && a.location == b.location && a.stack == b.stack }

    func report(space: Space, file: URL) -> String {
        var lines = ["留白空间「\(space.name)」的主页出错了。", "", "空间文件：\(file.path)", "错误：\(message)"]
        if !location.isEmpty { lines.append("位置：\(location)") }
        if !stack.isEmpty { lines += ["堆栈：", stack] }
        lines += ["", "请阅读同目录下的「编写说明.md」，修复空间文件里的问题。"]
        return lines.joined(separator: "\n")
    }
}

/// Live state of the homepage being shown: errors, the write notice and its web view.
@MainActor @Observable final class SpacePageState {
    var errors: [SpacePageError] = []
    /// Records and notes the homepage changed recently; drives 「主页刚修改了 N 条记录 · 查看」.
    var recentChanges = 0
    var noticeVersion = 0
    @ObservationIgnored weak var controller: SpacePageController?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    func record(_ error: SpacePageError) {
        guard !errors.contains(error) else { return }
        errors = Array((errors + [error]).suffix(5))
    }

    func wrote(_ count: Int) {
        guard count > 0 else { return }
        recentChanges += count; noticeVersion += 1
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.panel) { self?.recentChanges = 0 }
        }
    }

    func reset() { errors = []; recentChanges = 0; noticeTask?.cancel() }
}

/// Owns one space homepage's web view and its bridge to `SpaceAPI`.
@MainActor final class SpacePageController: NSObject, WKScriptMessageHandlerWithReply, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let root: URL
    private(set) var space: Space
    let api: SpaceAPI
    let state: SpacePageState
    let webView: WKWebView
    private var loadedHTML: String?

    init(root: URL, space: Space, log: OperationLog, state: SpacePageState) {
        self.root = root; self.space = space; self.state = state
        api = SpaceAPI(root: root, space: space.name, log: log)
        let configuration = WKWebViewConfiguration()
        // Network stays open (unlike the math sandbox); storage persists per space and only holds UI preferences.
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeIdentifier(root: root, space: space.name))
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        let content = configuration.userContentController
        content.addScriptMessageHandler(WeakReplyHandler(self), contentWorld: .page, name: "lb")
        content.add(WeakHandler(self), name: "lbError")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        state.controller = self
        load()
    }

    /// Stable per library and space, so a space keeps its preferences and never sees another's.
    static func storeIdentifier(root: URL, space: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data((root.path + "\u{0}" + space).utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30; bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func origin(root: URL, space: String) -> URL {
        URL(string: "https://space-\(storeIdentifier(root: root, space: space).uuidString.lowercased()).noteslite.invalid/")!
    }

    func load() {
        loadedHTML = space.html
        state.errors = []
        webView.loadHTMLString(SpaceAssets.document(for: space), baseURL: Self.origin(root: root, space: space.name))
    }

    /// The space file changed on disk (an agent rewrote it): show the new page without review.
    func update(_ space: Space) {
        self.space = space
        if space.html != loadedHTML { load() }
    }

    /// Library changes inside the scope reach the page's `lb.on("change")` listeners and the widgets.
    func notify(_ paths: [String]) {
        let relevant = paths.filter { space.scope.contains($0) && !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
        guard !relevant.isEmpty, let json = try? JSONSerialization.data(withJSONObject: relevant), let list = String(data: json, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__lbChange && window.__lbChange(\(list))")
    }

    // MARK: bridge

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let request = try? JSONSerialization.data(withJSONObject: body) else {
            replyHandler(["ok": false, "error": ["code": "invalid", "message": "请求格式不正确。"]], nil); return
        }
        let reply = api.handle(request)
        state.wrote(api.lastChanges)
        replyHandler(try? JSONSerialization.jsonObject(with: reply, options: [.fragmentsAllowed]), nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let source = (body["source"] as? String) ?? ""
        let line = (body["line"] as? Int) ?? 0
        let column = (body["column"] as? Int) ?? 0
        let location = line > 0 ? (source.hasPrefix("https://space-") || source.isEmpty ? "空间文件" : source) + " 第 \(line) 行" + (column > 0 ? "，第 \(column) 列" : "") : ""
        state.record(SpacePageError(message: (body["message"] as? String) ?? "未知错误", location: location, stack: (body["stack"] as? String) ?? ""))
    }

    // MARK: navigation

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // Links leave for the user's browser; the homepage itself never navigates away.
        if action.navigationType == .linkActivated, let url = action.request.url, action.targetFrame?.isMainFrame != false {
            if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadFailed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        state.record(SpacePageError(message: "页面进程意外退出，已重新载入。", location: "", stack: ""))
        load()
    }

    private func loadFailed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        state.record(SpacePageError(message: "页面加载失败：" + error.localizedDescription, location: "", stack: ""))
    }
}

/// WebKit retains message handlers strongly; these break the cycle with the controller.
private final class WeakReplyHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var target: SpacePageController?
    init(_ target: SpacePageController) { self.target = target }
    @MainActor func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage, replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let target else { replyHandler(nil, "页面已关闭"); return }
        target.userContentController(c, didReceive: m, replyHandler: replyHandler)
    }
}
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: SpacePageController?
    init(_ target: SpacePageController) { self.target = target }
    @MainActor func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

struct SpacePageView: NSViewRepresentable {
    let controller: SpacePageController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// The right column in space mode: the homepage plus its error bar and write notice.
struct SpaceHome: View {
    let space: Space
    let root: URL
    @Bindable var store: SpaceStore
    let showLog: () -> Void

    var body: some View {
        let state = store.pageState
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let error = state.errors.last {
                    SpaceErrorBar(error: error, count: state.errors.count,
                                  copy: { store.copy(error.report(space: space, file: SpaceLibrary(root: root).url(of: space.name))) },
                                  dismiss: { withAnimation(Motion.panel) { state.errors = [] } })
                        .transition(Motion.banner)
                }
                if state.recentChanges > 0 {
                    SpaceWriteNotice(count: state.recentChanges, version: state.noticeVersion, show: showLog)
                        .transition(Motion.banner)
                }
            }
            .padding(.horizontal, 18).padding(.top, state.errors.isEmpty && state.recentChanges == 0 ? 0 : 10)
            .animation(Motion.panel, value: state.errors)
            .animation(Motion.panel, value: state.recentChanges > 0)
            if let controller = store.controller(for: space, root: root) {
                SpacePageView(controller: controller)
            }
        }
    }
}

struct SpaceErrorBar: View {
    let error: SpacePageError
    let count: Int
    let copy: () -> Void
    let dismiss: () -> Void
    @State private var copied = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("主页出错了" + (count > 1 ? "（\(count) 个错误）" : "")).font(.system(size: 11.5, weight: .semibold))
                Text(error.message + (error.location.isEmpty ? "" : " · " + error.location))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button {
                copy()
                withAnimation(Motion.feedback) { copied = true }
                Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation(Motion.feedback) { copied = false } }
            } label: {
                Label(copied ? "已复制" : "复制错误给 agent", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace)).font(.system(size: 11, weight: .medium))
            }.buttonStyle(SoftButton())
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                .buttonStyle(SoftButton()).foregroundStyle(.secondary).accessibilityLabel("关闭错误提示")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.22)))
    }
}

struct SpaceWriteNotice: View {
    let count: Int
    let version: Int
    let show: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.and.list.clipboard").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("主页刚修改了 ").font(.system(size: 11.5)) + Text("\(count)").font(.system(size: 11.5, weight: .semibold)).monospacedDigit() + Text(" 条记录").font(.system(size: 11.5))
            Button("查看", action: show).buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.accentColor)
            Spacer(minLength: 0)
        }
        .contentTransition(.numericText(value: Double(count)))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .scaleEffect(1)
        .animation(Motion.feedback, value: version)
        .accessibilityElement(children: .combine)
    }
}

/// Every write the homepages made, newest first, each undoable on its own.
struct OperationLogSheet: View {
    let log: OperationLog
    let space: String?
    let close: () -> Void
    @State private var entries: [OperationLog.Entry] = []
    @State private var onlyThisSpace = true
    @State private var failure: (id: UUID, message: String)?

    private var shown: [OperationLog.Entry] { entries.filter { !onlyThisSpace || space == nil || $0.space == space } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("操作记录").font(.headline)
                    Text("空间主页对笔记做出的每次写入，保留 30 天，可以逐条撤销。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let space { Toggle("只看「\(space)」", isOn: $onlyThisSpace.animation(Motion.selection)).toggleStyle(.checkbox).font(.caption) }
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
            Divider().opacity(0.5)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(shown) { entry in
                        OperationRow(entry: entry, failure: failure?.id == entry.id ? failure?.message : nil) { undo(entry) }
                            .transition(Motion.row)
                    }
                    if shown.isEmpty {
                        Text("还没有记录。").font(.caption).foregroundStyle(.tertiary).padding(40)
                    }
                }.padding(10).animation(Motion.selection, value: shown)
            }.frame(height: 380)
            Divider().opacity(0.5)
            HStack { Spacer(); Button("完成", action: close).keyboardShortcut(.defaultAction) }.padding(14)
        }
        .frame(width: 560)
        .onAppear { entries = log.entries() }
    }

    private func undo(_ entry: OperationLog.Entry) {
        do {
            try log.undo(entry.id)
            failure = nil
            withAnimation(Motion.selection) { entries = log.entries() }
        } catch {
            withAnimation(Motion.feedback) { failure = (entry.id, (error as? SpaceAPIError)?.message ?? error.localizedDescription) }
        }
    }
}

private struct OperationRow: View {
    let entry: OperationLog.Entry
    let failure: String?
    let undo: () -> Void
    @State private var hovered = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.summary).font(.system(size: 12)).lineLimit(2)
                    .strikethrough(entry.undone, color: .secondary).foregroundStyle(entry.undone ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(entry.date, format: .dateTime.month().day().hour().minute())
                    Text("·"); Text(entry.space)
                    if entry.undone { Text("· 已撤销") }
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
                if let failure { Text(failure).font(.system(size: 10.5)).foregroundStyle(.orange).transition(.opacity.combined(with: .offset(y: -3))) }
            }
            Spacer(minLength: 8)
            if !entry.undone {
                Button("撤销", action: undo).buttonStyle(SoftButton()).font(.system(size: 11, weight: .medium))
                    .opacity(hovered ? 1 : 0.55)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.primary.opacity(hovered ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 9))
        .onHover { hovered = $0 }
        .animation(Motion.hover, value: hovered)
    }

    private var icon: String {
        switch entry.kind {
        case .recordAppend: "plus.circle"
        case .recordUpdate: "pencil.circle"
        case .recordRemove: "minus.circle"
        case .noteCreate: "doc.badge.plus"
        case .noteWrite: "doc.text"
        case .noteRename: "character.cursor.ibeam"
        case .noteMove: "folder"
        case .noteTrash: "trash"
        case .pageWrite: "macwindow"
        }
    }
}
