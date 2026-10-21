# 30: 其余 Agent 与对话历史

**What to build:** 可以在助手栏切换 Codex、DeepSeek Harness、Pi，并回看、继续以前的对话；助手编写空间主页时遵循编写说明。

**Blocked by:** 28

**Status:** ready-for-agent

**Progress:** completed

- [x] Codex、DeepSeek Harness、Pi 的适配层与完全权限启动，逐一核实输出与恢复方式
- [x] 对话历史列表，继续以前的对话沿用其 Agent 与工作目录
- [x] 让助手写空间主页时把编写说明作为上下文
- [x] 假 Agent 覆盖各适配层的输入输出

## Comments

### 2026-10-20 用户试用反馈

选了尚未适配的 Agent（如 Codex）时，要等发出消息后才提示“这个 Agent 还不能在助手栏里使用”，助手形象随之变红。本任务一并改为：选择 Agent 时就标出或禁用尚未支持的 Agent，不让用户发出注定失败的消息。另：用户机器上未安装 `claude` 命令行，只有 Claude 桌面 App 内部的 `claude-code-vm` 副本，检测不应使用它。

### 2026-10-21 实施记录（Notion AI）

分支 `notion/30-more-agents-history`（从 `feat/notes-desktop` 408dd0d 拉出，与任务 29 的 PR 互不依赖）。按用户选择的方案 A：适配层依据各 Agent 的文档、源码与 `--help` 实现，并在沙箱里安装真实命令行、接本地假模型服务逐一核实；接缝 B 的假 Agent 覆盖各适配层的输入输出；**接真实模型的真机验证留待人工验收**。

- 适配层（`src/core/agentStream.ts`，每种 Agent 一个 `AgentAdapter`：启动参数、可选环境变量、逐行解析、段落拼接）：
  - **Codex**（核实版本 0.163.0）：`codex exec --json --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox -`，提示词走 stdin；续对话 `codex exec resume --json … <thread_id> -`（核实续上的是同一 thread）。解析 `thread.started`、`item.started/completed`（`command_execution` → 运行命令，去掉 `/bin/bash -lc '…'` 外壳；`file_change` → 写入；`web_search` → 搜索；`mcp_tool_call` → 思考）、`agent_message`（整段文字，段间空一行）、`turn.failed`。顶层 `error` 是“重连中”之类的提示，不当作失败。
  - **DeepSeek Harness**（`dsh`，核实版本 0.2.1-rc.2）：`dsh --profile headless --json [--session-id <id>] -`。完全权限要靠环境变量 `DSH_PERMISSION_MODE=danger-full-access`：默认的 workspace-write 沙箱会**静默**拦下工作目录外的写入（已核实）。解析 `session`、`text`、`tool_call`/`tool_result`（bash→运行命令，read→读取，write/edit→写入，glob/grep/web_search/web_fetch→搜索）、`final`、`status` 的 `turn_end`（`reason.kind` 不是 `completed` 即为失败）、`error`（如找不到要续的对话，退出码 1）。续对话核实历史确实带进了模型请求（按工作目录认领对话）。
  - **Pi**（`@earendil-works/pi-coding-agent`，核实版本 1.3.0）：`pi --mode json`，提示词走 stdin；续对话 `--session <id>`（核实历史带进了模型请求）。Pi 没有授权系统，本身即完全权限；JSON 模式下项目信任默认跳过，不传 `--approve`。解析 `session` 头、`message_update` 的 `text_delta`（流式）、`tool_execution_start/end`、`message_end` 的 `stopReason: "error"`。**模型失败时 Pi 仍以 0 退出**，所以以 `stopReason` 判断失败。
  - 核实方式：三种命令行都装在沙箱，分别接本地假模型服务（Codex 用自定义 provider 的 Responses 接口，Pi 用 `models.json` 的 openai-completions，DSH 用 `DEEPSEEK_BASE_URL` 的 Anthropic Messages 流），让它们真的运行命令、写文件、续对话、失败，录下的输出存为 `tests/core/agentOutput/*.jsonl` 作解析测试的样本。没有调用任何付费服务。
