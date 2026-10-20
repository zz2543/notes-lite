# 30: 其余 Agent 与对话历史

**What to build:** 可以在助手栏切换 Codex、DeepSeek Harness、Pi，并回看、继续以前的对话；助手编写空间主页时遵循编写说明。

**Blocked by:** 28

**Status:** ready-for-agent

- [ ] Codex、DeepSeek Harness、Pi 的适配层与完全权限启动，逐一核实输出与恢复方式
- [ ] 对话历史列表，继续以前的对话沿用其 Agent 与工作目录
- [ ] 让助手写空间主页时把编写说明作为上下文
- [ ] 假 Agent 覆盖各适配层的输入输出

## Comments

### 2026-10-20 用户试用反馈

选了尚未适配的 Agent（如 Codex）时，要等发出消息后才提示“这个 Agent 还不能在助手栏里使用”，助手形象随之变红。本任务一并改为：选择 Agent 时就标出或禁用尚未支持的 Agent，不让用户发出注定失败的消息。另：用户机器上未安装 `claude` 命令行，只有 Claude 桌面 App 内部的 `claude-code-vm` 副本，检测不应使用它。
