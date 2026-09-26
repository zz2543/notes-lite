import TwainCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            Tab("编辑器", systemImage: "textformat", value: SettingsTab.editor) {
                EditorSettings(model: model)
            }
            Tab("Agent", systemImage: "sparkles", value: SettingsTab.agent) {
                AgentSettings(model: model)
            }
            Tab("快捷键", systemImage: "keyboard", value: SettingsTab.keys) {
                KeySettings()
            }
        }
        .frame(width: 600)
        .frame(minHeight: 460)
    }
}

/// Three cards that show each typeface in use instead of naming it.
struct FontCards: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(EditorFont.allCases) { f in
                let on = model.font == f
                Button { model.font = f } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aa 文")
                            .font(f.swiftUIFont(size: 24))
                        Text(f.cardLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.fill.quinary, in: .rect(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: on ? 2 : 0.5)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct EditorSettings: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section("正文字体") {
                FontCards(model: model)
                Text("专注，是一种选择。Focus is a choice.")
                    .font(model.font.swiftUIFont(size: 16))
                    .foregroundStyle(.secondary)
            }
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
    @State private var toolState = TwainTool.installState
    @State private var toolError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("位置") {
                    Text(model.vault?.displayPath ?? "未选择").lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                if let v = model.vault {
                    LabeledContent("笔记", value: "\(v.notes.count) 篇 · \(v.folders.count) 个文件夹")
                    LabeledContent("Git") {
                        Label(v.isGitRepo ? "已启用" : "不是 git 仓库",
                              systemImage: v.isGitRepo ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(v.isGitRepo ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    }
                }
                HStack {
                    Spacer()
                    Button("在 Finder 中显示", action: model.revealVault).disabled(model.vault == nil)
                    Button("更换库…", action: model.chooseVault)
                }
            } header: {
                Text("库")
            } footer: {
                Text("共笔不托管模型。库就是磁盘上的一个文件夹，Claude Code 和 Codex 在里面直接读写 .md；共笔负责看见、审阅和还原每一次改动。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("命令行工具") {
                cliRow(.claude, on: $model.claudeOn)
                cliRow(.codex, on: $model.codexOn)
            }

            Section {
                LabeledContent("连接") {
                    Label(model.server != nil ? "正在监听" : "未监听（可能已有另一个共笔在运行）",
                          systemImage: model.server != nil ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.server != nil ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                }
                LabeledContent("终端中使用") {
                    HStack {
                        switch toolState {
                        case .installed:
                            Text("~/.local/bin/twain").foregroundStyle(.secondary)
                            Button("移除") { TwainTool.uninstall(); toolState = TwainTool.installState }
                        case .missing:
                            Button("安装 twain 命令") {
                                do { try TwainTool.install(); toolError = nil } catch { toolError = "安装失败：\(error.localizedDescription)" }
                                toolState = TwainTool.installState
                            }
                        case let .other(path):
                            Text("~/.local/bin/twain 已被占用：\((path as NSString).abbreviatingWithTildeInPath)")
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                if let toolError { Text(toolError).font(.caption).foregroundStyle(.red) }
                Toggle(isOn: $model.mcpOn) {
                    Text("给 agent 挂载共笔工具（MCP）")
                    Text("共笔启动的 Claude Code 和 Codex 可以直接调用 propose_edit、ask_user 等工具：修改附理由、拿不准时向你提问。关闭后只能通过 twain 命令使用。")
                }
            } header: {
                Text("twain 命令")
            } footer: {
                Text("共笔启动的 agent 自动就能用 twain 查询当前笔记、选区、反链和待办。安装后，在终端里运行的 agent 也能用。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if model.userCommands.isEmpty {
                    Text("没有自定义命令").foregroundStyle(.secondary)
                }
                ForEach(model.userCommands, id: \.key) { c in
                    LabeledContent {
                        Text("/" + c.key).font(.callout.monospaced()).foregroundStyle(.secondary)
                    } label: {
                        Label {
                            Text(c.title)
                            Text("\(c.agent.displayName) · " + ["selection": "作用于选区", "note": "作用于当前笔记", "vault": "作用于整个库"][c.scope.rawValue, default: ""])
                        } icon: {
                            Image(systemName: c.icon).foregroundStyle(Theme.agentColor(c.agent))
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("打开命令文件夹") { reveal(".twain/commands") }.disabled(model.vault == nil)
                }
            } header: {
                Text("自定义命令")
            } footer: {
                Text("库里 .twain/commands/ 下的每个 .md 文件是一条命令，出现在 ⌘K、斜杠菜单和 Agent 菜单里；agent 也能用 run_command 调用。文件开头写 title、agent、scope，正文是提示词，可用 {{selection}} {{note}} {{path}} {{line}} {{date}}。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("允许自动化运行", isOn: $model.automationsOn)
                LabeledContent("每天最多") {
                    Stepper("\(model.automationDailyLimit) 次（今天已运行 \(model.automationRunsToday) 次）",
                            value: $model.automationDailyLimit, in: 1...200)
                        .id(model.tick)
                }
                if model.automations.isEmpty {
                    Text("没有自动化。把 .twain/automations/ 里的示例文件去掉 .example 后缀即可试用。").foregroundStyle(.secondary)
                }
                ForEach(model.automations, id: \.id) { a in
                    Toggle(isOn: Binding(get: { model.isApproved(a) }, set: { model.setApproved(a, $0) })) {
                        Text(a.title)
                        Text("\(a.on.joined(separator: "、"))" + (a.match.map { " · \($0)" } ?? " · 所有笔记")
                             + " · 静默 \(a.debounce) 秒后由 \(a.agent.displayName) 运行")
                    }
                    .id("\(a.id)-\(model.tick)")
                }
                HStack {
                    Spacer()
                    Button("打开自动化文件夹") { reveal(".twain/automations") }.disabled(model.vault == nil)
                }
            } header: {
                Text("自动化")
            } footer: {
                Text("自动化在库里发生某件事（例如保存收件箱）后自动运行。它只能提交修改提案，不能直接改文件，每处改动都要你审阅。每条自动化需要你在这里启用；文件内容一旦变化（包括随 git 拉取的改动），需要重新启用。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(AgentKind.allCases, id: \.self) { modelRow($0) }
            } header: {
                Text("模型")
            } footer: {
                Text("选“默认”时沿用 CLI 自己的配置。也可以填写完整的模型名，例如 claude-opus-5-5。切换后，已有会话继续时会换用新模型。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("衔接") {
                Toggle(isOn: $model.syncContext) {
                    Text("AGENTS.md 与 CLAUDE.md 同源")
                    Text("CLAUDE.md 只包含 @AGENTS.md，两个 agent 读同一份规则。缺失时由共笔创建。")
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

    private func modelRow(_ k: AgentKind) -> some View {
        let binding = Binding(get: { model.agentModel[k] ?? "" },
                              set: { model.agentModel[k] = $0.trimmingCharacters(in: .whitespaces) })
        return LabeledContent {
            HStack(spacing: 8) {
                TextField("模型名", text: binding, prompt: Text(model.modelName("", for: k)))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: 170)
                Menu {
                    Picker("模型", selection: binding) {
                        ForEach(AgentBar.options(model, k), id: \.self) { id in
                            Text(model.modelName(id, for: k)).tag(id)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } label: {
            Label(k.displayName, systemImage: Theme.agentSymbol(k))
        }
    }

    private func reveal(_ rel: String) {
        guard let v = model.vault else { return }
        let u = v.root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        NSWorkspace.shared.open(u)
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
                Image(systemName: Theme.agentSymbol(k)).foregroundStyle(Theme.agentColor(k))
            }
        }
        .disabled(info?.found != true)
    }
}

struct KeySettings: View {
    let groups: [(String, [(String, String)])] = [
        ("窗口", [("命令面板", "⌘K"), ("专注模式", "⌘."), ("显示/隐藏边栏", "⌃⌘S"), ("Agent 面板", "⌘J"), ("设置", "⌘,")]),
        ("笔记", [("新建笔记", "⌘N"), ("打开库", "⌘O"), ("审阅改动", "⇧⌘R")]),
        ("编辑器", [("斜杠命令", "/"), ("接受续写", "Tab")]),
    ]
    var body: some View {
        Form {
            ForEach(groups, id: \.0) { g in
                Section(g.0) {
                    ForEach(g.1, id: \.0) { r in
                        LabeledContent(r.0) {
                            Text(r.1)
                                .font(.body.monospaced())
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(.fill.tertiary, in: .rect(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
