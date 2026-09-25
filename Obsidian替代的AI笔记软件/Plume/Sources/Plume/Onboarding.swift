import PlumeCore
import SwiftUI

/// First-run sheet: where the vault lives, how the agents share rules, how writing feels.
struct OnboardingSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        let step = model.onboardingStep ?? 0
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: stepVault
                case 1: stepAgents
                default: stepFeel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: i == step ? 18 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: step)
                Spacer()
                Button("跳过") { model.finishOnboarding() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                if step > 0 {
                    Button("上一步") { withAnimation(.snappy) { model.onboardingStep = step - 1 } }
                        .buttonStyle(.glass)
                }
                Button(step == 2 ? "开始写作" : "继续") { next(step) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(32)
        .frame(width: 560, height: 500)
    }

    private func next(_ step: Int) {
        if step == 0, model.vault == nil { model.openVault(AppModel.defaultVaultURL) }
        if step == 1, model.syncContext { model.ensureContextFiles() }
        if step == 2 { model.finishOnboarding() } else { withAnimation(.snappy) { model.onboardingStep = step + 1 } }
    }

    private func header(_ icon: String, _ kicker: String, _ title: String, _ body: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)
                .glassEffect(.regular.tint(.accentColor.opacity(0.14)), in: .rect(cornerRadius: 18, style: .continuous))
                .padding(.bottom, 6)
            Text(kicker).font(.subheadline).foregroundStyle(.secondary)
            Text(title).font(.largeTitle.weight(.semibold))
            if let body {
                Text(body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var stepVault: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("folder", "欢迎使用 Plume", "你的笔记，就是一个文件夹。",
                   "Plume 直接编辑磁盘上的 Markdown 文件——没有数据库，没有私有格式。Claude Code 和 Codex 也在同一个文件夹里工作，你们看到的永远是同一份文字。")
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    let v = model.vault
                    Text(v?.displayPath ?? (AppModel.defaultVaultURL.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                    Text(v.map { "\($0.notes.count) 篇笔记 · \($0.folders.count) 个文件夹 · " + ($0.isGitRepo ? "git 仓库" : "非 git 仓库") } ?? "将新建这个文件夹")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("更换…", action: model.chooseVault)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
            .padding(14)
            .contentCard(radius: Metrics.cardRadius)
        }
    }

    @ViewBuilder private var stepAgents: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("person.2", "2 / 3", "让两个 agent 读同一份规则。",
                   "Plume 在库根目录写入 AGENTS.md，CLAUDE.md 只引用它。无论你在 Plume 里还是终端里启动 agent，上下文都一致。")
            VStack(spacing: 0) {
                ForEach(Array(AgentKind.allCases.enumerated()), id: \.element) { i, k in
                    if i > 0 { Divider().padding(.leading, 44) }
                    HStack(spacing: 12) {
                        Image(systemName: Theme.agentSymbol(k))
                            .foregroundStyle(Theme.agentColor(k))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(k.displayName)
                            Text(model.cli[k]?.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? k.executable)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        switch model.cli[k]?.found {
                        case .some(true): Label("已检测", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .some(false): Label("未找到", systemImage: "xmark.circle").foregroundStyle(.secondary)
                        case .none: ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
            }
            .contentCard(radius: Metrics.cardRadius)
            Label("终端里在库内运行的会话会自动出现在 Agent 面板。", systemImage: "apple.terminal")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var stepFeel: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("textformat", "3 / 3", "选一种写字的感觉。", nil)
            FontCards(model: model)
            VStack(spacing: 0) {
                Toggle(isOn: $model.typewriter) {
                    Text("打字机滚动")
                    Text("当前行始终停在视线高度").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Divider().padding(.leading, 14)
                Toggle(isOn: $model.dim) {
                    Text("段落聚焦")
                    Text("淡化正在编辑之外的段落").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .toggleStyle(.switch)
            .contentCard(radius: Metrics.cardRadius)
        }
    }
}
