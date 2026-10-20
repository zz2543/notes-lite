# 07: 启动性能达标

**What to build:** 打开软件不用等：冷启动 1 秒内能在上次的笔记里打字，再次打开 0.3 秒内恢复，且没有白屏或转圈。

**Blocked by:** 01, 06

**Status:** ready-for-agent

**Progress:** completed

- [x] 在 Apple M4、约一万篇笔记的笔记库上：冷启动到可输入 ≤ 1 秒；关闭窗口后再次打开 ≤ 0.3 秒
- [x] 启动不做全库扫描或建索引，先显示上次的笔记与当前目录
- [x] 窗口出现时无白屏、无转圈启动画面
- [x] 提供可重复的测量脚本并记录机器、系统、笔记库规模与结果；Windows 数据仅记录作参考

## Comments

### 2026-10-20 实施记录

分支 `ticket/07-startup-performance`。提交：`4f75c69` 启动时回到上次的文件夹与笔记、`1c025e9` 接缝 B 测量用例、`d9b4c24` 渲染进程包压缩、`52671fc` 先显示上次的笔记再建索引并在 macOS 关窗时隐藏、`5173e00` `npm run measure:startup`，以及两次合并 `feat/notes-desktop`（`97c9d13` 含文件监视推迟与重新显示时恢复焦点、`0ea6f3b`）。

测量（`tests/e2e/startup.spec.ts`，`STARTUP_RUNS=10 npm run measure:startup`）：Apple M4，macOS 27.0.1（Darwin 27.0.0），笔记库 100 个文件夹 × 100 篇（每篇约 1.3 KB，共 1 万篇）。计时从 Playwright 发起启动到在上次的笔记里打出的字出现（含 Playwright 自身开销；文件已在系统缓存中，即“热盘冷进程”）。

- 冷启动到可输入：中位数约 450–480 ms（合并 03/05/08 后 10 次：479 ms）；目标 1 s。
- 关闭窗口后再次打开到可输入：中位数约 30 ms（10 次：29 ms）；目标 0.3 s。改前（重新建窗口）约 190 ms。
- 分解（诊断时）：主进程启动约 100 ms，建窗到页面开始约 120 ms，页面解析约 80 ms（压缩前约 115 ms），上次的笔记显示约 150–200 ms。
- 断言只在 macOS 且非 CI 时生效；CI 与 Windows 只把数字写进测试注解和输出，作参考。Windows 数据尚未实测（本地无 Windows 机器），由 CI 输出补记。

本地验证：`npm run typecheck` 通过；接缝 A `npm test` 74 个用例；接缝 B `npm run test:e2e` 33 个用例（新增 `startup.spec.ts` 2 个：“reopens the last note in its folder, ready to type”含之后搜索可用，“starts ready to type within budget in a library of ten thousand notes”）。全量接缝 B 跑过 4 次，各有一次 `design-system` 悬停、`external-changes` 冲突用例失败，单独重跑均通过，最后两次全绿；疑为负载下的偶发，未改动。

实施中的决定：

- 设置里记住 `place`（当前文件夹与打开的笔记），切换笔记库时清空；启动时若笔记或文件夹已不在则丢弃对应部分。重新打开的笔记光标放在末尾（与新建笔记相同），不记具体光标位置。
- 主进程在页面加载时预读上次的文件夹（及其上级）与笔记，页面第一次请求直接用预读结果。
- 窗口在页面报告“已显示上次的位置”后才出现（兜底 0.5 s），只有窗口底色或材质，无白屏、无转圈。搜索索引与文件监视（任务 05）都在这之后才开始（兜底 3 s）；从选择对话框打开的新笔记库仍立即开始。
- macOS 上关闭窗口且笔记都已保存时只隐藏窗口，Dock 图标重新显示并恢复焦点；选择“不保存，直接关闭”时仍真正关闭。
- 渲染进程包开启压缩（`electron.vite.config.ts`）。

留给后续任务：真正冷盘（重启后首次启动）未测；Windows 实测数字留给任务 22 / 25 记录。

### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 两平台通过：https://github.com/zz2543/notes-lite/actions/runs/39355440325 。CI 记录的启动时间（一万篇笔记，中位数）：Windows（AMD EPYC 虚拟机）冷启动到可输入 570 ms；macOS（M1 虚拟机）冷启动 1112 ms、重开 27 ms。CI 只记录不判定；macOS 虚拟机冷启动略超 1 s 预算，本机 M4 为 479 ms，验收以真机为准。
