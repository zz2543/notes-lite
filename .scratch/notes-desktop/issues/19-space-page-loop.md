# 19: 空间主页最小闭环

**What to build:** 打开空间看到由记录表驱动的空间主页，在页面里快速录入一条记录就写回 Markdown；每次写入进入操作记录，可逐条撤销。

**Blocked by:** 18, 05

**Status:** ready-for-agent

**Progress:** completed

- [x] 空间主页在隔离沙盒中运行，每个空间独立存储，允许联网；页面只能通过桥接接口访问笔记
- [x] 空间请求处理在核心库：记录表定位、占位符、类型推断、增删改记录、按表头新建
- [x] 范围校验：拒绝范围外路径、`..`、符号链接逃逸、其他空间文件与隐藏目录
- [x] 每次写入进操作记录，逐条撤销、跨重启保留、30 天清理；撤销冲突有提示
- [x] 移植旧版空间请求处理、操作记录测试；Playwright 验证录入后磁盘出现新行

## Comments

### 2026-10-20 实现

分支 `ticket/19-space-page-loop`：af86dfa（核心库读请求）、4099237（记录写入、操作记录、逐条撤销）、625c4eb（范围内笔记增改移删与撤销）、eb30f54（沙盒主页与操作记录面板）、f362b34（合入 `feat/notes-desktop`）。

- 沙盒：每个空间的主页是盖在卡片上的 `WebContentsView`（`src/main/spacePages.ts`），`sandbox`、无 Node、按“笔记库根目录 + 空间名”哈希的 `persist:` 分区（存储互不相通），自定义安全协议 `notes-space://` 每次加载从磁盘读空间文件；默认联网，权限请求一律拒绝，不能导航离开，`window.open` 的 http(s) 链接交给系统浏览器。页面只有 `lb`（`src/main/lbShim.ts`，移植旧版 lb.js），经专用 preload（`src/preload/space.ts`）只从主框架发给主进程，再交核心库 `spaceRequests` 判断；嵌入的 iframe 拿不到 `lb`。
- 沙盒 preload 不能 `require` 共享 chunk，所以两份 preload 不得共用模块：空间页通道单独放在 `src/shared/spacePage.ts`。
- 主页由主进程盖在页面之上，菜单、对话框和“设置”打开时主页先让开（`useOverlay` / `useOverlayOpen`）；切到笔记或“资料库”时移除，回来保留页面状态。
- 打开空间：双栏下中栏为“主页 + 范围内笔记”；单栏下（任务 17 留下的部分）在侧栏空间列表下方显示同样内容。主页卡片头保留专注与助手栏按钮。
- 证据：`npm run typecheck`；`npm test` 140 通过 / 1 跳过（含 `tests/core/spaceRequests.test.ts`、`spaceRecordWrites.test.ts`、`spaceNoteWrites.test.ts`：范围、`..`、符号链接/目录联接、隐藏目录、其他空间文件、逐条撤销、重开后撤销、撤销冲突、30 天清理）；`npm run test:e2e` 71 通过，含 `tests/e2e/space-page.spec.ts` 4 项（录入后磁盘出现新行、操作记录逐条撤销与冲突提示、沙盒无 Node/无 `window.notes`/范围外拒绝/iframe 无 `lb`/不能导航/存储隔离、主页与笔记切换保留状态、单栏空间）。`spaces.spec.ts` 的空间列表定位改为精确名称，避免与“空间内容”相撞。
- 留给后续：主页的 `lb.on("change")` 推送与外部改动后刷新随任务 21；组件库随任务 20。


### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 两平台通过：https://github.com/zz2543/notes-lite/actions/runs/39386345223 。合并后修过的 CI 问题：慢机器上的撤销分组与助手栏宽度过渡用例、字体许可证在 Windows 检出时被改成 CRLF（加 `.gitattributes`）。

### 2026-10-20 里程碑代码审查

空间改名后主页的本地存储不再丢失（spaces-spec #51）：存储键由核心库 `spaceStorage` 记在应用数据目录，改名随空间走，删除或改名后同名新空间从空开始：`ef3a307`。操作记录对话框移到 `OperationLog.tsx`，提示文字涵盖助手的每一轮：`4b7290f`。
