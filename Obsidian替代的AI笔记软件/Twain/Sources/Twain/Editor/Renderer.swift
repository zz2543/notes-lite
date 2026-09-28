import AppKit
import CryptoKit
import TwainCore
import WebKit

/// What a picture is made from.
enum RenderKind: Hashable {
    /// `$$…$$` display math.
    case block
    /// `$…$` inside a line.
    case inline
    /// A ```` ```mermaid ```` block.
    case diagram
    /// A fenced block a plugin renders: its HTML page, relative to the vault.
    case plugin(page: String)
}

/// A rendered formula or diagram, in points.
final class Rendered {
    let image: NSImage?
    let size: CGSize
    /// Distance from the top to the text baseline (inline math sits on the line's baseline).
    let baseline: CGFloat
    let error: String?

    init(image: NSImage?, size: CGSize, baseline: CGFloat, error: String?) {
        self.image = image
        self.size = size
        self.baseline = baseline
        self.error = error
    }
}

/// Turns TeX, Mermaid and plugin blocks into pictures for the native editor.
///
/// KaTeX and Mermaid ship inside the app (Render/) and run in one hidden web view that never
/// reaches the network. Requests made in the same run-loop turn are rendered together on one
/// page and cut out of a single snapshot, so a note with a hundred formulas costs a few
/// round trips, not a hundred. Results are kept in memory and on disk, keyed by source and
/// appearance, so reopening a note shows its formulas at once.
final class BlockRenderer: NSObject, WKNavigationDelegate {
    static let shared = BlockRenderer()

    struct Key: Hashable {
        var kind: RenderKind
        var source: String
        var dark: Bool
        var fontSize: CGFloat
        /// For plugin blocks: the width they lay out to.
        var width: CGFloat = 0
    }

    /// Bumped when the bundled renderer changes, so old pictures on disk aren't reused.
    private static let version = "2"
    private var memory: [Key: Rendered] = [:]
    private var order: [Key] = []
    private var waiting: [Key: [() -> Void]] = [:]
    private var queue: [Key] = []
    private var busy = false
    private var pumpScheduled = false

    private var window: NSWindow?
    private var web: WKWebView?
    private var pageReady = false
    private var plugins: [String: (window: NSWindow, web: WKWebView, ready: Bool)] = [:]
    /// The vault, for plugin pages.
    var vaultRoot: URL?

