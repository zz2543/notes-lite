import WebKit
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
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "noteslite.block-network", encodedContentRuleList: blockNetwork) { list, _ in
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
