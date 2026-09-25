import PlumeCore
import SwiftUI

// MARK: - Command palette

struct PaletteEntry: Identifiable {
    let id: String
    let label: String
    let hint: String
    let isNote: Bool
    let run: () -> Void
}

struct CommandPalette: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    private var entries: [PaletteEntry] {
        let m = model
        var cmds: [PaletteEntry] = [
            .init(id: "new", label: "新建笔记", hint: "⌘N", isNote: false, run: m.newNote),
            .init(id: "zen", label: m.zen ? "退出专注模式" : "进入专注模式", hint: "⌘.", isNote: false, run: m.toggleZen),
            .init(id: "tw", label: "打字机滚动：" + (m.typewriter ? "关闭" : "开启"), hint: "", isNote: false) { m.typewriter.toggle() },
            .init(id: "dim", label: "段落聚焦：" + (m.dim ? "关闭" : "开启"), hint: "", isNote: false) { m.dim.toggle() },
            .init(id: "font", label: "切换字体：衬线 / 无衬线 / 等宽", hint: "", isNote: false) { m.font = m.font.next },
            .init(id: "sum", label: "让 Claude Code 总结当前笔记", hint: "Agent", isNote: false) { m.runAgent(prompt: "总结这篇笔记，在开头加一段摘要", agent: .claude) },
            .init(id: "todo", label: "让 Codex 整理当前笔记的待办", hint: "Agent", isNote: false) { m.runAgent(prompt: "整理这篇笔记的待办，合并重复项", agent: .codex) },
        ]
        if !m.pending.isEmpty, let first = m.pending.keys.sorted().first {
            cmds.append(.init(id: "review", label: "审阅待定改动（\(m.pending.count)）", hint: "Diff", isNote: false) {
                m.open(first); m.showDiff = true
            })
        }
        cmds += [
            .init(id: "settings", label: "Agent 与 CLI 设置", hint: "⌘,", isNote: false) { m.openSettings(.agent) },
            .init(id: "vault", label: "打开其他库…", hint: "", isNote: false, run: m.chooseVault),
            .init(id: "ob", label: "重新运行新手引导", hint: "", isNote: false) { m.onboardingStep = 0 },
        ]
        let notes = (m.vault?.notes ?? []).map { n in
            PaletteEntry(id: "n:" + n.rel, label: n.displayName, hint: n.folder.isEmpty ? "库" : n.folder, isNote: true) { m.open(n.rel, focus: true) }
        }
        let q = m.paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            let recent = notes.filter { $0.id != "n:" + (m.activeRel ?? "") }.prefix(4)
            return Array(recent) + cmds
        }
        return (notes + cmds).filter { $0.label.lowercased().contains(q) || $0.hint.lowercased().contains(q) }
    }

    var body: some View {
        let list = entries
        let sel = min(model.paletteSel, max(0, list.count - 1))
        ZStack(alignment: .top) {
            Color(hex: 0x1E1C19, alpha: 0.12)
                .ignoresSafeArea()
                .onTapGesture { model.palette = false }
            VStack(spacing: 0) {
                TextField("", text: $model.paletteQuery, prompt: Text("搜索笔记，或输入命令…").foregroundStyle(Theme.faint))
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .focused($focused)
                    .onChange(of: model.paletteQuery) { _, _ in model.paletteSel = 0 }
                    .onKeyPress(.downArrow) { move(1, list.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, list.count); return .handled }
                    .onKeyPress(.escape) { model.palette = false; return .handled }
                    .onKeyPress(.return) {
                        if list.isEmpty {
                            let q = model.paletteQuery.trimmingCharacters(in: .whitespaces)
                            model.palette = false
                            if !q.isEmpty { model.openByTitle(q) }
                        } else {
                            model.palette = false
                            list[sel].run()
                        }
                        return .handled
                    }
                Rectangle().fill(Color(hex: 0xECE9E4)).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                                HStack(spacing: 10) {
                                    if e.isNote {
                                        RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1.2).frame(width: 10, height: 12).opacity(0.45)
                                    }
                                    Text(e.label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(e.hint).font(.system(size: 11.5)).opacity(0.6)
                                }
                                .font(.system(size: 13.5))
                                .foregroundStyle(i == sel ? .white : Theme.ink)
                                .padding(.horizontal, 12).frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 7).fill(i == sel ? Theme.accent : .clear))
                                .contentShape(Rectangle())
                                .id(i)
                                .onHover { if $0 { model.paletteSel = i } }
                                .onTapGesture { model.palette = false; e.run() }
                            }
                            if list.isEmpty {
                                Text("没有匹配项 · ↵ 新建「\(model.paletteQuery)」")
                                    .foregroundStyle(Theme.muted).padding(18)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: model.paletteSel) { _, v in proxy.scrollTo(v) }
                }
                Rectangle().fill(Color(hex: 0xECE9E4)).frame(height: 1)
                HStack(spacing: 14) {
                    Text("↑↓ 选择"); Text("↵ 执行"); Text("esc 关闭"); Spacer()
                }
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xFCFBF9)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 35, y: 24)
            .padding(.top, 110)
        }
        .onAppear { focused = true }
    }

    private func move(_ d: Int, _ n: Int) {
        guard n > 0 else { return }
        model.paletteSel = (min(model.paletteSel, n - 1) + d + n) % n
    }
}

