# notes-desktop：跨平台桌面版重写

**Status:** ready-for-agent

正式规格：[跨平台桌面版重写：Electron 单一代码库取代 macOS 原生旧版](../../notes-desktop/docs/specs/desktop-rewrite-spec.md)。验收基线另含 [独立笔记软件规格](../../notes-desktop/docs/specs/spec.md)、[空间规格](../../notes-desktop/docs/specs/spaces-spec.md) 和 [退出列表与空行插入光标规格](../../notes-desktop/docs/specs/list-exit-caret-spec.md)。架构决定见 [ADR 0004](../../notes-desktop/docs/adr/0004-cross-platform-desktop-rewrite.md) 与 [ADR 0005](../../notes-desktop/docs/adr/0005-agent-sidebar-via-external-cli.md)。

配套规格（同属本功能）：

- [界面与动效规格](../../notes-desktop/docs/specs/ui-motion-spec.md)，取值见 [设计规范](../../notes-desktop/docs/design-system.md)。
- [助手栏规格](../../notes-desktop/docs/specs/assistant-spec.md)：里程碑 5；测试接缝（核心库快照与还原、用假命令行 Agent 驱动的运行中应用）已与用户确认。

30 个任务已拆分并获用户确认，参见 [任务索引](README.md)。

## Comments

- 2026-10-19：新增界面与动效规格、设计规范、助手栏规格（ADR 0005），均为 ready-for-agent。
- 2026-10-19：按里程碑拆为 30 个任务（用户追加：设置界面层级清晰并使用滑块等可视化控件，见任务 15）。
