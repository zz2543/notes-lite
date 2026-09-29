#if DEBUG
import AppKit
import TwainCore

/// Puts the app into a known state for offscreen snapshots (see AppDelegate.snapshot).
@MainActor
enum DebugScenario {
    static func textView() -> TwainTextView? {
        func find(_ v: NSView) -> TwainTextView? {
            if let t = v as? TwainTextView { return t }
            for s in v.subviews { if let t = find(s) { return t } }
            return nil
        }
        return NSApp.windows.compactMap { $0.contentView.flatMap(find) }.first
    }

    /// Seconds since this process started, from the kernel's record of it.
    static func uptime() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        let t = info.kp_proc.p_un.__p_starttime
        return Date().timeIntervalSince1970 - (Double(t.tv_sec) + Double(t.tv_usec) / 1e6)
    }

    /// Times the operations that grow with the vault, on whatever vault is open.
    static func perf(_ m: AppModel) {
        func ms(_ body: () -> Void) -> Double {
            let t = CACurrentMediaTime(); body(); return (CACurrentMediaTime() - t) * 1000
        }
        func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
        guard let v = m.vault else { return }
        log(String(format: "perf launch→ready %.0fms (includes the 1.5s scenario delay)", uptime() * 1000))
        log(String(format: "perf notes=%d folders=%d", v.notes.count, v.folders.count))
        log(String(format: "perf vault walk %.1fms", ms { _ = VaultListing.walk(v.root) }))
        var cold = VaultIndex(root: v.root)
        log(String(format: "perf index cold %.1fms", ms { cold.refresh() }))
        log(String(format: "perf index warm %.1fms", ms { cold.refresh() }))
        let store = SummaryStore(vault: v.root)
        var cards = 0
        log(String(format: "perf skim all cards %.1fms", ms { cards = cold.paths.compactMap { cold.notes[$0] }.map { Skim.card($0, store: store) }.count }) + " (\(cards))")
        for q in ["AI", "笔记", "markdown 插件", "不存在的词组xyz"] {
            var n = 0
            log(String(format: "perf search %@ %.1fms", q, ms { n = cold.search(q, limit: 20).count }) + " hits=\(n)")
        }
        log(String(format: "perf tasks %.1fms", ms { _ = cold.tasks() }))
        var parts = (hash: 0.0, words: 0.0, summary: 0.0)
        var slow: [(Double, String)] = []
        for n in cold.notes.values {
            parts.hash += ms { _ = Skim.hash(n.lines) }
            parts.words += ms { _ = Markdown.countWords(n.lines) }
            let t = ms { _ = Skim.autoSummary(n.lines) }
            parts.summary += t
            slow.append((t, n.rel))
        }
        for (t, rel) in slow.sorted(by: { $0.0 > $1.0 }).prefix(3) { log(String(format: "perf slow summary %.1fms %@", t, rel)) }
        log(String(format: "perf skim parts hash %.1fms words %.1fms summary %.1fms", parts.hash, parts.words, parts.summary))
        // Open notes of a few sizes and wait for each one's first screen to lay out.
        let size = { (n: VaultIndex.Note) in n.lines.reduce(0) { $0 + $1.count } }
        let readable = cold.notes.values.filter { AppModel.unreadableReason(v.url($0.rel)) == nil }.sorted { size($0) < size($1) }
        guard !readable.isEmpty else { return }
        let picks = [readable[readable.count / 2], readable.last { size($0) < 200_000 }, readable.last].compactMap { $0 }
        func openNext(_ i: Int) {
            guard i < picks.count else { return }
            let t = CACurrentMediaTime()
            m.open(picks[i].rel)
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    if let tv = textView(), let lm = tv.layoutManager, let tc = tv.textContainer {
                        lm.ensureLayout(forBoundingRect: tv.visibleRect, in: tc)
                    }
                    log(String(format: "perf open %d chars %.1fms", (m.editor.editorText as NSString).length, (CACurrentMediaTime() - t) * 1000))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { openNext(i + 1) }
                }
            }
        }
        openNext(0)
    }

    static func apply2(_ parts: [String], _ m: AppModel) {
        if parts.count > 1 { m.openSpace(parts[1]) }
    }

    static func apply(_ name: String, to m: AppModel) {
        let parts = name.split(separator: ":").map(String.init)
        let rel = parts.count > 1 ? parts[1] : "项目/2.0 发布计划.md"
        if parts.first == "space" { apply2(parts, m); return }
        if parts.first == "settings" {
            m.openSettings(SettingsTab(rawValue: parts.count > 1 ? parts[1] : "open") ?? .open)
            // settings:<tab>:bottom — scrolls the page to its end, for sections below the fold.
            if parts.count > 2, parts[2] == "bottom" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
                    for w in NSApp.windows where w.isVisible {
                        for case let sv as NSScrollView in views(w.contentView ?? NSView()) {
                            if let doc = sv.documentView { doc.scroll(NSPoint(x: 0, y: doc.isFlipped ? doc.bounds.height : 0)) }
                        }
                    }
                }
            }
            return
        }
        if m.vault?.note(rel) != nil { m.open(rel) }
        switch parts.first ?? "" {
        case "toggles":
            // Hides and shows the sidebar and the inspector at whatever width the window has.
            let steps: [(AppModel) -> Void] = [
                { $0.chrome.agentPanel.toggle() }, { $0.chrome.agentPanel.toggle() },
                { $0.chrome.columnVisibility = .detailOnly }, { $0.chrome.columnVisibility = .all },
                { $0.toggleZen() }, { $0.toggleZen() },
            ]
            for (i, s) in steps.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(i + 1)) { s(m) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(steps.count + 2)) {
                FileHandle.standardError.write("toggles done\n".data(using: .utf8)!)
            }
        case "perf":
            perf(m)
        case "taskfx":
            // taskfx:<note>:<style>:<scale>:<stroke> — checks the first open task with the check box
            // effect frozen at that state, and writes the text layer to TWAIN_FX_OUT.
            Motion.style = MotionStyle(rawValue: parts.count > 2 ? parts[2] : "") ?? .calm
            let freeze = parts.count > 4 ? (CGFloat(Double(parts[3]) ?? 1), CGFloat(Double(parts[4]) ?? 1)) : nil
            EditorEffects.still = freeze.map { (scale: $0.0, stroke: $0.1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let tv = textView(), let c = tv.coordinator else { return }
                if parts.count > 2, parts[2] == "fade" {
                    // taskfx:<note>:fade — lays the cross-fade's picture over the text, kept fully shown.
                    Motion.style = .calm
                    EditorEffects.stillFade = true
                    EditorEffects.fadeNextDraw(of: tv)
                } else if freeze != nil { c.debugCheckFirstTask() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    tv.display()
                    guard let layer = tv.layer, let out = ProcessInfo.processInfo.environment["TWAIN_FX_OUT"] else { return }
                    let scale: CGFloat = 2
                    let visible = tv.visibleRect
                    let w = Int(visible.width * scale), h = Int(min(visible.height, 500) * scale)
                    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                    ctx.scaleBy(x: scale, y: scale)
                    if layer.contentsAreFlipped() { ctx.translateBy(x: 0, y: visible.height); ctx.scaleBy(x: 1, y: -1) }
                    ctx.translateBy(x: -visible.minX, y: -visible.minY)
                    layer.render(in: ctx)
                    if let img = ctx.makeImage() {
                        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                    }
                    FileHandle.standardError.write("taskfx done flipped=\(layer.contentsAreFlipped())\n".data(using: .utf8)!)
                    exit(0)
                }
            }
        case "stress":
            DebugStress.run(m, count: parts.count > 1 ? Int(parts[1]) ?? 44 : 44)
        case "rendertest":
            // Renders a few formulas and a diagram and writes them next to TWAIN_RENDER_OUT.
            let out = ProcessInfo.processInfo.environment["TWAIN_RENDER_OUT"] ?? "/tmp/twain-render"
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let keys: [BlockRenderer.Key] = [
                .init(kind: .block, source: #"d_{nodal} = d_{proc} + d_{queue} + \frac{L}{R}"#, dark: dark, fontSize: 17),
                .init(kind: .inline, source: #"x^2 + \sqrt{y}"#, dark: dark, fontSize: 17),
                .init(kind: .block, source: #"\ce{H2O ->[\Delta] H2 + O2}"#, dark: dark, fontSize: 17),
                .init(kind: .block, source: #"\badcommand{x}"#, dark: dark, fontSize: 17),
                .init(kind: .diagram, source: "graph TD\nA(通信网络)-->B1(电路交换)\nA-->B2(分组交换)", dark: dark, fontSize: 17),
                .init(kind: .diagram, source: "graph TD\nA-->", dark: dark, fontSize: 17),
            ]
            let t = CACurrentMediaTime()
            var left = keys.count
            for (i, k) in keys.enumerated() {
                func write(_ r: Rendered) {
                    let rep = r.image.flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }.map(NSBitmapImageRep.init(cgImage:))
                    try? rep?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)-\(i).png"))
                    FileHandle.standardError.write(String(format: "rendertest %d %.0fx%.0f base %.1f err %@ at %.0fms\n", i, r.size.width, r.size.height, r.baseline,
                                                          r.error ?? "-", (CACurrentMediaTime() - t) * 1000).data(using: .utf8)!)
                    left -= 1
                }
                if let r = BlockRenderer.shared.rendered(k, ready: { write(BlockRenderer.shared.cached(k)!) }) { write(r) }
            }
        case "openbench":
            // openbench:<a.md>,<b.md>,… — opens each note three times and reports the time until
            // its first screen is typeset (the second and third opens show the warm cost).
            let rels = (parts.count > 1 ? parts[1] : "").split(separator: ",").map(String.init)
            // openbench:<notes>:nosidebar / :noagent — the same opens with a column hidden.
            if parts.contains("nosidebar") { m.chrome.columnVisibility = .detailOnly }
            if parts.contains("noagent") { m.chrome.agentPanel = false }
            var queue = rels.flatMap { [$0, $0, $0] }
            func next() {
                guard !queue.isEmpty else { FileHandle.standardError.write("openbench done\n".data(using: .utf8)!); return }
                let rel = queue.removeFirst()
                m.open("", focus: false)
                DispatchQueue.main.async {
                    let t = CACurrentMediaTime()
                    m.open(rel)
                    let t1 = CACurrentMediaTime()
                    DispatchQueue.main.async {
                        let t2 = CACurrentMediaTime()
                        if let tv = textView(), let lm = tv.layoutManager, let tc = tv.textContainer {
                            lm.ensureLayout(forBoundingRect: tv.visibleRect, in: tc)
                            let t3 = CACurrentMediaTime()
                            tv.display()
                            FileHandle.standardError.write(String(format: "openbench parts open %.1f turn %.1f layout %.1f draw %.1f\n", (t1 - t) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000, (CACurrentMediaTime() - t3) * 1000).data(using: .utf8)!)
                        }
                        FileHandle.standardError.write(String(format: "openbench %@ %d chars %.1fms\n", rel,
                                                              (m.editor.editorText as NSString).length, (CACurrentMediaTime() - t) * 1000).data(using: .utf8)!)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { next() }
                    }
                }
            }
            next()
        case "resize":
            // Sweeps the window width a few points at a time, the way a user dragging its edge
            // would, to catch layouts whose size depends on their own size.
            if parts.contains("reply") { apply("reply", to: m) }
            if parts.contains("noagent") { m.chrome.agentPanel = false }
            if parts.contains("nosidebar") { m.chrome.columnVisibility = .detailOnly }
            guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView?.frame.width ?? 0 > 600 }) else { return }
            var width = w.frame.width
            // Down to 900, then back and forth through 820–900 a point at a time.
            var dir: CGFloat = -3, bounces = 0
            func step() {
                width += dir
                if width <= 820 { dir = 1; bounces += 1 } else if width >= 900, bounces > 0 { dir = -1; bounces += 1 }
                if width < 900, dir == -3 { dir = -1 }
                guard bounces < 8 else { FileHandle.standardError.write("resize done\n".data(using: .utf8)!); return }
                var f = w.frame; f.size.width = width; w.setFrame(f, display: true)
                FileHandle.standardError.write("width \(Int(width))\n".data(using: .utf8)!)
                DispatchQueue.main.async { step() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { step() }
        case "pastetest":
            // pastetest:<note>:<attachmentFolderPath>:<naming> — pastes a picture twice (with its
            // address as text, like a browser's Copy Image) and reports the files and the note.
            if parts.count > 2 { m.attachmentSetting = parts[2] }
            if parts.count > 3, let n = AttachmentNaming(rawValue: parts[3]) { m.prefs.attachmentNaming = n }
            m.requestFocus(caret: (m.editor.editorText as NSString).length)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let img = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { r in NSColor.systemTeal.setFill(); r.fill(); return true }
                let pb = NSPasteboard(name: NSPasteboard.Name("twain.pastetest"))
                pb.clearContents()
                pb.setData(NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!, forType: .png)
                pb.setString("https://example.com/a.png", forType: .string)
                let tv = textView()!
                let c = tv.coordinator!
                let ok1 = c.pasteMedia(from: pb, at: nil)
                let ok2 = c.pasteMedia(from: pb, at: nil)
                let text = NSPasteboard(name: NSPasteboard.Name("twain.pastetest2"))
                text.clearContents()
                text.setString("第一行\n第二行 普通文字", forType: .string)
                text.setData(pb.data(forType: .png), forType: .png)
                let ok3 = c.pasteMedia(from: text, at: nil)
                let files = (FileManager.default.enumerator(atPath: m.vault!.rootPath)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".png") }.sorted()
                let log = "pastetest ok=\(ok1),\(ok2) textWins=\(!ok3) setting=\(m.attachmentSetting) files=\(files) tail=\(m.editor.editorText.suffix(80).replacingOccurrences(of: "\n", with: "⏎"))\n"
                FileHandle.standardError.write(log.data(using: .utf8)!)
            }
        case "scroll":
            // scroll:<note>:<y> — scrolls the editor to y points without touching the caret.
            let y = CGFloat(Double(parts.count > 2 ? parts[2] : "0") ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let tv = textView(), let clip = tv.enclosingScrollView?.contentView else { return }
                if let lm = tv.layoutManager, let tc = tv.textContainer { lm.ensureLayout(forBoundingRect: CGRect(x: 0, y: 0, width: 4000, height: y + 2000), in: tc) }
                clip.scroll(to: NSPoint(x: 0, y: y))
                tv.enclosingScrollView?.reflectScrolledClipView(clip)
            }
        case "focus":
            m.requestFocus(caret: 40)
        case "caret":
            m.requestFocus(caret: Int(parts.count > 2 ? parts[2] : "0") ?? 0)
        case "select":
            // select:<note>:<from>:<length> — a multi-line selection, to check how it is drawn.
            let from = Int(parts.count > 2 ? parts[2] : "0") ?? 0
            m.requestFocus(caret: from)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let tv = textView()!
                let len = (tv.string as NSString).length
                let n = Int(parts.count > 3 ? parts[3] : "") ?? len
                tv.setSelectedRange(NSRange(location: min(from, len), length: min(n, len - min(from, len))))
            }
        case "slash":
            m.requestFocus(caret: (m.editor.editorText as NSString).length)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                textView()?.insertText("\n/", replacementRange: textView()!.selectedRange())
            }
        case "type":
            m.requestFocus(caret: (m.editor.editorText as NSString).length)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let tv = textView()!
                for s in ["\n- [ ] 第一件事", "\n", "第二件事", "\n", "\n", "正文 **粗**"] {
                    if s == "\n" { tv.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
                    else { tv.insertText(s, replacementRange: tv.selectedRange()) }
                }
            }
        case "space":
            if parts.count > 1 { m.openSpace(parts[1]) }
        case "desk":
            if let d = m.desks.first(where: { !$0.cards.isEmpty }) { m.chrome.selection = "desk:" + d.id }
        case "reply":
            let s = AgentSession(agent: .claude, source: .app, title: "续写")
            s.apply([.user("根据上下文续写这篇笔记"), .step(id: "1", text: "读取 AGENTS.md", write: nil), .stepDone(id: "1"),
                     .text("""
                     我在「找回生活的掌控感」末尾续写了几条，已经提交到共笔等你审阅，**还没写进文件**。写法跟前两条一样：

                     ```
                     每天睡前花五分钟写下第二天最重要的三件事
                     固定起床和睡觉的时间，周末也不要差太多
                     ```

                     续写接在最后一条“深度工作四小时”后面：
                     - 第一条理由，带 `代码` 和 [链接](https://example.com)
                     - 第二条
                     1. 有序
                     > 你要是其实想在别的位置续写，告诉我在哪就行。
                     """)])
            m.agents.sessions.append(s)
            m.agents.activeSessionID = s.id
        case "bench":
            // Types into the middle of the note, one key per run-loop turn so the async work
            // (SwiftUI updates, height fitting, drawing) counts too, and reports per-key costs.
            let mid = (m.editor.editorText as NSString).length / 2
            m.requestFocus(caret: mid)
            let keys = ProcessInfo.processInfo.environment["BENCH_KEYS"].flatMap(Int.init) ?? 60
            var times: [Double] = []
            var last = CACurrentMediaTime()
            func step(_ i: Int) {
                let tv = textView()!
                if i > 0 { times.append((CACurrentMediaTime() - last) * 1000) }
                guard i < keys else {
                    let sorted = times.sorted()
                    let line = String(format: "bench keys=%d median=%.2fms p95=%.2fms max=%.2fms length=%d\n",
                                      times.count, sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.95)], sorted.last!,
                                      (m.editor.editorText as NSString).length)
                    FileHandle.standardError.write(line.data(using: .utf8)!)
                    return
                }
                last = CACurrentMediaTime()
                if i % 15 == 14 { tv.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
                else { tv.insertText(i % 2 == 0 ? "字" : "a", replacementRange: tv.selectedRange()) }
                // Let the run loop do everything a real key would trigger, then type the next.
                DispatchQueue.main.async { DispatchQueue.main.async { step(i + 1) } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { step(0) }
        case "diff", "banner":
            let before = Markdown.lines(m.editor.editorText)
            var after = before
            after.insert("> **摘要**：本文围绕里程碑、风险、备注展开。", at: 1)
            after[after.count - 2] = "索引改为增量之后，冷启动预计降到 10 秒以内。"
            after += ["## 下一步", "- [ ] 确认结论与负责人"]
            m.agents.pending[m.editor.activeRel!] = PendingReview(rel: m.editor.activeRel!, by: .claude, source: .app, baseline: before, proposed: after,
                                                    hunks: LineDiff.hunks(from: before, to: after), snapshot: "a1b2c3d")
            m.editor.showDiff = parts.first == "diff"
            let s = AgentSession(agent: .claude, source: .app, title: "总结这篇笔记")
            s.apply([.user("总结这篇笔记，在开头加摘要"), .step(id: "1", text: "读取 AGENTS.md", write: nil), .stepDone(id: "1"),
                     .step(id: "2", text: "写入 项目/2.0 发布计划.md", write: nil), .stepDone(id: "2"),
                     .text("我在开头加了一段摘要，并在文末整理出“下一步”。")])
            s.items.append(SessionItem(kind: .change(rel: m.editor.activeRel!, plus: 4, minus: 1)))
            m.agents.sessions.append(s)
            m.agents.activeSessionID = s.id
        case "proposal":
            // A proposal with reasons, one hunk already rejected with the user's reason.
            let s = AgentSession(agent: .claude, source: .app, title: "精简措辞")
            m.agents.sessions.append(s)
            m.agents.activeSessionID = s.id
            let lines = Markdown.lines(m.editor.editorText)
            let edits: [JSONValue] = [
                ["old": .string(lines[1]), "new": .string("> 摘要：2.0 在 10 月 20 日前完成内测。"), "reason": "开头先交代结论，读者不用读完全文"],
                ["old": .string(lines[lines.count - 2]), "new": "冷启动目标：10 秒以内。", "reason": "把主观判断改成可验证的目标"],
            ]
            m.propose(CommandCall(params: ["note": .string(m.editor.activeRel!), "edits": .array(edits), "reason": "精简措辞，让每段先说结论"],
                                  session: s)) { _ in }
            // The proposal is made once the index has caught up (a moment later).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            m.setHunk(1, .rejected)
            m.setFeedback(1, "这里需要保留原来的解释")
            m.editor.showDiff = parts.count < 3 || parts[2] != "panel"
            if !m.editor.showDiff {
                s.apply([.user("把这篇笔记精简一下"), .text("我提交了两处修改，等你审阅。")])
                let q = AgentQuestion(id: UUID(), sessionID: s.id, agent: .claude, question: "摘要放在标题下面，还是单独一节？",
                                      options: ["标题下面", "单独一节"], allowText: true)
                m.agents.questions[q.id] = q
                s.items.append(SessionItem(kind: .question(q.id)))
                s.items.append(SessionItem(kind: .feedback(rel: m.editor.activeRel!, message: "我审阅了你的修改：接受 1 处，拒绝 1 处。", sent: false)))
                m.chrome.agentPanel = true
            }
            }
        case "ime":
            // Return while Pinyin is composing must commit the candidate, not send; plain Return must send.
            m.chrome.agentPanel = true
            m.prefs.claudeOn = false  // a send then only shows a toast instead of running the CLI
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
                func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
                let composer = views(w.contentView!.superview ?? w.contentView!).compactMap { $0 as? NSTextField }
                    .first { $0.placeholderString?.hasPrefix("让 ") == true }
                guard let composer, w.makeFirstResponder(composer), let field = w.firstResponder as? NSTextView else {
                    print("IME: composer not found"); return
                }
                func enter() {
                    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                             context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                    w.sendEvent(e)
                }
                m.agents.agentInput = "测试"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    field.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                    enter()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("IME composing: marked=\(field.hasMarkedText()) toast=\(m.chrome.toast ?? "nil")")
                        field.unmarkText()
                        m.chrome.toast = nil
                        m.agents.agentInput = "测试"
                        enter()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            print("IME plain: toast=\(m.chrome.toast ?? "nil")")
                            m.prefs.claudeOn = true
                            exit(0)
                        }
                    }
                }
            }
        case "models":
            m.chrome.agentPanel = true
            if parts.count > 2, let k = AgentKind(rawValue: parts[2]) { m.agents.agentPick = k }
            m.chrome.modelPickerOpen = true
        case "agent":
            m.chrome.agentPanel = true
            if parts.count > 2, let k = AgentKind(rawValue: parts[2]) { m.agents.agentPick = k }
        case "palette": m.openPalette(); m.chrome.paletteQuery = parts.count > 2 ? parts[2] : ""
        case "settings": m.openSettings(parts.count > 2 ? SettingsTab(rawValue: parts[2]) ?? .agent : .agent)
        case "onboarding": m.chrome.onboardingStep = Int(parts.count > 2 ? parts[2] : "0") ?? 0
        case "zen": m.toggleZen(); m.requestFocus(caret: 40)
        case "fakerun":
            if parts.count > 2 { m.requestFocus(caret: 5) }
            m.debugSimulateRun(rel: rel, append: "\n- [ ] 模拟 agent 追加\n")
        case "run":
            m.chrome.agentPanel = true
            m.runAgent(prompt: parts.count > 2 ? parts[2] : "在这篇笔记末尾追加一行：测试完成。", agent: .claude)
        case "markdown":
            m.chrome.agentPanel = true
            let s = AgentSession(agent: .claude, source: .app, title: "Markdown 预览")
            s.apply([.user("总结这篇笔记"), .text("""
            # 本周进展

            已完成 **编辑器优化**，详情见 [项目文档](https://example.com)。

            - 支持 Markdown 回复
            - 保持审阅状态
              - 避免误触

            > 下一步：验证快照和真实运行。

            ```swift
            let status = "待审阅"
            print(status)
            ```
            """)])
            m.agents.sessions.append(s)
            m.agents.activeSessionID = s.id
        default: break
        }
    }
}
#endif
