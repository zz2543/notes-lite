import PlumeCore
import SwiftUI

// MARK: - Command palette (⌘K)

struct PaletteEntry: Identifiable {
    let id: String
    let label: String
    let hint: String
    let icon: String
    let run: () -> Void
}

struct CommandPalette: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    private var entries: [PaletteEntry] {
        let m = model
        var cmds: [PaletteEntry] = [
            .init(id: "new", label: "新建笔记", hint: "⌘N", icon: "square.and.pencil", run: m.newNote),
            .init(id: "zen", label: m.zen ? "退出专注模式" : "进入专注模式", hint: "⌘.", icon: "arrow.up.left.and.arrow.down.right", run: m.toggleZen),
            .init(id: "tw", label: "打字机滚动：" + (m.typewriter ? "关闭" : "开启"), hint: "", icon: "text.aligncenter") { m.typewriter.toggle() },
            .init(id: "dim", label: "段落聚焦：" + (m.dim ? "关闭" : "开启"), hint: "", icon: "text.line.first.and.arrowtriangle.forward") { m.dim.toggle() },
            .init(id: "font", label: "切换字体：衬线 / 无衬线 / 等宽", hint: m.font.shortLabel, icon: "textformat") { m.font = m.font.next },
            .init(id: "sum", label: "让 Claude Code 总结当前笔记", hint: "Agent", icon: "sparkle") { m.runAgent(prompt: "总结这篇笔记，在开头加一段摘要", agent: .claude) },
            .init(id: "todo", label: "让 Codex 整理当前笔记的待办", hint: "Agent", icon: "terminal") { m.runAgent(prompt: "整理这篇笔记的待办，合并重复项", agent: .codex) },
        ]
        if !m.pending.isEmpty {
            cmds.append(.init(id: "review", label: "审阅待定改动（\(m.pending.count)）", hint: "⇧⌘R", icon: "checklist", run: m.reviewNext))
        }
        cmds += [
            .init(id: "settings", label: "Agent 与 CLI 设置", hint: "⌘,", icon: "gearshape") { m.openSettings(.agent) },
            .init(id: "vault", label: "打开其他库…", hint: "⌘O", icon: "folder", run: m.chooseVault),
            .init(id: "ob", label: "重新运行新手引导", hint: "", icon: "hand.wave") { m.onboardingStep = 0 },
        ]
        let notes = (m.vault?.notes ?? []).map { n in
            PaletteEntry(id: "n:" + n.rel, label: n.displayName, hint: n.folder, icon: n.isAgentFile ? "doc.badge.gearshape" : "doc.text") {
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
            Color.black.opacity(0.08)
                .contentShape(Rectangle())
                .onTapGesture { model.palette = false }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                    TextField("搜索笔记，或输入命令", text: $model.paletteQuery)
                        .textFieldStyle(.plain)
                        .font(.title2)
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
                .padding(.horizontal, 16).padding(.vertical, 14)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                                let on = i == sel
                                HStack(spacing: 10) {
                                    Image(systemName: e.icon).frame(width: 20).foregroundStyle(on ? .white : .secondary)
                                    Text(e.label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(e.hint).font(.caption).foregroundStyle(on ? .white.opacity(0.8) : .secondary)
                                }
                                .foregroundStyle(on ? .white : .primary)
                                .padding(.horizontal, 10).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : .clear))
                                .contentShape(Rectangle())
                                .id(i)
                                .onHover { if $0 { model.paletteSel = i } }
                                .onTapGesture { model.palette = false; e.run() }
                            }
                            if list.isEmpty {
                                Text("没有匹配项 · ↩ 新建「\(model.paletteQuery)」")
                                    .foregroundStyle(.secondary).padding(16)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: model.paletteSel) { _, v in proxy.scrollTo(v) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 580)
            .plumeControlGlass(in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 16)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
    }

    private func move(_ d: Int, _ n: Int) {
        guard n > 0 else { return }
        model.paletteSel = (min(model.paletteSel, n - 1) + d + n) % n
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            EditorSettings(model: model)
                .tabItem { Label("编辑器", systemImage: "textformat") }
                .tag(SettingsTab.editor)
            AgentSettings(model: model)
                .tabItem { Label("Agent", systemImage: "sparkles") }
                .tag(SettingsTab.agent)
            KeySettings()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
                .tag(SettingsTab.keys)
        }
        .frame(width: 580)
        .scenePadding()
    }
}

