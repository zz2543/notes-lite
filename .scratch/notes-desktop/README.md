# notes-desktop 任务索引

日期：2026-10-19。30 个任务的粒度与阻塞关系已获用户确认，均为 ready-for-agent；编号即依赖顺序。规格入口见 [spec.md](spec.md)。

里程碑：01–07 骨架；08–17 编辑对齐与设置；18–21 空间；22–25 完成对齐并取代旧版；26–30 助手栏。

| 任务 | 阻塞项 |
| --- | --- |
| [01: 应用骨架与打开笔记库](issues/01-app-skeleton.md) | 无 |
| [02: 编辑与自动保存](issues/02-edit-autosave.md) | 01 |
| [03: 设计规范落地：材质、颜色与动效预设](issues/03-design-system-foundation.md) | 01 |
| [04: 整理笔记与文件夹](issues/04-organize-notes.md) | 02 |
| [05: 外部修改与文件监视](issues/05-external-changes.md) | 02 |
| [06: 就地搜索](issues/06-inline-search.md) | 01 |
| [07: 启动性能达标](issues/07-startup-performance.md) | 01, 06 |
| [08: 原地排版与源码切换](issues/08-live-markdown.md) | 02 |
| [09: 列表延续与退出列表](issues/09-list-continuation-exit.md) | 08 |
| [10: 插入光标与文字选区](issues/10-caret-selection.md) | 08（移到最后，届时问用户） |
| [11: 光标与输入动画](issues/11-typing-motion.md) | 10, 03（随 10 移到最后） |
| [12: 表格与公式](issues/12-tables-math.md) | 08 |
| [13: 笔记链接、图片与附件](issues/13-links-attachments.md) | 08, 04 |
| [14: 专注模式](issues/14-focus-mode.md) | 02, 03 |
| [15: 设置面板：层级清晰与可视化控件](issues/15-settings-panel.md) | 03 |
| [16: 排版设置与内置字体](issues/16-typography-settings.md) | 08, 15 |
| [17: 单栏导航](issues/17-single-column-nav.md) | 04, 15 |
| [18: `.notes/` 搬迁与空间库](issues/18-notes-folder-and-spaces.md) | 01, 03 |
| [19: 空间主页最小闭环](issues/19-space-page-loop.md) | 18, 05 |
| [20: 空间组件、样式包与新接口前缀](issues/20-space-components-prefix.md) | 19 |
| [21: 空间的刷新、错误条与引用同步](issues/21-space-refresh-errors.md) | 19 |
| [22: Windows 适配](issues/22-windows-adaptation.md) | 14, 15, 16, 17 |
| [23: 动效专项审查与打磨](issues/23-motion-review.md) | 14, 16, 17, 21, 26, 29, 30 |
| [24: 大胆高饱和外观风格](issues/24-bold-appearance.md) | 15, 23（移到最后，届时问用户） |
| [25: 完整验收并取代旧版](issues/25-acceptance-replace-old.md) | 07, 09, 12, 13, 20, 22, 23 |
| [26: 助手栏布局与助手形象](issues/26-assistant-layout-figure.md) | 03, 17 |
| [27: 按轮快照与撤销](issues/27-turn-snapshots.md) | 19 |
| [28: 一轮对话（Claude Code）](issues/28-assistant-first-turn.md) | 26, 27 |
| [29: 审查卡片与“直接保留”模式](issues/29-turn-review.md) | 28 |
| [30: 其余 Agent 与对话历史](issues/30-more-agents-history.md) | 28 |

进度：01–09、14–21、26–28 已完成（CI 两平台通过）；29、30 已完成并合并进 feat/notes-desktop。之后 Notion AI 的工作都在 notion/all 分支（提交以 `[notion] <工单号>:` 开头）：12 已完成。接下来 13、23。22 用户要求暂不做（25 依赖 22，也不做）。10、11、24 按用户要求移到最后，届时再问是否做。

优先顺序（2026-10-20 用户要求）：17 完成后优先做助手栏 26–30（27 等 19），再做其余界面任务；动效审查 23 放在助手栏之后并覆盖它。
