# 07: 快捷录入组件 lb-quick-add

**What to build:** 用户在空间主页上几秒钟记一条记录：组件按目标记录表的表头和字段类型生成输入框，提交后记录写入 Markdown，页面其他组件立刻更新。

**Blocked by:** 04：写入记录与操作记录

**Status:** ready-for-agent

**Progress:** completed

- [x] 按目标记录表表头生成输入框：数字字段用数字输入，日期字段默认填今天，其余为文本。
- [x] 目标不存在时，按组件声明的表头新建。
- [x] 提交后磁盘上出现新行，进入操作记录并可撤销，触发写入提示。
- [x] 可配置 `target`、`label`、`title` 等；使用样式包并跟随深色模式。
- [x] 输入不合法或写入失败时给出反馈，不显示虚假成功。

## Comments

2026-10-18：已实现。`SpaceWorkflowTests` 通过真实表单提交写入磁盘；截图 quick-add-dark.jpg。完整记录见 [实测记录](../../../NotesLite/evidence/spaces/verification.md)。
