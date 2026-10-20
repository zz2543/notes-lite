# 21: 空间的刷新、错误条与引用同步

**What to build:** 范围内笔记被编辑器、外部程序或页面修改时空间主页自动刷新；页面出错有错误条；笔记改名移动时空间里的路径随之更新。

**Blocked by:** 19

**Status:** ready-for-agent

**Progress:** in-progress

- [x] 三种来源的修改都触发页面刷新
- [x] JS 错误与资源加载失败显示错误条，可复制给 Agent；写入后显示提示条
- [x] 笔记与文件夹改名、移动时更新空间文件中的范围与组件路径
- [x] Playwright 验证外部修改刷新与错误条

## Comments

### 2026-10-20 实现（分支 `ticket/21-space-refresh`）

提交：b83c963（改名/移动时空间路径同步）、860121d（实时刷新、错误条、写入提示）、8715e97（合入 `feat/notes-desktop`，含任务 28）。

- **引用同步**：核心库 `spaceLibrary().syncPaths(from, to)`（移植旧版 `syncPaths`：范围 meta 沿用原名改写；引号内的路径、`#标题`、省略 `.md` 的写法跟随；单独的文件夹名不改，前缀相同的兄弟文件夹不动）。在 `organizer` 的 `relocate` 成功后调用，所以应用里的改名/移动、空间页的 `space.rename/move`、外部 Agent 命令都覆盖；操作记录撤销改名/移动时反向同步。同步失败不回滚移动（笔记已在用户放的位置）。
- **实时刷新**：主进程的库监视回调交给 `spacePages.libraryChanged`：空间文件被改写（Agent、`writePage`）则直接重载，不审阅；否则把范围内、非隐藏的变化路径（核心库 `spaceChanges`）推给页面的 `space.on("change")`，组件已订阅，随之重绘。编辑器保存、外部程序、页面自己写入都经磁盘与监视器到达，隐藏在笔记后面的主页也会收到。
- **错误条**：`space` 接口在页面里捕获未捕获错误、未处理的 Promise 拒绝、资源加载失败（捕获阶段）和组件的 `space:problem`；主进程只接受主页主框架发来的报告，把行号换算成“空间文件第 N 行”；主框架加载失败、渲染进程退出也进错误条。卡片头下方以“展开”出现、把主页往下推；保留最近 5 个不同错误，可关闭；重载时清空。“复制错误给 agent”由核心库 `spaceErrorReport` 生成（空间文件、错误、位置、堆栈、编写说明路径）。
- **写入提示**：页面经 `space` 写入后显示“主页刚修改了 N 条记录/处内容 · 查看”，8 秒后消失，“查看”打开操作记录。
- 证据：`npm run typecheck`；`npm test` 173 通过 / 3 跳过（新增 `spaces.test.ts` 3 个：移植的 syncPaths、spaceChanges、spaceErrorReport；`organize.test.ts` 1 个；`spaceNoteWrites.test.ts` 1 个：页面改名后同步与撤销反向同步）；合并前 `npm run test:e2e` 83 通过，合并后重跑 space-refresh / space-page / spaces / assistant 16 通过。新增 `tests/e2e/space-refresh.spec.ts` 3 个：外部程序、编辑器、页面三种来源刷新（脚本与组件都重绘，范围外不推送）与写入提示；Agent 改写空间文件后立即显示；JS 错误（第 4 行）、复制报告、资源加载失败、组件被拒、修好后错误条消失，错误条最终状态完全显示且不遮挡主页。

决定与留给后续：
- 新增设计变量 `--space-problem`（取 `--accent-orange`，错误条底色 9%、描边 22% 混色）不在设计规范里 → 任务 23 核对；错误条与写入提示的入场用“展开”（高度+不透明度）。
- 刷新延迟未测量（规格不设门槛）；监视器 80 ms 汇集一次。

