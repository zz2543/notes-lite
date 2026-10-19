# 17: 嵌套空列表项逐级退出

**What to build:** 在嵌套的空列表项上回车时退回上一层级，而不是直接结束整个列表；缩进与标记跟随父项。完整决定见 [退出列表与空行插入光标规格](../../../notes-desktop/docs/specs/list-exit-caret-spec.md)。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

**Progress:** completed

- [x] 嵌套空项回车后缩进与父项对齐，光标位于新标记之后，不新增行。
- [x] 标记跟随父项类型：无序沿用父项符号；有序为父项编号加一并沿用父项分隔符；任务父项生成未勾选任务标记。
- [x] 后续同级项不重新编号；退一级不补分隔空行。
- [x] 多层嵌套逐次回车逐级退出，到达最外层后按退出列表规则处理。
- [x] 撤销可恢复退一级前的状态。
- [x] 在真实原生编辑器测试中覆盖三种列表类型与保存后的源码，修复前失败、修复后通过。

## Comments

与 16 修改同一换行处理入口，二者逻辑独立；并行实施时需在合并时处理冲突。

2026-10-19 实施：测试均在真实 AppKit 编辑器接缝（`ListEditingTests`），修复前失败、修复后通过。全套 `swift test` 共 79 项（24 原生界面、55 核心），唯一失败为 `EditorWorkflowTests.testCaretGeometryNavigationCompositionAndListExit` 中 18 处光标几何断言（宽度 2.5/2、高度公式、x+1），在未改动的 HEAD 上同样失败，与本任务无关；该测试中改写的退出列表断言通过。日志 `/tmp/noteslite-list-exit-tests.log`。未做手动打开应用的视觉检查。

撤销按系统打字粒度：连续多次回车会被 NSTextView 合并为一步撤销，一次撤销回到退一级之前。当最近的更浅缩进行本身是空列表项时不视为父项，直接退出列表（未覆盖的边界）。
