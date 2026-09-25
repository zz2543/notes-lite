#if DEBUG
import AppKit
import PlumeCore

/// Puts the app into a known state for offscreen snapshots (see AppDelegate.snapshot).
enum DebugScenario {
    static func textView() -> PlumeTextView? {
        func find(_ v: NSView) -> PlumeTextView? {
            if let t = v as? PlumeTextView { return t }
            for s in v.subviews { if let t = find(s) { return t } }
            return nil
        }
        return NSApp.windows.compactMap { $0.contentView.flatMap(find) }.first
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
