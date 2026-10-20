# 27: 按轮快照与撤销

**What to build:** 每一轮开始前对整个笔记库做增量快照，一轮的改动可以作为一条操作记录整体撤销或逐篇撤回，包括图片附件。

**Blocked by:** 19

**Status:** ready-for-agent

**Progress:** completed

- [x] Markdown 与文本存入按内容去重的存储，每轮只检查修改时间与大小
- [x] 附件：macOS 用 APFS 克隆；Windows 首次后台复制基线；超过约 10GB 时 Windows 只记录元数据并提示
- [x] 一轮结束后得出改动清单，整轮撤销与逐篇撤回都完全还原
- [x] 快照保留 30 天自动清理；设置显示占用并可立即清理
- [x] 按用户真实规模（约一万篇笔记、1GB 附件）实测耗时、内存与磁盘并记录

## Comments

### 2026-10-20 实施记录

分支 `ticket/27-turn-snapshots`。核心库 `src/core/snapshots.ts`：`snapshotStore(base)` 按笔记库分目录（根路径哈希）存在应用数据目录 `userData/snapshots/`，`library(root)` 给出 `begin / finish / revert(id, path?) / turn / baseline / usage / clean / clear`。

- 文本（md、txt、html、json 等按扩展名）存入按 SHA-256 去重的对象库；每次只比较大小与修改时间，未变的文件沿用上次的记录，不再读取。内存只保留最新一份清单（真实规模下约 3 MB）。
- 附件：macOS 用 `cp -c`（APFS 克隆；Node 的 `copyFile` 在 macOS 上不会克隆，实测 1 GB 会真占 1 GB），其余平台整份复制；复制模式下附件总量超过约 10 GB 只记大小与时间，改动标为不可撤回，设置里提示。助手栏打开时主进程在后台做基线快照（`prepareSnapshots`），Windows 的首次复制就在这时发生。
- 改动清单：新增/改写/删除，按路径排序；撤回时文件在这一轮之后又被改过则拒绝（`conflict`），整轮撤回时一处冲突即全部不动；新增的文件进废纸篓，这一轮新建的空文件夹删除。`.git`、`.DS_Store`、`Thumbs.db` 与 `.notes/操作记录.json` 不进快照。
- 操作记录：新增 `agentTurn` 条目（`turnEntry(turn)`），摘要“助手一轮：改动 N 个文件”，撤销即整轮撤回；`operationLog` 新增 `turns` 选项，主进程已接入。
- 保留：每轮开始与应用启动的后台工作清理 30 天前开始的轮次及只被它们引用的内容（每个笔记库始终保留最新一份快照作为增量基准）；设置新增“助手”分类，“快照”组显示全部笔记库的占用并可“立即清理”（先确认）。
- 测试钩子：`NOTES_DESKTOP_SNAPSHOT_COPY_LIMIT`（字节）让任何平台都用复制模式与该上限。

证据：`npm run typecheck` 通过；`npm test` 151 通过 / 3 跳过，其中 `tests/core/snapshots.test.ts` 11 项（整轮撤销、逐篇撤回与空文件夹、冲突拒绝、图片改写删除两种模式、超限只记元数据、去重、30 天清理（注入时钟）与立即清理、操作记录整轮撤销与冲突、多库分开存放与合计）；`npm run test:e2e` 73 通过，含 `tests/e2e/snapshots.spec.ts` 2 项（打开助手栏后才有快照、设置显示占用并立即清理、超限提示），`settings.spec.ts` 分类列表加上“助手”。CI 未运行。

真实规模实测（macOS，APFS；`NOTES_DESKTOP_MEASURE_SNAPSHOTS=1 NODE_OPTIONS=--expose-gc npx vitest run tests/core/snapshots.scale.test.ts`，一万篇笔记 + 200 × 5 MB 附件）：

| 模式 | 基线快照 | 基线实占磁盘 | 无改动时一轮开始 | 一轮结束（11 个文件改动） | 整轮撤销 | 常驻内存 |
| --- | --- | --- | --- | --- | --- | --- |
| 克隆（macOS） | 0.76 s | 48 MB | 0.19 s | 0.14 s | 0.04 s | 约 3 MB |
| 复制（Windows 方式） | 1.5 s | 1.05 GB | 0.17 s | 0.14 s | 0.04 s | 约 3 MB |

留给后续：
- 一轮的驱动（`begin` → Agent 运行 → `finish` → `log.record([turnEntry(turn)])`）、审查汇总卡片的“全部保留 / 逐篇撤回”（用 `revert(id, path)`）与“直接保留”设置：任务 28 及其后。
- 设置里的占用按文件逻辑大小相加，macOS 克隆共享的磁盘块会被重复计入（是上限值）。Windows 上的实际耗时未在 Windows 机器上测量。

### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 两平台通过：https://github.com/zz2543/notes-lite/actions/runs/39386345223 。合并后修过的 CI 问题：慢机器上的撤销分组与助手栏宽度过渡用例、字体许可证在 Windows 检出时被改成 CRLF（加 `.gitattributes`）。

### 2026-10-20 里程碑代码审查

一轮进行中应用自己的写入（自动保存、整理、空间主页写入）不再算进这一轮，撤销一轮不会撤掉用户的输入：`TurnSnapshots.appWrote`，`6cca1de`。
