# 18: 空行插入光标对齐

**What to build:** 空行上的插入光标与在该行打出第一个字之后的位置和高度完全一致，开始输入时光标零位移。完整决定见 [退出列表与空行插入光标规格](../../../notes-desktop/docs/specs/list-exit-caret-spec.md)。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

**Progress:** in-progress

- [ ] 段落之间的空行：光标纵向位置与高度与打出第一个字后的光标在 0.6 点内一致。
- [ ] 文档末尾的空行：同上。
- [x] 空行上开始输入法组字时光标不发生纵向位移。
- [x] 光标高度不因行距被拉长，水平位置仍取自 AppKit。
- [x] 在真实原生编辑器测试中覆盖上述场景，修复前失败、修复后通过。

## Comments

“刚退出列表后的那一行”的零位移由 16 验收。

2026-10-19 实施：测试均在真实 AppKit 编辑器接缝（`ListEditingTests`），修复前失败、修复后通过。全套 `swift test` 共 79 项（24 原生界面、55 核心），唯一失败为 `EditorWorkflowTests.testCaretGeometryNavigationCompositionAndListExit` 中 18 处光标几何断言（宽度 2.5/2、高度公式、x+1），在未改动的 HEAD 上同样失败，与本任务无关；该测试中改写的退出列表断言通过。日志 `/tmp/noteslite-list-exit-tests.log`。未做手动打开应用的视觉检查。

空行光标改按当前输入属性（正文字体）计算：键入拉丁字符或输入法组字时三种场景零位移（误差 0.6 点内）。未勾选的两项：提交中文字符后，该字符使用中文字面（宋体/苹方），光标按字符字体的度量绘制，仍比空行光标低约 2.5 点、高 1 点；这是现有逐字符光标几何的行为，混排行内移动光标同样存在。消除它需要改为按行的正文字体统一计算光标纵向几何，影响全部光标，待用户决定。
