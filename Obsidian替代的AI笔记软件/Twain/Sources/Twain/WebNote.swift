import SwiftUI
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
