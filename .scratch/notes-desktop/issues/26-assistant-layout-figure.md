# 26: 助手栏布局与助手形象

**What to build:** 主窗口右侧有可开关的助手栏，左侧导航随窗口宽度换档为它让位；助手形象按状态在实体与粒子之间连续变形；尚未检测到 Agent 时显示安装指引。

**Blocked by:** 03, 17

**Status:** ready-for-agent

**Progress:** in-progress

- [x] 助手栏停靠在右侧，⌘J / Ctrl+J 开关，栏宽无回弹过渡；不使用浮动面板
- [x] 助手栏打开时：≥ 1180px 双栏、960–1180px 单栏、< 960px 图标栏；收起助手栏不重排左侧导航
- [ ] 专注模式下助手栏仍停靠，卡片铺满其余空间
- [x] 助手形象：扁平单色正圆、圆角方块眼与细嘴、环绕粒子；九种状态与粒子融合按设计规范；同一时间只显示一个
- [x] 检测本机 Claude Code、Codex、DeepSeek Harness、Pi；一个都没有时显示安装指引

## Comments

### 2026-10-20 实施记录

分支 `ticket/26-assistant-layout`：`3b72681` 核心库检测 Agent、`b88b4ab` 助手形象状态模型、`70c2d49` 助手栏/形象/安装指引/导航档位、`4e39279` 档位测试、`e5dc8b5` 形象静止帧测试、`178fcc4` 测试等待窗口最后一次 resize。

本地验证（macOS）：`npm run typecheck` 通过；`npm test` 117 通过 1 跳过（新增 `tests/core/agents.test.ts` 6 个，Windows 的 PATHEXT 用例在 macOS 跳过；`tests/core/assistant-figure.test.ts` 7 个：九种状态的形态、临界阻尼融合约 0.8s 无过冲、五官在 72% 后淡入、48/22px 尺寸取值）；`npm run test:e2e` 新增 `tests/e2e/assistant.spec.ts` 5 个：⌘J 开关、栏宽 0.26s cubic-bezier 过渡且停靠右缘 340px、卡片相应变窄、同时只有一个形象；无 Agent 时显示安装指引，装入假 `claude`/`codex` 后“重新检测”出现 Agent 切换；1200→1100→900 宽度下双栏/单栏/图标栏，“展开导航”与图标栏搜索恢复单栏，收起助手栏不重排、调整窗口才重排（做过变异检查）；设置为单栏时始终单栏；形象为 #1d1d1f 实体且持续在动，减弱动态效果下静止且栏宽不过渡（做过变异检查）。CI 未运行。

实施中的决定：
- 检测：核心库 `detectAgents({ path, pathext })` 按 PATH 顺序找 `claude`、`codex`、`dsh`、`pi`（Windows 按 PATHEXT），取第一个。主进程在 PATH 之后追加安装器常用目录（`~/.local/bin`、`~/.claude/local`、`/opt/homebrew/bin`、`/usr/local/bin`、`~/.npm-global/bin`、`~/.bun/bin`、`~/.volta/bin`；Windows `%APPDATA%\npm`），因为从 Finder 打开的应用拿不到终端的 PATH。`NOTES_DESKTOP_AGENT_PATH` 替换整个搜索路径（测试用，e2e 夹具默认指向 `scratch/agents`）。每次打开助手栏或点“重新检测”时重新检测。
- 导航档位：`navigationTier.ts`，只在打开助手栏、窗口 resize、导航设置变化时确定；收起不重排。设置为单栏时宽窗仍为单栏，< 960px 仍收为图标栏。图标栏：展开导航、搜索（展开为单栏并就地搜索）、切换笔记库。
- 助手栏始终在 DOM 中，宽度 0 ↔ 340/300px 以 `--assistant-toggle`（0.26s cubic-bezier(0.32,0.72,0,1)）过渡，内容定宽不重排；关闭后 visibility hidden、inert。形象只渲染一个：打开时在栏顶 48px，收起时在卡片顶部栏右端 22px 开关内。
- 形象用 canvas 绘制（`AssistantFigure.tsx`），状态模型与尺寸在 `figureModel.ts`。颜色变量 `--figure-ink/eye/error`。当前状态恒为“待命”，由任务 28 的一轮对话驱动。
- 安装指引给出 Claude Code、Codex、Pi 的 npm 安装命令；DeepSeek Harness 只列命令 `dsh`（安装方式未核实）。

留给后续任务：
- 专注模式下助手栏仍停靠：专注模式（任务 14）尚未实现；布局上助手栏是独立的一栏，任务 14 只需让卡片铺满时保留 `.assistant`。
- 形象的状态驱动、完成后回到待命、对话内容与输入框：任务 28；每种 Agent 的安装方式与适配：任务 30（含核实 `dsh` 安装命令；登录 shell 的 PATH 如 nvm 目录也可在 28 启动 Agent 时一并处理）。
- 形象与栏宽过渡的观感、常驻 rAF 动画的耗电：任务 23 动效审查。

