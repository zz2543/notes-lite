# 06: 只读组件：lb-stat、lb-chart、lb-calendar、lb-records

**What to build:** 外部 Agent 可以在空间主页里直接放大数字、折线/柱状图、打卡热力日历和最近记录列表，用来展示任意主题的进展，数据变化后自动重绘。

**Blocked by:** 03：空间主页渲染：只读的 lb 接口与实时刷新

**Status:** ready-for-agent

**Progress:** completed

- [x] `lb-stat` 支持计数、求和、平均、最新值，按周期统计。
- [x] `lb-chart` 支持折线图和柱状图，x/y 对应字段。
- [x] `lb-calendar` 按日期字段显示打卡热力日历。
- [x] `lb-records` 显示最近 N 条记录。
- [x] 组件不认识任何主题，只认识记录表和字段；可配置 `source`、`label`、`unit`、`title`、颜色等；只通过 `lb` 读取，订阅 change 后自动重绘。
- [x] 组件使用样式包，在浅色和深色模式下都与原生界面一致（截图存入 evidence）。
- [x] 数据为空、字段不存在、来源在范围外时显示可理解的状态。

## Comments

2026-10-18：已实现。原生截图 widgets-dark.jpg、agent-homepage-dark/light.jpg；`SpaceWorkflowTests` 覆盖 lb-stat、lb-records 渲染与刷新。完整记录见 [实测记录](../../../NotesLite/evidence/spaces/verification.md)。
