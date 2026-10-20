# 09: 列表延续与退出列表

**What to build:** 列表输入行为与退出列表规格一致：延续同级标记、空项回车退出或退回上一层、分隔空行不占高度。

**Blocked by:** 08

**Status:** ready-for-agent

**Progress:** completed

- [x] 非空列表项末尾换行带出同级同类型标记
- [x] 嵌套空项回车退回上一层；最外层空项回车结束列表且不另起新行
- [x] 开始输入正文时自动补分隔空行，显示时不占高度，文件在其他编辑器中仍正确
- [ ] 按退出列表与空行插入光标规格的验收项通过（Playwright）

## Comments

### 2026-10-20 实施记录（分支 `ticket/09-list-continuation`）

实现：
- 核心 `src/core/lists.ts`（纯函数，移植旧版 `Markdown.continuation` 与 `parentItem`）：`listReturn`（延续 / 退一级 / 退出）、`opensListGap`、`closesListGap`。
- 编辑器 `src/renderer/src/listEditing.ts`：回车键（高优先级 keymap；字面块内、组字中、光标在标记内时交给默认换行）。分隔空行由 transactionFilter 放进触发它的输入所在的事务（同一撤销步），只追踪自己补入的那一个，撤销重做、光标离开下一行、切换笔记即忘记。组字在 `compositionstart` 时先补空行（在组字事务里改文档会打断 CodeMirror 的组字），history 把随后的组字并入同一步。源码视图下同样生效。
- 显示 `markdownView.ts` + `markdown.css`：列表项与普通段落之间唯一的空行（光标不在其上时）高度为 0；↑↓ 会停在这一行上（否则零高度行会被跳过）。

验证（macOS）：typecheck；`npm test` 84 个（新增 `tests/core/lists.test.ts` 10 个）；`npm run test:e2e` 43 个（新增 `tests/e2e/lists.spec.ts` 10 个：三种列表的最外层退出、打字/组字/粘贴补空行且该行零位移、只输 `-` 不撤回、完整标记与删空撤回、回车不补、撤销不出现单独空行、他处输入不补、切换笔记、嵌套退一级与编号、不重新编号、代码块、空行压矮及两个空行/列表间/段落间不压矮）。

决定：
- 撤销粒度沿用 CodeMirror history（500 ms 内相邻输入合并）；退一级、退出、补空行都不单独成步。
- 旧版“退出列表后忽略输入法回显标记”的保护针对 AppKit，CodeMirror 下不存在，未移植。

留给后续：
- 空行插入光标的位置与高度（规格用户故事 25–29）→ 任务 10；最后一项验收框因此未勾。


### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 两平台通过：https://github.com/zz2543/notes-lite/actions/runs/39359385148 。最后一项（空行插入光标位置）随任务 10 移到最后，未勾选。
