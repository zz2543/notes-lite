import SwiftUI
import TwainCore
import WebKit

/// Pages Twain shows (HTML notes, plugin widgets) never reach the network: local files only.
enum WebSandbox {
    private static var rules: WKContentRuleList?
    private static var waiting: [(WKContentRuleList?) -> Void] = []
    private static var compiling = false

    static let blockNetwork = """
    [{"trigger": {"url-filter": "^https?://"}, "action": {"type": "block"}},
     {"trigger": {"url-filter": "^wss?://"}, "action": {"type": "block"}},
     {"trigger": {"url-filter": "^ftp://"}, "action": {"type": "block"}}]
    """

    /// The compiled rule list, compiled once per launch.
    static func ruleList(_ done: @escaping (WKContentRuleList?) -> Void) {
        if let rules { done(rules); return }
        waiting.append(done)
        guard !compiling else { return }
        compiling = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "twain.block-network", encodedContentRuleList: blockNetwork) { list, _ in
            DispatchQueue.main.async {
                rules = list
                compiling = false
                for w in waiting { w(list) }
                waiting = []
            }
        }
    }

    static func configuration() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .nonPersistent()
        c.preferences.isElementFullscreenEnabled = true
        return c
    }
}

/// An HTML note, rendered. Links to the web open in the browser; everything else stays local.
struct HTMLNoteView: NSViewRepresentable {
    let url: URL
    let root: URL
    /// Changes when the file does, to reload.
    let version: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WebSandbox.configuration())
        w.navigationDelegate = context.coordinator
        w.setValue(false, forKey: "drawsBackground")
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        let c = context.coordinator
        guard c.loaded != url || c.version != version else { return }
        c.loaded = url
        c.version = version
        WebSandbox.ruleList { list in
            #if DEBUG
            FileHandle.standardError.write("web rules \(list != nil) load \(url.path)\n".data(using: .utf8)!)
            #endif
            if let list, !c.hasRules {
                w.configuration.userContentController.add(list)
                c.hasRules = true
            }
            w.loadFileURL(url, allowingReadAccessTo: root)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: URL?
        var version = -1
        var hasRules = false

        #if DEBUG
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.innerText + ' | imgs: ' + [...document.images].map(i => i.naturalWidth).join(',')") { r, e in
                FileHandle.standardError.write("web finished \(String(describing: r)) \(String(describing: e))\n".data(using: .utf8)!)
            }
            if let out = ProcessInfo.processInfo.environment["TWAIN_WEB_SNAPSHOT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    webView.takeSnapshot(with: nil) { img, _ in
                        guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                    }
                }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            FileHandle.standardError.write("web failed \(error)\n".data(using: .utf8)!)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            FileHandle.standardError.write("web process terminated\n".data(using: .utf8)!)
        }
        #endif

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = action.request.url, u.scheme == "http" || u.scheme == "https" || u.scheme == "mailto",
               action.navigationType == .linkActivated {
                NSWorkspace.shared.open(u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - Plugin widgets

/// An `html` module: the plugin's own page in a sandbox (no network, only its plugin folder),
/// talking to Twain through `window.twain.call(command, params)` — the commands agents use,
/// under the same rules. `twain.module` is the module's JSON; `twain.onDataChange(f)` re-runs f
/// when data collections change; CSS variables --tw-text/-secondary/-accent/-fill follow the theme.
struct WidgetModule: View {
    @Bindable var model: AppModel
    let plugin: Plugin
    let module: JSONValue

    var body: some View {
        if let v = model.vault, let file = module["file"]?.string {
            let dir = v.root.appendingPathComponent(plugin.dir)
            WidgetWebView(model: model, url: dir.appendingPathComponent(file), root: dir, module: module,
                          plugin: plugin, dataVersion: model.dataVersion)
                .frame(height: CGFloat(module["height"]?.int ?? 200))
        } else {
            Text("html 模块需要 file（插件文件夹里的 .html）").font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct WidgetWebView: NSViewRepresentable {
    let model: AppModel
    let url: URL
    let root: URL
    let module: JSONValue
    let plugin: Plugin
    let dataVersion: Int
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WebSandbox.configuration()
        let ucc = config.userContentController
        ucc.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "twain")
        ucc.addUserScript(WKUserScript(source: Self.bridge(module: module, plugin: plugin), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: Self.themeScript(), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let w = WKWebView(frame: .zero, configuration: config)
        w.setValue(false, forKey: "drawsBackground")
        w.navigationDelegate = context.coordinator
        context.coordinator.version = dataVersion
        WebSandbox.ruleList { list in
            if let list { ucc.add(list) }
            w.loadFileURL(url, allowingReadAccessTo: root)
        }
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        if context.coordinator.version != dataVersion {
            context.coordinator.version = dataVersion
            w.evaluateJavaScript("window.twain && twain._dataChanged()")
        }
        if context.coordinator.scheme != scheme {
            context.coordinator.scheme = scheme
            w.evaluateJavaScript(Self.themeScript())
        }
    }

    static func bridge(module: JSONValue, plugin: Plugin) -> String {
        """
        window.twain = {
          module: \(module.text()),
          plugin: \(JSONValue.object(["id": .string(plugin.id), "name": .string(plugin.name)]).text()),
          call(cmd, params) { return window.webkit.messageHandlers.twain.postMessage({ cmd, params: params || {} }); },
          open(note, line) { return this.call("open", line ? { note, line } : { note }); },
          _listeners: [],
          onDataChange(f) { this._listeners.push(f); },
          _dataChanged() { this._listeners.forEach(f => { try { f(); } catch (e) { console.error(e); } }); }
        };
        """
    }

    static func themeScript() -> String {
        func hex(_ c: NSColor) -> String {
            let x = c.usingColorSpace(.sRGB) ?? .black
            return String(format: "rgba(%d,%d,%d,%.2f)", Int(x.redComponent * 255), Int(x.greenComponent * 255), Int(x.blueComponent * 255), x.alphaComponent)
        }
        var vars = ""
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            vars = "--tw-text:\(hex(.labelColor));--tw-secondary:\(hex(.secondaryLabelColor));--tw-accent:\(hex(.controlAccentColor));"
                + "--tw-fill:\(hex(.quaternaryLabelColor));--tw-bg:\(hex(.textBackgroundColor));"
        }
        return """
        (function(){ var s = document.getElementById('tw-theme') || document.createElement('style'); s.id = 'tw-theme';
          s.textContent = ':root{\(vars)}'; (document.head || document.documentElement).appendChild(s); })();
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        let model: AppModel
        var version = -1
        var scheme: ColorScheme?
        init(model: AppModel) { self.model = model }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
                return replyHandler(nil, "twain.call(命令, 参数)")
            }
            let paramsData = (try? JSONSerialization.data(withJSONObject: body["params"] ?? [:])) ?? Data("{}".utf8)
            let params = (try? JSONDecoder().decode(JSONValue.self, from: paramsData))?.object ?? [:]
            guard let c = CommandRegistry.command(cmd, in: model), c.agents else { return replyHandler(nil, "没有命令 \(cmd)") }
            do { try c.spec.validate(params) } catch let e as RPCError { return replyHandler(nil, e.message) } catch {}
            c.perform(model, CommandCall(params: params)) { result in
                switch result {
                case let .success(v):
                    replyHandler(try? JSONSerialization.jsonObject(with: v.encoded(), options: [.fragmentsAllowed]), nil)
                case let .failure(e):
                    replyHandler(nil, e.message)
                }
            }
        }

        #if DEBUG
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                webView.evaluateJavaScript("document.body.innerText") { r, e in
                    FileHandle.standardError.write("widget \(String(describing: r)) \(String(describing: e))\n".data(using: .utf8)!)
                }
            }
        }
        #endif

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // A widget stays on its own page; links go to the browser.
            if action.navigationType == .linkActivated, let u = action.request.url {
                if u.scheme == "http" || u.scheme == "https" { NSWorkspace.shared.open(u) }
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
    }
}
