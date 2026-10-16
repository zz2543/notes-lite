# 独立笔记软件任务索引

日期：2026-10-16。14 项任务的粒度和阻塞关系已获用户确认；本地 Markdown 已确认为问题跟踪方式，现有任务文件即正式跟踪记录。首个独立原生实现已交付；完整验收仍在进行，见 [实测记录](../../NotesLite/evidence/verification.md)。

规格来源：[独立笔记软件规格](../../design/notes-lite/spec.md)。术语和架构决定以同一设计上下文为准。

## 执行约定

每项任务完成其端到端验收后才算完成。`ready-for-agent` 表示任务描述可供执行，不表示阻塞依赖已完成；有未完成阻塞项的任务不可开始。

当前功能代码已实现；勾选项只表示已有对应检查证据。未完成的体验与性能验收保留未勾选，不能把代码存在当作任务端到端完成。

共用边界：真实原生应用与临时笔记库；保留原产品及已有修改；不引入 Agent 联动；不添加系统“减少动态效果”专项设计。

## 任务列表

| 任务 | 阻塞项 |
| --- | --- |
| [01：独立应用：完成一次笔记写作闭环](issues/01-independent-app.md) | 无 |
| [02：B 三栏资料库：浏览文件夹与笔记](issues/02-three-column-library.md) | 01 |
| [03：搜索与最近打开：快速返回内容](issues/03-search-and-recents.md) | 02 |
| [04：Markdown 原地排版与源码编辑](issues/04-markdown-editing.md) | 01 |
| [05：代码块与表格：完成结构化笔记](issues/05-code-and-tables.md) | 04 |
| [06：公式：完成数学笔记](issues/06-math-notes.md) | 04 |
| [07：笔记链接：连接并跳转相关内容](issues/07-note-links.md) | 02、04 |
| [08：图片与附件：完成图文资料记录](issues/08-images-and-attachments.md) | 04 |
| [09：整理笔记库：安全改名、移动和删除](issues/09-organize-vault.md) | 07、08 |
| [10：整页专注模式：进入、写作、返回](issues/10-focus-mode.md) | 02、04 |
| [11：真实 Metal 浮层：折射、高光与交互波纹](issues/11-metal-search-surface.md) | 03 |
| [12：连贯动效：面板与专注转场](issues/12-fluid-transitions.md) | 10、11 |
| [13：保存异常与外部修改：保护未保存内容](issues/13-save-and-conflicts.md) | 01 |
| [14：完整交付验收与原型归档](issues/14-verify-and-deliver.md) | 05、06、09、12、13 |

## 问题跟踪配置

配置已完成：使用本地 Markdown 和默认五个分诊标签。规格入口为 [spec.md](spec.md)，任务沿用现有独立文件，不需要远程发布。完整约定见 [问题跟踪配置](../../docs/agents/issue-tracker.md)。
