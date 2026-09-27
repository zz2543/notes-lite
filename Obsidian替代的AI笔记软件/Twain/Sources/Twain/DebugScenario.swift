#if DEBUG
import AppKit
import TwainCore

/// Puts the app into a known state for offscreen snapshots (see AppDelegate.snapshot).
enum DebugScenario {
    static func textView() -> TwainTextView? {
        func find(_ v: NSView) -> TwainTextView? {
            if let t = v as? TwainTextView { return t }
            for s in v.subviews { if let t = find(s) { return t } }
            return nil
        }
        return NSApp.windows.compactMap { $0.contentView.flatMap(find) }.first
    }

    /// Selects `text` in the page, focused, as a user's drag would leave it.
    static func select(_ text: String, in m: AppModel) {
        let r = (m.editorText as NSString).range(of: text)
        m.requestFocus(caret: r.location)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            textView()?.setSelectedRange(r)
        }
    }

    /// Puts a made-up agent change to `rel` into the review queue, attributed to `s`.
    static func pendingReview(on rel: String, in m: AppModel, session s: AgentSession) {
        guard let text = m.vault?.diskContent(rel) else { return }
        let before = Markdown.lines(text)
        var after = before
        after.insert("> **摘要**：本文要点已整理在下方。", at: min(1, after.count))
        after += ["- [ ] 确认结论与负责人"]
        m.pending[rel] = PendingReview(rel: rel, by: s.agent, source: .app, baseline: before, proposed: after,
                                       hunks: LineDiff.hunks(from: before, to: after), snapshot: nil, sessionID: s.id)
        let counts = m.pending[rel]!
        s.items.append(SessionItem(kind: .change(rel: rel, plus: counts.plus, minus: counts.minus)))
    }

    static func apply(_ name: String, to m: AppModel) {
        let parts = name.split(separator: ":").map(String.init)
        let rel = parts.count > 1 ? parts[1] : "项目/2.0 发布计划.md"
        if m.vault?.note(rel) != nil { m.open(rel) }
        switch parts.first ?? "" {
        case "focus":
            m.requestFocus(caret: 40)
        case "caret":
            m.requestFocus(caret: Int(parts.count > 2 ? parts[2] : "0") ?? 0)
        case "slash":
            m.requestFocus(caret: (m.editorText as NSString).length)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                textView()?.insertText("\n/", replacementRange: textView()!.selectedRange())
            }
        case "type":
            m.requestFocus(caret: (m.editorText as NSString).length)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let tv = textView()!
                for s in ["\n- [ ] 第一件事", "\n", "第二件事", "\n", "\n", "正文 **粗**"] {
                    if s == "\n" { tv.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
                    else { tv.insertText(s, replacementRange: tv.selectedRange()) }
                }
            }
        case "diff", "banner":
            let before = Markdown.lines(m.editorText)
            var after = before
            after.insert("> **摘要**：本文围绕里程碑、风险、备注展开。", at: 1)
            after[after.count - 2] = "索引改为增量之后，冷启动预计降到 10 秒以内。"
            after += ["## 下一步", "- [ ] 确认结论与负责人"]
            m.pending[m.activeRel!] = PendingReview(rel: m.activeRel!, by: .claude, source: .app, baseline: before, proposed: after,
                                                    hunks: LineDiff.hunks(from: before, to: after), snapshot: "a1b2c3d")
            m.showDiff = parts.first == "diff"
            let s = AgentSession(agent: .claude, source: .app, title: "总结这篇笔记")
            s.apply([.user("总结这篇笔记，在开头加摘要"), .step(id: "1", text: "读取 AGENTS.md", write: nil), .stepDone(id: "1"),
                     .step(id: "2", text: "写入 项目/2.0 发布计划.md", write: nil), .stepDone(id: "2"),
                     .text("我在开头加了一段摘要，并在文末整理出“下一步”。")])
            s.items.append(SessionItem(kind: .change(rel: m.activeRel!, plus: 4, minus: 1)))
            m.sessions.append(s)
            m.activeSessionID = s.id
        case "proposal":
            // A proposal with reasons, one hunk already rejected with the user's reason.
            let s = AgentSession(agent: .claude, source: .app, title: "精简措辞")
            m.sessions.append(s)
            m.activeSessionID = s.id
            let lines = Markdown.lines(m.editorText)
            let edits: [JSONValue] = [
                ["old": .string(lines[1]), "new": .string("> 摘要：2.0 在 10 月 20 日前完成内测。"), "reason": "开头先交代结论，读者不用读完全文"],
                ["old": .string(lines[lines.count - 2]), "new": "冷启动目标：10 秒以内。", "reason": "把主观判断改成可验证的目标"],
            ]
            m.propose(CommandCall(params: ["note": .string(m.activeRel!), "edits": .array(edits), "reason": "精简措辞，让每段先说结论"],
                                  session: s)) { _ in }
            m.setHunk(1, .rejected)
            m.setFeedback(1, "这里需要保留原来的解释")
            m.showDiff = parts.count < 3 || parts[2] != "panel"
            if !m.showDiff {
                s.apply([.user("把这篇笔记精简一下"), .text("我提交了两处修改，等你审阅。")])
                let q = AgentQuestion(id: UUID(), sessionID: s.id, agent: .claude, question: "摘要放在标题下面，还是单独一节？",
                                      options: ["标题下面", "单独一节"], allowText: true)
                m.questions[q.id] = q
                s.items.append(SessionItem(kind: .question(q.id)))
                s.items.append(SessionItem(kind: .feedback(rel: m.activeRel!, message: "我审阅了你的修改：接受 1 处，拒绝 1 处。", sent: false)))
                m.agentPanel = true
            }
        case "ime":
            // Return while Pinyin is composing must commit the candidate, not send; plain Return must send.
            m.agentPanel = true
            m.claudeOn = false  // a send then only shows a toast instead of running the CLI
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
                m.agentInput = "测试"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    field.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                    enter()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("IME composing: marked=\(field.hasMarkedText()) toast=\(m.toast ?? "nil")")
                        field.unmarkText()
                        m.toast = nil
                        m.agentInput = "测试"
                        enter()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            print("IME plain: toast=\(m.toast ?? "nil")")
                            m.claudeOn = true
                            exit(0)
                        }
                    }
                }
            }
        case "models":
            m.agentPanel = true
            if parts.count > 2, let k = AgentKind(rawValue: parts[2]) { m.agentPick = k }
            m.modelPickerOpen = true
        case "agent":
            m.agentPanel = true
            if parts.count > 2, let k = AgentKind(rawValue: parts[2]) { m.agentPick = k }
        case "selbar":
            // A selection in the page brings up the rewrite bar.
            select("同步冲突仍然偶发，需要在压测里复现。", in: m)
        case "inline":
            // A rewrite waiting in place (or still running with :running), without calling a CLI.
            let original = "同步冲突仍然偶发，需要在压测里复现。索引是全量重建的，大库冷启动偏慢。"
            let r = (m.editorText as NSString).range(of: original)
            let s = AgentSession(agent: .claude, source: .app, title: "精简：同步冲突仍然偶发")
            s.inline = true
            m.sessions.append(s)
            let running = parts.count > 2 && parts[2] == "running"
            s.running = running
            if !running { s.apply([.user("精简"), .text("同步冲突偶发，需压测复现；索引全量重建，大库冷启动慢。")]) }
            m.inline = InlineEdit(sessionID: s.id, rel: m.activeRel!, range: r, original: original, label: "精简",
                                  proposed: running ? nil : "同步冲突偶发，需压测复现；索引全量重建，大库冷启动慢。")
            m.requestFocus(caret: r.location + 4)
        case "realinline":
            // A real rewrite through the CLI: select, then 精简.
            select("同步冲突仍然偶发，需要在压测里复现。索引是全量重建的，大库冷启动偏慢。", in: m)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let a = AppModel.inlineActions[0]
                m.startInline(label: a.label, instruction: a.instruction)
            }
        case "inlineaccept":
            // Accept goes through the text view: one undoable edit, the passage replaced in place.
            apply("inline", to: m)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                m.acceptInline()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let ok = m.editorText.contains("同步冲突偶发，需压测复现；索引全量重建，大库冷启动慢。")
                        && !m.editorText.contains("同步冲突仍然偶发") && m.inline == nil
                    let undo = textView()?.undoManager?.canUndo == true
                    FileHandle.standardError.write(Data("INLINE accepted=\(ok) undoable=\(undo)\n".utf8))
                }
            }
        case "pill":
            // The caret on an open task offers to hand it to an agent.
            let r = (m.editorText as NSString).range(of: "完成同步引擎压测")
            m.requestFocus(caret: r.location + 3)
        case "taskbar":
            select("同步冲突仍然偶发，需要在压测里复现。", in: m)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                m.openTaskBar()
                m.taskText = "查一下库里有没有关于同步冲突的记录，整理成一段说明"
            }
        case "thread":
            // A conversation with its draft beside it, and a note it changed waiting for review.
            let s = AgentSession(agent: .claude, source: .app, title: "同步冲突怎么处理")
            s.isThread = true
            s.draftRel = "同步冲突怎么处理.md"
            m.vault?.forceWrite(s.draftRel!, "# 同步冲突怎么处理\n\n## 结论\n用 CRDT 合并文本，冲突只在同一行同时修改时出现。\n\n## 待验证\n- [ ] 压测里复现一次冲突\n")
            m.vault?.scan()
            s.apply([.user("同步冲突一般怎么处理？我们现在用的是 CRDT"),
                     .text("CRDT 能自动合并大多数并发编辑。真正的冲突只出现在两端同时修改**同一行**时。\n\n建议：\n- 在压测里构造同一行并发修改\n- 记录合并后的结果是否符合预期"),
                     .user("写进草稿"), .step(id: "1", text: "写入 同步冲突怎么处理.md", write: nil), .stepDone(id: "1"),
                     .text("已经写进草稿：结论和一条待验证。")])
            m.sessions.append(s)
            pendingReview(on: "项目/同步引擎.md", in: m, session: s)
            m.showThread(s)
        case "inbox":
            let s = AgentSession(agent: .claude, source: .app, title: "整理周报")
            m.sessions.append(s)
            pendingReview(on: rel, in: m, session: s)
            let q = AgentQuestion(id: UUID(), sessionID: s.id, agent: .claude, question: "周报按项目分，还是按日期分？",
                                  options: ["按项目", "按日期"], allowText: true)
            m.questions[q.id] = q
            s.items.append(SessionItem(kind: .question(q.id)))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { m.inboxOpen = true }
        case "flow":
            // The review flow: two notes pending, the first open, "1 / 2" in the toolbar.
            let s = AgentSession(agent: .claude, source: .app, title: "整理项目笔记")
            m.sessions.append(s)
            pendingReview(on: rel, in: m, session: s)
            pendingReview(on: "项目/同步引擎.md", in: m, session: s)
            m.open("收件箱.md")
            m.startReviewFlow()
        case "tasks":
            for (title, state) in [("整理周报", "ask"), ("汇总全库待办", "run"), ("精简发布计划", "review"), ("找相关笔记", "done")] {
                let s = AgentSession(agent: title == "找相关笔记" ? .codex : .claude, source: .app, title: title)
                s.apply([.user(title), .text("好的，我先读一下相关笔记。")])
                m.sessions.append(s)
                switch state {
                case "ask":
                    let q = AgentQuestion(id: UUID(), sessionID: s.id, agent: .claude, question: "按项目分还是按日期分？",
                                          options: [], allowText: true)
                    m.questions[q.id] = q
                case "run": s.running = true
                case "review": pendingReview(on: rel, in: m, session: s)
                default: break
                }
            }
            m.showTasks()
        case "palette": m.openPalette(); m.paletteQuery = parts.count > 2 ? parts[2] : ""
        case "settings": m.openSettings(parts.count > 2 ? SettingsTab(rawValue: parts[2]) ?? .agent : .agent)
        case "onboarding": m.onboardingStep = Int(parts.count > 2 ? parts[2] : "0") ?? 0
        case "zen": m.toggleZen(); m.requestFocus(caret: 40)
        case "fakerun":
            if parts.count > 2 { m.requestFocus(caret: 5) }
            m.debugSimulateRun(rel: rel, append: "\n- [ ] 模拟 agent 追加\n")
        case "run":
            m.agentPanel = true
            m.runAgent(prompt: parts.count > 2 ? parts[2] : "在这篇笔记末尾追加一行：测试完成。", agent: .claude)
        case "markdown":
            m.agentPanel = true
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
            m.sessions.append(s)
            m.activeSessionID = s.id
        default: break
        }
    }
}
#endif
