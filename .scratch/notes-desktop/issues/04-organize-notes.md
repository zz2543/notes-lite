# 04: 整理笔记与文件夹

**What to build:** 用户可以新建、改名、移动、删除笔记和文件夹，引用自动更新，删除可恢复；文件夹点击展开与收起符合约定。

**Blocked by:** 02

**Status:** ready-for-agent

**Progress:** completed

- [x] ⌘N / Ctrl+N 在当前文件夹新建；悬停文件夹行浮现新建图标，在该文件夹新建
- [x] 笔记与文件夹改名、移动，并更新其他笔记中指向它们的链接（代码示例不被改动）
- [x] 删除进入系统废纸篓，可恢复上次删除
- [x] 点击未选中文件夹：选中并展开；再次点击已展开的选中文件夹：收起；箭头只控制展开
- [x] 名称冲突有提示且不覆盖
- [x] 移植旧版对应的核心库测试

## Comments

### 2026-10-19 来自任务 01

“点击未选中文件夹：选中并展开；再次点击已展开的选中文件夹：收起；箭头只控制展开”已在任务 01 实现，并由 Playwright 冒烟用例覆盖（`tests/e2e/smoke.spec.ts`）；本任务核对即可，不必重做。

### 2026-10-20 实施记录

分支 `ticket/04-organize-notes`（已合入 `feat/notes-desktop`，含任务 06）。本地验证（macOS）：`npm run typecheck` 通过；接缝 A `npm test` 41 个用例（其中 `tests/core/organize.test.ts` 16 个）；接缝 B `npm run test:e2e` 12 个用例（其中 `tests/e2e/organize.spec.ts` 3 个）。CI 未运行，由编排者在集成分支上运行。

覆盖：新建笔记自动编号（“未命名笔记 2”）、新建文件夹；笔记与文件夹改名、移动，指向它们、从它们指出、以及被移动文件夹内部的链接都跟着更新，代码块、行内代码、`$$` 公式与 front matter 里的示例不动；名称冲突与不可用名称（含 Windows 不允许的字符和保留名）报错且不覆盖，只改大小写可行；有引用笔记写不进去时整体回滚（做过变异检查）；移到废纸篓与恢复上次删除（笔记与文件夹，原位置被占用时拒绝）；界面上 ⌘N / Ctrl+N、菜单“文件 › 新建笔记”、文件夹行悬停新建图标、右键菜单的重命名/移动/移到废纸篓/新建文件夹、侧栏“恢复上次删除”。文件夹点击展开收起沿用任务 01 的冒烟用例。

移植的旧版用例：`testRenamingUpdatesRealLinksButLeavesCodeExamplesAlone`、`testImportAndMovePreservesImageReferenceAndBacklink`（移动部分）、`testDottedLinks…`（改名部分）、`testSearchRecentsAndDuplicateNamesRemainUnambiguous`（编号与非法名称）、`testWriterCanCreateSaveAndReopenWithoutChangingLegacyMetadata`、`NoteRelocation` 的整体回滚。

实施中的决定：
- 恢复策略：Electron 的 `shell.trashItem` 不返回废纸篓里的位置，Windows 回收站也无法同样取回，因此删除前在临时目录保留一份副本（APFS 上为克隆），恢复时放回这份副本；系统废纸篓里仍留有一份，用户可自行清理。只保留最近一次删除，切换笔记库或退出后不可恢复（同旧版）。核心库通过 `openLibrary(root, { trash })` 注入废纸篓，主进程传入 `shell.trashItem`；Playwright 在本机用文件夹代替废纸篓，CI 上用真实废纸篓。
- ⌘N 由页面处理按键（真实与测试按键都可靠，macOS 上合成按键不会触发菜单快捷键），菜单项只在被点选时生效，不会触发两次。
- 链接改写沿用旧版解析顺序（笔记旁边 → 根目录 → 唯一标题）；随移动后仍按原写法解析的相对链接不改写；新写入的路径只转义会破坏链接的字符，原本百分号编码的链接保持编码风格。非 UTF-8 笔记不改写。
- 改名、移动后若打开的笔记被改写，编辑器重新读取；新建的笔记打开时光标在标题之后。
- 改名、移动、删除、恢复后通知搜索索引（任务 06）更新涉及的路径。
- 名称规则取 macOS 与 Windows 的交集，避免同步后在另一台电脑上出错。

留给后续任务：菜单与对话框的入场动效、悬停图标的“轻弹”过渡（任务 03/23）；对话框尺寸为占位变量（`organize.css`），待“提示与对话框”设计定稿；空间主页对改名的引用同步（任务 21）；拖拽移动未做。


### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 在 macOS 与 Windows 均通过：https://github.com/zz2543/notes-lite/actions/runs/39286887236

### 2026-10-20 里程碑代码审查

六项验收均已在上面的 Comments 中达成，补勾。