struct FontPicker: View {
    @Bindable var model: AppModel
    var body: some View {
        Picker("正文字体", selection: $model.font) {
            ForEach(EditorFont.allCases) { f in
                Text(f.cardLabel).tag(f)
            }
        }
        LabeledContent("预览") {
            Text("专注，是一种选择。Focus is a choice.")
                .font(Font(model.font.nsFont(size: 16)))
        }
    }
}

struct EditorSettings: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section { FontPicker(model: model) }
            Section("专注与输入") {
                Toggle(isOn: $model.typewriter) {
                    Text("打字机滚动")
                    Text("当前行始终停在视线高度")
                }
                Toggle(isOn: $model.dim) {
                    Text("段落聚焦")
                    Text("淡化正在编辑之外的段落")
                }
                Toggle(isOn: $model.ghostOn) {
                    Text("Tab 行内续写")
                    Text("停顿后由 claude（haiku）给出灰色建议，Tab 接受。每次续写都会调用一次 claude，通常需要 5–15 秒。")
                }
                .disabled(model.cli[.claude]?.found == false)
            }
        }
        .formStyle(.grouped)
    }
}

struct AgentSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("位置") {
                    Text(model.vault?.displayPath ?? "未选择").lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                if let v = model.vault {
                    LabeledContent("笔记", value: "\(v.notes.count) 篇 · \(v.folders.count) 个文件夹")
                    LabeledContent("Git", value: v.isGitRepo ? "已启用" : "不是 git 仓库")
                }
                HStack {
                    Spacer()
                    Button("在 Finder 中显示", action: model.revealVault).disabled(model.vault == nil)
                    Button("更换库…", action: model.chooseVault)
                }
            } header: {
                Text("库")
            } footer: {
                Text("Plume 不托管模型。库就是磁盘上的一个文件夹，Claude Code 和 Codex 在里面直接读写 .md；Plume 负责看见、审阅和还原每一次改动。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("命令行工具") {
                cliRow(.claude, on: $model.claudeOn)
                cliRow(.codex, on: $model.codexOn)
            }

            Section("衔接") {
                Toggle(isOn: $model.syncContext) {
                    Text("AGENTS.md 与 CLAUDE.md 同源")
                    Text("CLAUDE.md 只包含 @AGENTS.md，两个 agent 读同一份规则。缺失时由 Plume 创建。")
                }
                Toggle(isOn: $model.watchTerminal) {
                    Text("监听终端会话")
                    Text("在库内运行的 claude / codex 会话出现在 Agent 面板，它们的改动进入审阅。")
                }
                Toggle(isOn: $model.gitSnapshot) {
                    Text("写入前 git 快照")
                    Text(model.vault?.isGitRepo == false ? "库不是 git 仓库，快照不会生效。在库目录运行 git init 后即可使用。" : "每次 agent 写入前自动提交，任何改动都能找回。")
                }
            }

            Section("Agent 写入之后") {
                Picker("改动", selection: $model.reviewMode) {
                    Text("进入审阅队列").tag(ReviewMode.queue)
                    Text("直接接受").tag(ReviewMode.auto)
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }

    private func cliRow(_ k: AgentKind, on: Binding<Bool>) -> some View {
        let info = model.cli[k]
        return Toggle(isOn: Binding(get: { on.wrappedValue && info?.found == true }, set: { on.wrappedValue = $0 })) {
            Label {
                Text(k.displayName)
                if let info {
                    if let p = info.path {
                        Text(((p as NSString).abbreviatingWithTildeInPath) + (info.version.map { " · " + $0 } ?? ""))
                    } else {
                        Text("没有在 PATH 中找到 \(k.executable)")
                    }
                } else {
                    Text("检测中…")
                }
            } icon: {
                Image(systemName: k == .claude ? "sparkle" : "terminal").foregroundStyle(Theme.agentColor(k))
            }
        }
        .disabled(info?.found != true)
    }
}

struct KeySettings: View {
    let rows = [("命令面板", "⌘K"), ("专注模式", "⌘."), ("显示/隐藏侧边栏", "⌃⌘S"), ("Agent 面板", "⌘J"), ("新建笔记", "⌘N"),
                ("打开库", "⌘O"), ("审阅改动", "⇧⌘R"), ("斜杠命令", "/"), ("接受续写", "Tab"), ("设置", "⌘,")]
    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.0) { r in
                    LabeledContent(r.0) { Text(r.1).font(.body.monospaced()).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Onboarding sheet

struct OnboardingSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        let step = model.onboardingStep ?? 0
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0: stepVault
            case 1: stepAgents
            default: stepFeel
            }
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle().fill(i == step ? Color.primary : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                    }
                }
                Spacer()
                Button("跳过") { model.finishOnboarding() }.buttonStyle(.borderless)
                if step > 0 { Button("上一步") { model.onboardingStep = step - 1 } }
                Button(step == 2 ? "开始写作" : "继续") { next(step) }
                    .plumePrimaryButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540, height: 420)
    }

    private func next(_ step: Int) {
        if step == 0, model.vault == nil { model.openVault(AppModel.defaultVaultURL) }
        if step == 1, model.syncContext { model.ensureContextFiles() }
        if step == 2 { model.finishOnboarding() } else { model.onboardingStep = step + 1 }
    }

    private func header(_ icon: String, _ kicker: String, _ title: String, _ body: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.tint).padding(.bottom, 4)
            Text(kicker).font(.caption).foregroundStyle(.secondary)
            Text(title).font(.title.weight(.semibold))
            if let body {
                Text(body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var stepVault: some View {
        header("folder", "欢迎使用 Plume", "你的笔记，就是一个文件夹。",
               "Plume 直接编辑磁盘上的 Markdown 文件——没有数据库，没有私有格式。Claude Code 和 Codex 也在同一个文件夹里工作，你们看到的永远是同一份文字。")
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    let v = model.vault
                    Text(v?.displayPath ?? (AppModel.defaultVaultURL.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                    Text(v.map { "\($0.notes.count) 篇笔记 · \($0.folders.count) 个文件夹 · " + ($0.isGitRepo ? "git 仓库" : "非 git 仓库") } ?? "将新建这个文件夹")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("更换…", action: model.chooseVault)
            }
            .padding(4)
        }
    }

    @ViewBuilder private var stepAgents: some View {
        header("person.2", "2 / 3", "让两个 agent 读同一份规则。",
               "Plume 在库根目录写入 AGENTS.md，CLAUDE.md 只引用它。无论你在 Plume 里还是终端里启动 agent，上下文都一致。")
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AgentKind.allCases, id: \.self) { k in
                    HStack {
                        Label(k.executable, systemImage: k == .claude ? "sparkle" : "terminal")
                        Spacer()
                        switch model.cli[k]?.found {
                        case .some(true): Label("已检测", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .some(false): Label("未找到", systemImage: "xmark.circle").foregroundStyle(.secondary)
                        case .none: ProgressView().controlSize(.small)
                        }
                    }
                }
                Divider()
                Text("终端里在库内运行的会话会自动出现在 Agent 面板。").font(.caption).foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    @ViewBuilder private var stepFeel: some View {
        header("textformat", "3 / 3", "选一种写字的感觉。", nil)
        Form {
            FontPicker(model: model)
            Toggle("打字机滚动", isOn: $model.typewriter)
            Toggle("段落聚焦", isOn: $model.dim)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding(-20)
    }
}
