# 15: 列表与段落之间的空行压矮显示

**What to build:** 打开或编辑任何笔记时，紧接在列表项之后、又紧挨着普通段落的那一个空行以极小行高显示，仅保留段落已有的间距，使列表与随后正文在视觉上不被多出的一行隔开。源码保持不变。完整决定见 [退出列表与空行插入光标规格](../../../design/notes-lite/list-exit-caret-spec.md)。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

**Progress:** completed

- [x] “列表项、单个空行、普通段落”中的空行以极小行高显示，段落相对列表的纵向位置与“列表项、段落”紧邻时一致（仅保留段落间距）。
- [x] 无序、有序、任务列表之后均适用；打开已有笔记同样生效。
- [x] 列表与段落之间有两个及以上空行时全部按正常空行显示；列表与列表、段落与段落之间的空行不受影响。
- [x] 代码块等字面块内的空行不受影响；源码视图与保存的 Markdown 不变。
- [x] 在真实原生编辑器测试中断言行的纵向位置，修复前失败、修复后通过。

## Comments

2026-10-19 实施：测试均在真实 AppKit 编辑器接缝（`ListEditingTests`），修复前失败、修复后通过。全套 `swift test` 共 79 项（24 原生界面、55 核心），唯一失败为 `EditorWorkflowTests.testCaretGeometryNavigationCompositionAndListExit` 中 18 处光标几何断言（宽度 2.5/2、高度公式、x+1），在未改动的 HEAD 上同样失败，与本任务无关；该测试中改写的退出列表断言通过。日志 `/tmp/noteslite-list-exit-tests.log`。未做手动打开应用的视觉检查。

光标位于分隔空行上时该行照常显示（否则光标无处可见），由 `testBlankLineBetweenListAndParagraphTakesNoRoom` 覆盖。
