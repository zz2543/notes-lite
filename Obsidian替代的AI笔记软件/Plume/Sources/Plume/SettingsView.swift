import PlumeCore
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