// MARK: - Settings

struct SettingsOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Color(hex: 0x1E1C19, alpha: 0.16).ignoresSafeArea()
                .onTapGesture { model.settings = false }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Button { model.settings = false } label: { Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12) }
                            .buttonStyle(.plain).help("关闭")
                        Circle().fill(Color(hex: 0xDCD9D4)).frame(width: 12, height: 12)
                        Circle().fill(Color(hex: 0xDCD9D4)).frame(width: 12, height: 12)
                    }
                    .padding(.horizontal, 6).padding(.top, 2).padding(.bottom, 16)
                    ForEach([(SettingsTab.editor, "编辑器"), (.agent, "Agent 与 CLI"), (.keys, "快捷键")], id: \.0) { tab, label in
                        Button { model.settingsTab = tab } label: {
                            Text(label).font(.system(size: 13, weight: model.settingsTab == tab ? .medium : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).frame(height: 28)
                        }
                        .buttonStyle(.hover(.black.opacity(0.05), base: model.settingsTab == tab ? .black.opacity(0.08) : .clear))
                    }
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 14)
                .frame(width: 190)
                .background(Color(hex: 0xF1EFEB))
                .overlay(alignment: .trailing) { Rectangle().fill(Color(hex: 0xE4E1DC)).frame(width: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch model.settingsTab {
                        case .agent: AgentSettings(model: model)
                        case .editor: EditorSettings(model: model)
                        case .keys: KeySettings()
                        }
                    }
                    .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 780, maxHeight: 560)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xFBFAF8)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.22), radius: 40, y: 30)
            .padding(24)
        }
        .onExitCommand { model.settings = false }
    }
}

