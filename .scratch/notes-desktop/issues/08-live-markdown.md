# 08: 原地排版与源码切换

**What to build:** 直接书写 Markdown 即可原地看到标题、强调、引用、列表、代码块的排版，并能切换到源码显示，文件内容始终逐字不变。

**Blocked by:** 02

**Status:** ready-for-agent

**Progress:** completed

- [x] 标题、粗斜体、引用、有序/无序列表、行内代码、代码块按设计规范原地排版
- [x] 代码高亮
- [x] 切换源码与原地排版不重建文档，光标、选区与滚动位置保持
- [x] 移植旧版渲染语法相关测试

## Comments

### 2026-10-20 实施记录（分支 `ticket/08-live-markdown`）

实现：
- 核心库 `src/core/markdown.ts` 移植旧版 `Markdown.swift` 的块类型、字面块（围栏代码、`$$` 公式块、front matter，`literalBlocks`）与行内解析 `parseLine`（保留旧版优先级：代码、公式、脚注、嵌入、图片、笔记链接、链接、网址，再到强调与标签）；`src/core/codeHighlight.ts` 移植 `CodeHighlight.swift`（逐行着色）。
- 编辑器 `src/renderer/src/markdownView.ts` + `markdown.css`：只加装饰，不改文档。语法标记在非编辑行隐藏，在编辑行以 `--card-muted` 显示并悬挂在文字左侧，文字不位移；列表标记换成 • ◦ ▪ / “n.” / 任务方框，光标在标记内时显示原文；引用每级一条竖线；代码块等宽、底色、按语言着色；分隔线画成细线。
- 源码切换：菜单“笔记 › Markdown 源码”（勾选项，⌘⇧M / Ctrl+Shift+M，与旧版一致）与卡片顶部按钮（`aria-pressed`）。切换只重配 CodeMirror Compartment：文本、选区、撤销、输入法组字都在；编辑行在屏幕上的位置保持（不在视野时保持顶部文字）。整个窗口一个选择，切换笔记保留，不跨启动保存（同旧版）。

验证（macOS）：typecheck；`npm test` 25 个（新增 `tests/core/renderSyntax.test.ts` 11 个，移植 RenderSyntaxTests 中除表格与独立公式外的全部用例）；`npm run test:e2e` 14 个（新增 `tests/e2e/markdown.spec.ts` 8 个：标题、强调与行内代码、引用、列表、分隔线、代码块着色、切换保持光标选区滚动撤销且字节不变、菜单与按钮切换含组字中切换与跨笔记保持）。`smoke.spec.ts` 改为在源码视图下核对原文。

决定：
- 标题字重用原型的 650；三至六级标题、列表/引用缩进、代码配色等设计规范未列出的取值沿用旧版，已补入设计规范“正文排版”。
- 段距按旧版作用于每个段落行与空行之后，保证在空行上打字不使后文移动（与任务 10 的零位移一致）。
- 源码视图同旧版：等宽、无排版、无高亮。

留给后续：
- 表格、独立公式（`displayMath`、`MarkdownTable` 测试）与行内公式渲染 → 任务 12；`$$` 块暂按代码块显示。
- 链接、图片、嵌入、标签的样式与点击 → 任务 13（已解析，暂按原文显示）。
- 列表延续与退出、分隔空行压矮 → 任务 09；插入光标与选区 → 任务 10；排版设置调整这些变量 → 任务 16。
- 任务方框暂不可点击勾选，删除线、高亮、脚注、callout 暂按原文显示：没有任务认领，建议在 25 验收前补。
- 卡片顶部按钮“悬停时浮现、打字即隐藏”的动效留给任务 03/23；按钮目前常显、低显著度。

### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 在 macOS 与 Windows 均通过：https://github.com/zz2543/notes-lite/actions/runs/39291544784 。CI 上两个依赖帧时序的用例改为检查正在运行的过渡与 1px 内的位置（提交 979f5b4、bae9c12）。
