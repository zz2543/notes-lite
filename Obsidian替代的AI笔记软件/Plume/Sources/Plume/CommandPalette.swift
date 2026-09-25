import PlumeCore
import SwiftUI

struct PaletteEntry: Identifiable {
    enum Section: String { case notes = "笔记", commands = "命令" }
    let id: String
    let section: Section
    let label: String
    let hint: String
    let icon: String
    var tint: Color? = nil
    let run: () -> Void
}

/// ⌘K: one field that finds notes and runs commands, floating above the window like Spotlight.
struct CommandPalette: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    private var entries: [PaletteEntry] {
        let m = model
        var cmds: [PaletteEntry] = [
            .init(id: "new", section: .commands, label: "新建笔记", hint: "⌘N", icon: "square.and.pencil", run: m.newNote),
            .init(id: "zen", section: .commands, label: m.zen ? "退出专注模式" : "进入专注模式", hint: "⌘.", icon: "arrow.up.left.and.arrow.down.right", run: m.toggleZen),
            .init(id: "tw", section: .commands, label: "打字机滚动：" + (m.typewriter ? "关闭" : "开启"), hint: "", icon: "text.aligncenter") { m.typewriter.toggle() },
            .init(id: "dim", section: .commands, label: "段落聚焦：" + (m.dim ? "关闭" : "开启"), hint: "", icon: "text.line.first.and.arrowtriangle.forward") { m.dim.toggle() },
            .init(id: "font", section: .commands, label: "切换字体：衬线 / 无衬线 / 等宽", hint: m.font.shortLabel, icon: "textformat") { m.font = m.font.next },
            .init(id: "sum", section: .commands, label: "让 Claude Code 总结当前笔记", hint: "Agent", icon: "sparkle", tint: Theme.claude) {
                m.runAgent(prompt: "总结这篇笔记，在开头加一段摘要", agent: .claude)
            },
            .init(id: "todo", section: .commands, label: "让 Codex 整理当前笔记的待办", hint: "Agent", icon: "terminal") {
                m.runAgent(prompt: "整理这篇笔记的待办，合并重复项", agent: .codex)
            },
        ]
        if !m.pending.isEmpty {
            cmds.append(.init(id: "review", section: .commands, label: "审阅待定改动（\(m.pending.count)）", hint: "⇧⌘R", icon: "checklist", run: m.reviewNext))
        }
        cmds += [
            .init(id: "settings", section: .commands, label: "Agent 与 CLI 设置", hint: "⌘,", icon: "gearshape") { m.openSettings(.agent) },
            .init(id: "vault", section: .commands, label: "打开其他库…", hint: "⌘O", icon: "folder", run: m.chooseVault),
            .init(id: "ob", section: .commands, label: "重新运行新手引导", hint: "", icon: "hand.wave") { m.onboardingStep = 0 },
        ]
        let notes = (m.vault?.notes ?? []).map { n in
            PaletteEntry(id: "n:" + n.rel, section: .notes, label: n.displayName, hint: n.folder,
                         icon: n.isAgentFile ? "doc.badge.gearshape" : "doc.text") {
                m.open(n.rel, focus: true)
            }
        }
        let q = m.paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return Array(notes.filter { $0.id != "n:" + (m.activeRel ?? "") }.prefix(4)) + cmds
        }
        return (notes + cmds).filter { $0.label.lowercased().contains(q) || $0.hint.lowercased().contains(q) }
    }

    var body: some View {
        let list = entries
        let sel = min(model.paletteSel, max(0, list.count - 1))
        ZStack(alignment: .top) {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { model.palette = false }
            VStack(spacing: 0) {
                searchField(list: list, sel: sel)
                if !list.isEmpty || !model.paletteQuery.isEmpty {
                    Divider().padding(.horizontal, 14)
                    results(list: list, sel: sel)
                    footer
                }
            }
            .frame(width: 640)
            // A dense list needs a steadier backdrop than bare glass: tint the glass with the
            // window color so the page behind cannot compete with the results.
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.55),
                        in: .rect(cornerRadius: Metrics.panelRadius, style: .continuous))
            .floatingGlass(radius: Metrics.panelRadius)
            .padding(.top, 96)
        }
        .onAppear { focused = true }
    }

    private func searchField(list: [PaletteEntry], sel: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索笔记，或输入命令", text: $model.paletteQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($focused)
                .onChange(of: model.paletteQuery) { _, _ in model.paletteSel = 0 }
                .onKeyPress(.downArrow) { move(1, list.count); return .handled }
                .onKeyPress(.upArrow) { move(-1, list.count); return .handled }
                .onKeyPress(.escape) { model.palette = false; return .handled }
                .onKeyPress(.return) {
                    model.palette = false
                    if list.isEmpty {
                        let q = model.paletteQuery.trimmingCharacters(in: .whitespaces)
                        if !q.isEmpty { model.openByTitle(q) }
                    } else {
                        list[sel].run()
                    }
                    return .handled
                }
        }
        .padding(.horizontal, 20).frame(height: 60)
    }

    private func results(list: [PaletteEntry], sel: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        if i == 0 || list[i - 1].section != e.section {
                            Text(e.section.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, i == 0 ? 4 : 10).padding(.bottom, 2)
                        }
                        row(e, on: i == sel)
                            .id(i)
                            .onHover { if $0 { model.paletteSel = i } }
                            .onTapGesture { model.palette = false; e.run() }
                    }
                    if list.isEmpty {
                        Label("没有匹配项 · 按 ↩ 新建「\(model.paletteQuery)」", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: model.paletteSel) { _, v in proxy.scrollTo(v) }
        }
    }

    private func row(_ e: PaletteEntry, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: e.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(on ? AnyShapeStyle(.white) : e.tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
                .frame(width: 28, height: 28)
                .background(on ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.fill.tertiary),
                            in: .rect(cornerRadius: 7, style: .continuous))
            Text(e.label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(e.hint)
                .font(e.hint.hasPrefix("⌘") || e.hint.hasPrefix("⇧") ? .callout.monospaced() : .caption)
                .foregroundStyle(on ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                .lineLimit(1)
        }
        .foregroundStyle(on ? .white : .primary)
        .padding(.horizontal, 8).frame(height: 42)
        .background(RowHighlight(on: on))
        .contentShape(.rect)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("选择", systemImage: "arrow.up.arrow.down")
            Label("打开", systemImage: "return")
            Label("关闭", systemImage: "escape")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 14) }
    }

    private func move(_ d: Int, _ n: Int) {
        guard n > 0 else { return }
        model.paletteSel = (min(model.paletteSel, n - 1) + d + n) % n
    }
}