struct AgentSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Text("Agent 与 CLI").font(.system(size: 18, weight: .semibold))
        Text("Plume 不托管模型。库就是磁盘上的一个文件夹，Claude Code 和 Codex 在里面直接读写 .md；Plume 负责看见、审阅和还原每一次改动。")
            .foregroundStyle(Theme.muted3).lineSpacing(5)
            .frame(maxWidth: 520, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6).padding(.bottom, 20)

        SectionLabel(text: "工作区").padding(.bottom, 8)
        HStack(spacing: 10) {
            Text(model.vault?.displayPath ?? "未选择").font(.system(size: 12, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let v = model.vault {
                Text("\(v.notes.count) 篇笔记 · " + (v.isGitRepo ? "git 已启用" : "非 git 仓库"))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
            OutlineButton(title: "更换…", action: model.chooseVault)
            OutlineButton(title: "在 Finder 中显示", action: model.revealVault)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.cardLine))
        .padding(.bottom, 20)

        SectionLabel(text: "已检测到的 CLI").padding(.bottom, 8)
        HStack(alignment: .top, spacing: 10) {
            cliCard(.claude, on: model.claudeOn) { model.claudeOn.toggle() }
            cliCard(.codex, on: model.codexOn) { model.codexOn.toggle() }
        }
        .padding(.bottom, 20)

        SectionLabel(text: "衔接").padding(.bottom, 8)
        Card {
            ToggleRow(label: "AGENTS.md 与 CLAUDE.md 同源", desc: "CLAUDE.md 只包含 @AGENTS.md，两个 agent 读同一份规则。缺失时由 Plume 创建。",
                      on: model.syncContext, first: true) { model.syncContext.toggle() }
            ToggleRow(label: "监听终端会话", desc: "在库内运行的 claude / codex 会话出现在 Agent 面板，改动实时进入审阅",
                      on: model.watchTerminal) { model.watchTerminal.toggle() }
            ToggleRow(label: "Vault MCP 服务", desc: "向 agent 提供双链、标签与全文搜索（尚未实现）",
                      on: false, enabled: false) {}
            ToggleRow(label: "写入前 git 快照", desc: model.vault?.isGitRepo == false ? "库不是 git 仓库，快照不会生效。在库目录运行 git init 后启用。" : "每次 agent 写入前自动提交，任何改动都能一键还原",
                      on: model.gitSnapshot) { model.gitSnapshot.toggle() }
        }
        .padding(.bottom, 20)

        SectionLabel(text: "Agent 写入之后").padding(.bottom, 8)
        HStack(spacing: 0) {
            SegmentButton(label: "进入审阅队列", on: model.reviewMode == .queue) { model.reviewMode = .queue }
            SegmentButton(label: "直接接受", on: model.reviewMode == .auto) { model.reviewMode = .auto }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xEFECE8)))
    }

    private func cliCard(_ k: AgentKind, on: Bool, toggle: @escaping () -> Void) -> some View {
        let info = model.cli[k]
        let status: String = {
            guard let info else { return "检测中…" }
            guard info.found else { return "未在 PATH 中找到 \(k.executable)" }
            guard on else { return "已停用" }
            return "已启用 · 读取 " + (k == .claude ? "CLAUDE.md → AGENTS.md" : "AGENTS.md")
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Dot(color: k.color, size: 8)
                Text(k.displayName).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                PlumeSwitch(on: on && info?.found == true, enabled: info?.found == true, toggle: toggle)
            }
            Text((info?.path).map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "—")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted2).lineLimit(1).truncationMode(.middle)
            if let v = info?.version {
                Text(v).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted2).lineLimit(1)
            }
            Text(status).font(.system(size: 11.5)).foregroundStyle(Theme.muted3)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardLine))
    }
}

struct FontCards: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            ForEach(EditorFont.allCases) { f in
                let on = model.font == f
                Button { model.font = f } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("专注，是一种选择。").font(Font(f.nsFont(size: f == .mono ? 14 : 16))).foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(f.cardLabel).font(.system(size: 11.5)).foregroundStyle(Theme.muted2)
                    }
                    .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : Theme.cardLine, lineWidth: on ? 1.5 : 1))
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(on ? 0.12 : 0), lineWidth: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct EditorSettings: View {
    @Bindable var model: AppModel
    var body: some View {
        Text("编辑器").font(.system(size: 18, weight: .semibold)).padding(.bottom, 18)
        SectionLabel(text: "正文字体").padding(.bottom, 8)
        FontCards(model: model).padding(.bottom, 20)
        SectionLabel(text: "专注与输入").padding(.bottom, 8)
        Card {
            ToggleRow(label: "打字机滚动", desc: "当前行始终停在视线高度", on: model.typewriter, first: true) { model.typewriter.toggle() }
            ToggleRow(label: "段落聚焦", desc: "淡化正在编辑之外的段落", on: model.dim) { model.dim.toggle() }
            ToggleRow(label: "Tab 行内续写", desc: "停顿后由 claude（haiku）给出灰色建议，Tab 接受，继续输入即忽略。每次续写都会调用一次 claude，通常需要 5–15 秒。",
                      on: model.ghostOn, enabled: model.cli[.claude]?.found != false) { model.ghostOn.toggle() }
        }
    }
}

struct KeySettings: View {
    let rows = [("命令面板", "⌘K"), ("专注模式", "⌘."), ("侧边栏", "⌘\\"), ("Agent 面板", "⌘J"), ("新建笔记", "⌘N"),
                ("斜杠命令", "/"), ("接受续写", "Tab"), ("设置", "⌘,")]
    var body: some View {
        Text("快捷键").font(.system(size: 18, weight: .semibold)).padding(.bottom, 18)
        Card {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack {
                    Text(r.0).frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.1).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.text3)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: 0xE3E0DA)))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
            }
        }
    }
}

// MARK: - Onboarding