    private let disk = DispatchQueue(label: "twain.render.disk", qos: .userInitiated)
    private lazy var cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("app.twain.notes/render-\(Self.version)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// The picture for `key` if it is ready; otherwise nil, and `ready` runs on the main queue
    /// once it is (from the disk cache or a fresh render).
    func rendered(_ key: Key, ready: @escaping () -> Void) -> Rendered? {
        if let r = memory[key] { return r }
        let first = waiting[key] == nil
        waiting[key, default: []].append(ready)
        guard first else { return nil }
        let file = cacheFile(key)
        disk.async {
            let hit = Self.load(file)
            DispatchQueue.main.async {
                if let hit { self.finish(key, hit) } else { self.enqueue(key) }
            }
        }
        return nil
    }

    /// Only what is already in memory; never starts work.
    func cached(_ key: Key) -> Rendered? { memory[key] }

    // MARK: cache

    private func remember(_ key: Key, _ r: Rendered) {
        if memory[key] == nil { order.append(key) }
        memory[key] = r
        // Pictures are small; keep a few thousand.
        if order.count > 3000 {
            for k in order.prefix(500) { memory[k] = nil }
            order.removeFirst(500)
        }
    }

    private func finish(_ key: Key, _ r: Rendered) {
        remember(key, r)
        for w in waiting.removeValue(forKey: key) ?? [] { w() }
    }

    private func cacheFile(_ key: Key) -> URL {
        let kind: String = switch key.kind {
        case .block: "b"
        case .inline: "i"
        case .diagram: "d"
        case let .plugin(page): "p:" + page
        }
        let id = "\(kind)|\(key.dark)|\(key.fontSize)|\(key.width)|\(key.source)"
        let hash = SHA256.hash(data: Data(id.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(hash)
    }

    private static func load(_ base: URL) -> Rendered? {
        guard let meta = try? Data(contentsOf: base.appendingPathExtension("json")),
              let j = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
              let w = j["w"] as? Double, let h = j["h"] as? Double else { return nil }
        let img = (try? Data(contentsOf: base.appendingPathExtension("png"))).flatMap(NSBitmapImageRep.init(data:)).map { rep -> NSImage in
            let i = NSImage(size: NSSize(width: w, height: h))
            i.addRepresentation(rep)
            return i
        }
        return Rendered(image: img, size: CGSize(width: w, height: h), baseline: j["baseline"] as? Double ?? h, error: j["error"] as? String)
    }

    private func store(_ r: Rendered, _ cg: CGImage?, at base: URL) {
        disk.async {
            var meta: [String: Any] = ["w": r.size.width, "h": r.size.height, "baseline": r.baseline]
            if let e = r.error { meta["error"] = e }
            if let cg, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: base.appendingPathExtension("png"))
            }
            try? JSONSerialization.data(withJSONObject: meta).write(to: base.appendingPathExtension("json"))
        }
    }

    // MARK: rendering

    private func enqueue(_ key: Key) {
        queue.append(key)
        guard !pumpScheduled else { return }
        pumpScheduled = true
        // Let the rest of this restyle ask for its pictures too, then render them together.
        DispatchQueue.main.async {
            self.pumpScheduled = false
            self.pump()
        }
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        // Plugin blocks whose page is loaded go one at a time; pages still loading wait in line.
        if let i = queue.firstIndex(where: { if case let .plugin(page) = $0.kind { return plugins[page]?.ready == true }; return false }) {
            let k = queue.remove(at: i)
            if case let .plugin(page) = k.kind { renderPlugin(k, page: page) }
            return
        }
        for k in queue { if case let .plugin(page) = k.kind { loadPlugin(page, width: k.width) } }
        guard let next = queue.first(where: { if case .plugin = $0.kind { return false }; return true }) else { return }
        guard let web = ensurePage(), pageReady else { return }
        // One batch: same look, at most a few diagrams (they are big).
        var batch: [Key] = []
        var diagrams = 0
        queue.removeAll { k in
            guard batch.count < 40, k.dark == next.dark, k.fontSize == next.fontSize else { return false }
            if case .plugin = k.kind { return false }
            if k.kind == .diagram { guard diagrams < 3 else { return false }; diagrams += 1 }
            batch.append(k)
            return true
        }
        busy = true
        let items: [[String: Any]] = batch.enumerated().map { i, k in
            ["id": i, "src": k.source, "kind": k.kind == .block ? "block" : k.kind == .inline ? "inline" : "diagram"]
        }
        let opts: [String: Any] = ["color": Self.css(Theme.NS.ink, dark: next.dark), "dark": next.dark, "fontSize": next.fontSize,
                                   "font": "-apple-system, 'PingFang SC', sans-serif"]
        web.callAsyncJavaScript("return await renderBatch(items, opts)", arguments: ["items": items, "opts": opts],
                                in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case let .success(value) = result, let boxes = value as? [[String: Any]], boxes.count == batch.count else {
                if case let .failure(e) = result { Self.log("render batch failed: \(e)") }
                for k in batch { self.finish(k, Rendered(image: nil, size: CGSize(width: 200, height: 24), baseline: 18, error: "渲染失败")) }
                self.busy = false
                self.pump()
                return
            }
            let rects = boxes.map { b in
                CGRect(x: b["x"] as? Double ?? 0, y: b["y"] as? Double ?? 0, width: b["w"] as? Double ?? 1, height: b["h"] as? Double ?? 1)
            }
            let union = rects.reduce(CGRect.null) { $0.union($1) }
            self.snapshot(web, union) { cg in
                for (i, k) in batch.enumerated() {
                    let r = rects[i]
                    let b = boxes[i]
                    let piece = cg.flatMap { Self.crop($0, r, in: union) }
                    let out = Rendered(image: piece.map { NSImage(cgImage: $0, size: r.size) }, size: r.size,
                                       baseline: b["baseline"] as? Double ?? r.height, error: b["error"] as? String)
                    self.store(out, piece, at: self.cacheFile(k))
                    self.finish(k, out)
                }
                self.busy = false
                self.pump()
            }
        }
    }

    private func snapshot(_ web: WKWebView, _ rect: CGRect, done: @escaping (CGImage?) -> Void) {
        // The view must cover what is photographed.
        let need = NSSize(width: max(web.frame.width, rect.maxX + 4), height: max(web.frame.height, rect.maxY + 4))
        if need != web.frame.size {
            web.window?.setContentSize(need)
            web.frame = NSRect(origin: .zero, size: need)
        }
        let config = WKSnapshotConfiguration()
        config.rect = rect
        config.afterScreenUpdates = true
        web.takeSnapshot(with: config) { img, err in
            if let err { Self.log("snapshot failed: \(err)") }
            done(img?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }

    private static func crop(_ cg: CGImage, _ r: CGRect, in union: CGRect) -> CGImage? {
        let scale = CGFloat(cg.width) / union.width
        let px = CGRect(x: (r.minX - union.minX) * scale, y: (r.minY - union.minY) * scale, width: r.width * scale, height: r.height * scale).integral
        return cg.cropping(to: px)
    }

    // MARK: the page

    static var resources: URL? = {
        let name = "Twain_Twain.bundle"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for case let base? in bases {
            let u = base.appendingPathComponent(name).appendingPathComponent("Render")
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("renderer.html").path) { return u }
            // SwiftPM's bundle layout on the command line keeps resources under Contents/Resources.
            let v = base.appendingPathComponent(name).appendingPathComponent("Contents/Resources/Render")
            if FileManager.default.fileExists(atPath: v.appendingPathComponent("renderer.html").path) { return v }
        }
        return nil
    }()

    /// A hidden window holding a web view: WebKit only paints views that are in one.
    private static func hiddenWebView(size: NSSize, delegate: WKNavigationDelegate) -> (NSWindow, WKWebView) {
        let config = WebSandbox.configuration()
        let w = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        w.setValue(false, forKey: "drawsBackground")
        w.underPageBackgroundColor = .clear
        w.navigationDelegate = delegate
        let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents = true
        win.isExcludedFromWindowsMenu = true
        win.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        win.alphaValue = 0
        win.hasShadow = false
        win.backgroundColor = .clear
        win.isOpaque = false
        win.contentView = w
        // Never ordered in: WebKit still lays out and photographs it, and it stays out of window lists.
        win.orderOut(nil)
        return (win, w)
    }

    private func ensurePage() -> WKWebView? {
        if let web { return web }
        guard let dir = Self.resources else {
            Self.log("renderer resources missing")
            for k in queue { finish(k, Rendered(image: nil, size: CGSize(width: 240, height: 24), baseline: 18, error: "缺少渲染组件")) }
            queue.removeAll()
            return nil
        }
        let (win, w) = Self.hiddenWebView(size: NSSize(width: 2400, height: 1200), delegate: self)
        window = win
        web = w
        WebSandbox.ruleList { list in
            if let list { w.configuration.userContentController.add(list) }
            w.loadFileURL(dir.appendingPathComponent("renderer.html"), allowingReadAccessTo: dir)
        }
        return w
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === web {
            pageReady = true
            pump()
            return
        }
        for (page, p) in plugins where p.web === webView {
            plugins[page]?.ready = true
            pump()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Start over on the next request.
        if webView === web {
            window?.close()
            window = nil
            web = nil
            pageReady = false
            busy = false
        }
        for (page, p) in plugins where p.web === webView {
            p.window.close()
            plugins[page] = nil
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Pictures never navigate anywhere.
        decisionHandler(action.navigationType == .other ? .allow : .cancel)
    }

    // MARK: plugin blocks

    private func loadPlugin(_ page: String, width: CGFloat) {
        guard plugins[page] == nil else { return }
        guard let root = vaultRoot else {
            queue.removeAll { k in
                guard case .plugin(page) = k.kind else { return false }
                finish(k, Rendered(image: nil, size: CGSize(width: 240, height: 24), baseline: 18, error: "没有打开的库"))
                return true
            }
            return
        }
        let url = root.appendingPathComponent(page)
        let (win, w) = Self.hiddenWebView(size: NSSize(width: max(200, width), height: 800), delegate: self)
        plugins[page] = (win, w, false)
        w.configuration.userContentController.addUserScript(WKUserScript(source: WidgetWebView.themeScript(), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        WebSandbox.ruleList { list in
            if let list { w.configuration.userContentController.add(list) }
            w.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// Calls the loaded page's `twainRenderBlock(source, ctx)` and photographs the result.
    private func renderPlugin(_ key: Key, page: String) {
        guard let p = plugins[page] else { return }
        let width = max(200, key.width)
        busy = true
        let web = p.web
        if web.frame.width != width {
            p.window.setContentSize(NSSize(width: width, height: web.frame.height))
            web.frame.size.width = width
        }
        let ctx: [String: Any] = ["dark": key.dark, "width": width, "fontSize": key.fontSize, "color": Self.css(Theme.NS.ink, dark: key.dark)]
        let js = """
        if (typeof window.twainRenderBlock !== 'function') throw new Error('页面没有定义 twainRenderBlock(source, ctx)');
        const r = await window.twainRenderBlock(source, ctx);
        // No requestAnimationFrame here: a page that is never on screen gets no frames.
        const d = document.documentElement;
        return { w: Math.ceil((r && r.width) || Math.min(ctx.width, d.scrollWidth)), h: Math.ceil((r && r.height) || d.scrollHeight) };
        """
        // A page that never answers mustn't hold up every other picture.
        var done = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !done else { return }
            done = true
            self.finish(key, Rendered(image: nil, size: CGSize(width: width, height: 24), baseline: 18, error: "插件渲染超时（5 秒）"))
            self.busy = false
            self.pump()
        }
        web.callAsyncJavaScript(js, arguments: ["source": key.source, "ctx": ctx], in: nil, in: .page) { [weak self] result in
            guard let self, !done else { return }
            done = true
            guard case let .success(v) = result, let box = v as? [String: Any] else {
                var msg = "插件渲染失败"
                if case let .failure(e) = result { msg += "：" + ((e as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? e.localizedDescription) }
                self.finish(key, Rendered(image: nil, size: CGSize(width: width, height: 24), baseline: 18, error: msg))
                self.busy = false
                self.pump()
                return
            }
            let size = CGSize(width: min(width, box["w"] as? Double ?? width), height: min(3000, max(1, box["h"] as? Double ?? 100)))
            self.snapshot(web, CGRect(origin: .zero, size: size)) { cg in
                let out = Rendered(image: cg.map { NSImage(cgImage: $0, size: size) }, size: size, baseline: size.height, error: nil)
                // Plugin output may change with the plugin itself; memory only.
                self.finish(key, out)
                self.busy = false
                self.pump()
            }
        }
    }

    /// Forgets a plugin page (it changed on disk) and every picture made with it.
    func reloadPlugins() {
        for (_, p) in plugins { p.window.close() }
        plugins = [:]
        for k in memory.keys { if case .plugin = k.kind { memory[k] = nil } }
        order.removeAll { if case .plugin = $0.kind { return true }; return false }
    }

    // MARK: helpers

    static func css(_ c: NSColor, dark: Bool) -> String {
        var out = "#000"
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            let x = c.usingColorSpace(.sRGB) ?? .black
            out = String(format: "rgba(%d,%d,%d,%.3f)", Int(x.redComponent * 255), Int(x.greenComponent * 255), Int(x.blueComponent * 255), x.alphaComponent)
        }
        return out
    }

    static func log(_ s: String) {
        #if DEBUG
        FileHandle.standardError.write(("render: " + s + "\n").data(using: .utf8)!)
        #endif
    }
}