- 选择 Agent：四种都已支持，“这个 Agent 还不能在助手栏里使用”的分支删除，选择器列出所有已安装的 Agent，不会再发出注定失败的消息。安装说明补上 `npm install -g @deepseek-ai/dsh`；Pi 的包已改名，改为 `@earendil-works/pi-coding-agent`（旧包 `@mariozechner/pi-coding-agent` 在 npm 上已标为弃用）。
- 检测（`src/core/agents.ts`）：路径或真实路径（跟随符号链接）中有 `claude-code-vm` 一段的，视为 Claude 桌面 App 自带的副本，跳过并继续往后找。
- 对话历史：对话保存时记下 `updated`；`ConversationStore.list(root)` 列出该笔记库的对话（标题取第一条消息的首行，按最近使用排序，读不了的文件跳过）；`AssistantTurns.history/open`，经 IPC `assistant:conversations`、`assistant:open-conversation` 给页面。助手栏顶栏左侧“对话历史”按钮（一轮进行中不可用）在消息区位置展开列表：标题，下面是“Agent · 工作目录 · 时间”，当前对话高亮；点开后显示该对话，继续时沿用它的 Agent 与工作目录（与当前选中的位置和 Agent 切换无关）。Agent 的对话 id 一收到就存盘，一轮进行中退出应用也能续上；该轮再打开时显示为“已停止。”，不声称有无改动。对话所用的 Agent 已卸载时，仍可回看，但提示“这个对话用的 X 没有安装，不能继续。”并禁用发送。
- 空间主页的编写说明：**决定**每一轮只要笔记库里有空间，就在提示词末尾附上编写说明的位置（先确保已安装最新版）和各空间文件，并标出当前打开的空间——用户在哪里提出“改一下健身主页”都能让 Agent 先读编写说明；没有空间的笔记库不附。路径相对于工作目录，与附带的笔记一致。界面上不另加标记。
- 假 Agent（`tests/support/fakeAgentProgram.mjs`）：按安装时的命令（claude/codex/dsh/pi）说对应 Agent 的输出格式与续对话参数；Pi 失败时以 0 退出、DSH 失败时 `turn_end` 报错并以 1 退出；记录 `DSH_PERMISSION_MODE`。

证据：`npm run typecheck` 通过；`npm test` 216 通过 / 3 跳过 / 4 失败——这 4 项（library/migration/organize/search 中依赖 chmod 拒绝读写的用例）在沙箱以 root 运行时必然失败，基线 408dd0d 上同样失败，与本任务无关。新增/扩充：`tests/core/agentStream.test.ts` 12 项（三种 Agent 的启动参数、续对话参数、DSH 环境变量、按真实样本解析、失败映射）；`tests/core/turns.test.ts` 用假 Codex/DSH/Pi 各跑一轮（完全权限参数、工作目录、stdin、流式文字与工具、改动记入操作记录）、续对话、失败原因，以及空间编写说明 3 项；`tests/core/agents.test.ts` 跳过 `claude-code-vm` 副本 2 项；`tests/core/conversationHistory.test.ts` 4 项（含对话 id 立即存盘与退出中断的一轮）；`tests/core/assistantTurns.test.ts` 打开空间时的提示词 1 项。新增 `tests/e2e/assistant-agents.spec.ts` 3 项：假 Codex/DSH/Pi 依次选用、发送、续对话；对话历史列出、重启后打开并在原 Agent 与工作目录下继续、Agent 卸载后只能回看；打开空间时提示词带编写说明与当前空间。

`npm run test:e2e` 全量 92 项：86 通过，6 项失败均为沙箱环境原因（系统强调色 2 项、chmod 拒绝写入 2 项、外部删除提示 1 项、空间刷新 1 项），基线 408dd0d 上同样失败，与本任务无关；助手相关 12 项全部通过。

代码审查（两个子代理，基点 408dd0d）：
- 规范：必须修复 1 项——e2e 用了 CSS 类名定位，已改为按角色/文字。建议项已处理：失败兜底文案抽成常量、三处工具事件合成 `toolEvent`、`open_`/`nameOf`/`stopped` 别名去掉、假 Agent 的命令类型改用 `AgentId`、`TurnSpaces.spaces` 改名 `list`、重复导入合并、提示词段间多出的空行去掉。样式里的 `opacity: 0.35`、`2px` 沿用周边先例，未改。
- 规格：四条验收标准均满足，无必须修复。已处理：对话 id 立即存盘（第一轮中途退出也能续上）、已卸载 Agent 的历史对话禁止发送、退出中断样本改为真实形态、DSH 失败判定的记录措辞。未处理、记为已知限制：**一轮进行中退出应用时，快照来不及收尾，这一轮的改动不会进入审查与操作记录**（任务 27/28 起的既有行为，需在下次打开笔记库时补齐快照，宜另开任务单）；对话历史每次读取全部对话文件（数量大时可加索引）；笔记库搬家后其对话按路径对不上；历史时间不带年份。空间上下文的决定被认为合理；可选改进（对当前打开的空间附上范围与记录表，复用 `spaces.prompt()`）留待以后。

真机验证（接真实模型服务运行 Codex、DeepSeek Harness、Pi 各一轮并续对话）按用户要求留待人工验收。