struct OnboardingOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        let step = model.onboardingStep ?? 0
        ZStack {
            Color(hex: 0x1E1C19, alpha: 0.3).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                switch step {
                case 0: stepVault
                case 1: stepAgents
                default: stepFeel
                }
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Capsule().fill(i == step ? Theme.dark : Color(hex: 0xD8D4CE)).frame(width: i == step ? 18 : 6, height: 6)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: step)
                    Spacer()
                    Button("跳过") { model.finishOnboarding() }
                        .buttonStyle(.plain).foregroundStyle(Theme.muted2).padding(.horizontal, 12).frame(height: 30)
                    if step > 0 {
                        OutlineButton(title: "上一步", height: 30, horizontal: 14, size: 13) { model.onboardingStep = step - 1 }
                    }
                    DarkButton(title: step == 2 ? "开始写作" : "继续", height: 30, horizontal: 16, weight: .medium) { next(step) }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 40).padding(.top, 36).padding(.bottom, 24)
            .frame(maxWidth: 600)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xFBFAF8)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.28), radius: 45, y: 30)
            .padding(24)
        }
    }

    private func next(_ step: Int) {
        if step == 0, model.vault == nil { model.openVault(AppModel.defaultVaultURL) }
        if step == 1, model.syncContext { model.ensureContextFiles() }
        if step == 2 { model.finishOnboarding() } else { model.onboardingStep = step + 1 }
    }

    private let title = Font(EditorFont.serif.nsFont(size: 26, weight: .semibold))

    @ViewBuilder private var stepVault: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("欢迎使用 Plume").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.bottom, 10)
            Text("你的笔记，就是一个文件夹。").font(title)
            Text("Plume 直接编辑磁盘上的 Markdown 文件——没有数据库，没有私有格式。Claude Code 和 Codex 也在同一个文件夹里工作，你们看到的永远是同一份文字。")
                .font(.system(size: 13.5)).foregroundStyle(Theme.text3).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        let v = model.vault
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).stroke(Theme.muted2, lineWidth: 1.4).frame(width: 16, height: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(v?.displayPath ?? (AppModel.defaultVaultURL.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Text(v.map { "\($0.notes.count) 篇笔记 · \($0.folders.count) 个文件夹 · " + ($0.isGitRepo ? "git 仓库" : "非 git 仓库") } ?? "将新建这个文件夹")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            OutlineButton(title: "更换…", height: 26, horizontal: 12, action: model.chooseVault)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardLine))
    }

    @ViewBuilder private var stepAgents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("2 / 3").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.bottom, 10)
            Text("让两个 agent 读同一份规则。").font(title)
            Text("Plume 在库根目录写入 AGENTS.md，CLAUDE.md 只引用它。无论你在 Plume 里还是终端里启动 agent，上下文都一致。")
                .font(.system(size: 13.5)).foregroundStyle(Theme.text3).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AgentKind.allCases, id: \.self) { k in
                    HStack(spacing: 8) {
                        Dot(color: k.color)
                        Text(k.executable).frame(maxWidth: .infinity, alignment: .leading)
                        switch model.cli[k]?.found {
                        case .some(true): Text("✓ 已检测").foregroundStyle(Theme.plus)
                        case .some(false): Text("未找到").foregroundStyle(Theme.minus)
                        case .none: Text("检测中…").foregroundStyle(Theme.muted)
                        }
                    }
                }
                Text("终端里在库内运行的会话会自动出现在 Agent 面板。")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardLine))

            Text(treePreview)
                .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.text3).lineSpacing(5)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardLine))
        }
    }

    private var treePreview: String {
        let name = model.vault?.name ?? "Vault"
        let folders = (model.vault?.folders ?? []).filter { !$0.contains("/") }.prefix(3)
        var lines = [name + "/", "├─ AGENTS.md", "├─ CLAUDE.md  → @AGENTS.md"]
        for (i, f) in folders.enumerated() { lines.append((i == folders.count - 1 ? "└─ " : "├─ ") + f + "/") }
        if folders.isEmpty { lines[2] = "└─ CLAUDE.md  → @AGENTS.md" }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder private var stepFeel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("3 / 3").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.bottom, 10)
            Text("选一种写字的感觉。").font(title)
        }
        FontCards(model: model)
        Card {
            ToggleRow(label: "打字机滚动", desc: "当前行始终停在视线高度", on: model.typewriter, first: true) { model.typewriter.toggle() }
            ToggleRow(label: "段落聚焦", desc: "淡化正在编辑之外的段落", on: model.dim) { model.dim.toggle() }
        }
    }
}
