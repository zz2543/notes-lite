# 共笔性能与稳定性重构计划

> 状态：已执行（分支 `perf/refactor`，2026-09-29），实施记录见第 5 节 · 计划写于 2026-09-28
> 起因：用户反馈“多次切换笔记后崩溃、转沙滩球”“左右边栏伸缩掉帧、动画不流畅”，希望整个 app 十分流畅、清晰。
> 已确认的判断：卡顿和崩溃不是 Swift 语言造成的，问题出在 SwiftUI / AppKit / TextKit 的用法上。**继续全 Swift 开发**，不引入 Rust、C++ 或 Web 界面。
> 配套文档：视觉升级另见 [`visual-plan.md`](visual-plan.md)，它在本计划完成后开始，单独回退。

## 0. 回退保证（开始前必须先做）

| 项 | 做法 |
|---|---|
| 基准点 | tag `perf-baseline`，指向本计划写好时的提交（代码与 `e09e195` 相同）。任何时候都能回到重构前的样子 |
| 工作分支 | 从 `perf-baseline` 拉出 `perf/refactor`，全部重构只在这个分支上做，不在 `feat/ai-native` 上直接改 |
| 提交粒度 | 一个改动点一个提交；每个提交都能单独编译，并通过 `swift test` 和 `scripts/e2e.sh`。出问题时可以用 `git revert <提交>` 单独撤掉一步 |
| 阶段标记 | 每个阶段验收后打 tag：`perf-p0` … `perf-p5`。回退到某阶段结束时：`git switch -c 临时分支 perf-p2` |
| 合并 | 全部阶段做完、用户试用确认后，才用 `git merge --no-ff perf/refactor` 合回 `feat/ai-native`。合并提交可以用 `git revert -m 1 <合并提交>` 整体撤销 |
| 不推送 | 延续现有约定，只在本地操作，不 push |
| 未跟踪文件 | `promo/`、`deliverables/` 等未跟踪目录不在 git 里，tag 管不到它们。本计划不会碰这些目录 |
| 并行会话 | 写这份计划时，另一个会话正在工作区里改 `EditorView.swift`、`DebugScenario.swift`，并新增 `Sources/Twain/Render/`（KaTeX、Mermaid）。开始之前先确认这些改动是提交、放弃还是另开分支，避免混进重构的提交里 |

完全回退到重构前：

```bash
git switch feat/ai-native          # 若尚未合并，什么都不用做，重构只存在于 perf/refactor
git revert -m 1 <合并提交>          # 若已合并，整体撤销合并
git switch -c rollback perf-baseline   # 或者直接从基准点开一个新分支
```

## 1. 流畅的标准（每个阶段都用它验收）

| 场景 | 目标 | 现状（2026-09-28 实测） |
|---|---|---|
| 动画、滚动（ProMotion 120Hz） | 每帧 ≤ 8.3ms，零掉帧 | 收起侧栏或 Agent 面板时不掉帧；**展开时每次卡 5–8 帧，单帧最长 75–130ms** |
| 按一个键 | ≤ 8ms（p95） | 中位数 1.8ms，p95 8.4ms（80KB 笔记，`ai-native-plan.md` D2） |
| 切换笔记 | ≤ 30ms | 连续打开 44 篇：中位数 71–75ms，p90 87–100ms，最长 145ms。**4 千字和 9 千字的笔记耗时几乎一样**，说明时间花在界面重算上，与文字多少无关 |
| 启动到可以打字 | ≤ 500ms | 待测 |
| 连续打开 200 篇、开关栏 50 次 | 无排版异常、无崩溃，内存不持续上涨 | 第一轮压测出现 2 次 TextKit 排版异常，第二轮未复现；内存待测 |
| 主线程 | 不读写磁盘、不启动子进程、不同步等待后台 | 多处违反，见第 2 节 |

测量环境：真实库的副本（452 篇笔记，含附件共 1.2GB），优化构建（`swift build -c release -Xswiftc -DDEBUG`），通过 `TWAIN_SNAPSHOT_VAULT` 指向副本，不碰真实库。

## 2. 问题清单（有依据的）

| # | 现象 | 根因 | 依据 |
|---|---|---|---|
| P1 | 崩溃：AppKit 主动终止程序 | 左右栏设了最小/最大宽度，`SplitViewChildController` 在更新约束时又改最小尺寸，形成死循环，超过 AppKit 允许的约束轮数就被终止 | 崩溃日志 `Twain-2026-09-28-005323.ips`；`MainWindow.swift:12`、`:17` |
| P2 | 切换笔记后排版异常，可能导致卡死或崩溃 | 替换整篇文字时，选区变化通知在 TextKit 还没处理完这次改动时就回调 `restyle()`，在排版过程中改了文字属性 | 压测日志 `NSRunStorage _replaceElements(): replaced range {0, 13090} extends beyond current run storage size 10641`；`EditorView.swift:281`（待验证） |
| P3 | 打开笔记固定要 70ms | `AppModel` 是一个有上百个可观察属性的对象，所有界面都通过 `@Bindable` 拿着整个对象；`open()` 一次改十几个属性，侧栏、正文、状态栏、工具栏跟着一起重算 | `AppModel.swift:451` 起；实测耗时与笔记大小无关 |
| P4 | 界面刷新时读磁盘 | 侧栏每次刷新都读 `contextInSync`，它要读 `CLAUDE.md` 并检查 `AGENTS.md` 是否存在；而每次切换笔记，选中项和展开的文件夹都会变 | `AppModel.swift:442`、`Sidebar.swift:65` |
| P5 | 每 5 秒无故刷新 | 定时器每 5 秒改一次 `tick`；状态栏的 `stats` 读它，设置页和空间页用 `.id(model.tick)` 把整块界面拆掉重建 | `AppModel.swift:274`、`SettingsView.swift:190`、`:201`、`SpaceView.swift:574` |
| P6 | 每 3 秒无故刷新 | 终端扫描每次都给每个终端会话的 `alive`、`running` 重新赋值。`@Observable` 对象只要赋值就会通知界面，哪怕值没变 | `AppModel+Agents.swift:426` |
| P7 | 后台线程同步等主线程 | 终端扫描在后台线程里用 `DispatchQueue.main.sync` 取会话数据，主线程忙时后台跟着卡住，写法上也有死锁风险 | `AppModel+Agents.swift:414` |
| P8 | 数据一变整块图表重建 | `.id(model.dataVersion)` 让空间页、设置页的图表整块重建，而不是更新数据 | `SpaceView.swift:411`、`:447`、`:483`、`SettingsView.swift:395` |
| P9 | 长笔记里移动光标越往后越慢 | `center()` 在每次按键和每次移动光标时都从文首排版到光标处 | `EditorView.swift:585` |
| P10 | 批注多时打字变卡 | 每按一次键，50ms 后重新定位所有批注卡片：在全文中查找每条批注的位置，并让每张卡片的 `NSHostingView` 同步完成一次 SwiftUI 布局 | `EditorView.swift:275`、`Annotations.swift:148` |
| P11 | 聚焦或失焦时整篇重设样式 | 开启“淡化其他段落”后，所有非当前段落的颜色都依赖聚焦状态，聚焦一变就要重设全部行 | `Styler.swift` 的 `Sig.dim` |
| P12 | 展开侧栏或 Agent 面板时掉帧 | 展开时要重建整棵文件树（每个文件夹一个 `DisclosureGroup`）和整段会话记录，还叠加了 P4 的磁盘读取 | 实测：只有展开掉帧，收起不掉 |
| P13 | 栏宽动画期间编辑器每帧重算 | 宽度每变一帧，`setFrameSize` 就调用 `layoutChanged()`：重算边距、批注栏、光标位置，窗口较窄时还会重排整段文字 | `TextView.swift:38` |
| P14 | 玻璃效果叠加 | 全 app 共 57 处玻璃效果，很多没有放进同一个 `GlassEffectContainer`，重叠区域的模糊要算好几遍 | `grep glassEffect/glassCapsule` |
| P15 | 打开笔记时同步读文件 | `open()` 在主线程读正文、判断文件是否可读、加载批注、检查超长行 | `AppModel.swift:451` 起 |

## 3. 分阶段计划

每个阶段先写验收标准，做完用第 1 节的指标对比前后数据，记进第 5 节。

### 阶段 0：测量工具（1–2 天）

- 0.1 把压测正式加进 `DebugScenario`，场景名 `stress`：连续打开 N 篇笔记，统计中位数、p90、最大值；随后开关侧栏和 Agent 面板各 4 次，用 `CADisplayLink` 统计每次动画的帧间隔和掉帧数。输出格式固定，方便前后对比。另一个会话已经在做 `openbench`，合并时统一成一个。
- 0.2 加 `stress:long` 变体：连续打开 200 篇、开关栏 50 次，结束时报告排版异常次数和内存占用（`task_info` 的 `phys_footprint`）。
- 0.3 在关键路径打 `os_signpost`：打开笔记、`sync`、`restyle`、`center`、批注重排、侧栏重建。Instruments 里能直接看到每段耗时。
- 0.4 写 `scripts/perf.sh`：一条命令完成构建、复制库、跑场景，并把结果追加到 `docs/perf-log.md`。
- 验收：在 `perf-baseline` 上跑出第 1 节所有“待测”项的基准数据。

### 阶段 1：先止住崩溃

- 1.1 替换整篇文字期间（`swapping == true`）不调用 `restyle()`，替换完成后统一排一次（P2）。先用 `stress:long` 复现，再修复，确认异常次数归零。
- 1.2 布局死循环（P1）：检查 `navigationSplitViewColumnWidth` 和 `inspectorColumnWidth` 的最小值、窗口 `minWidth`、详情页内容的尺寸，保证子视图的尺寸不会反过来改变栏宽。用现有的 `resize` 和 `toggles` 场景扫一遍所有窗口宽度。
- 1.3 给 `TextStorage` 的修改加断言（仅 DEBUG）：如果 `restyle` 在 `processEditing` 期间被调用，直接报错，防止同类问题回来。
- 验收：`stress:long` 连续 3 轮零异常、零崩溃；`resize` 场景全宽度扫过不崩。

### 阶段 2：状态管理重构（改动最大，收益也最大）

- 2.1 **拆分 `AppModel`**。按界面区域拆成几个独立的 `@Observable` 对象，`AppModel` 只负责协调：
  - `EditorState`：正文、版本号、选区、幽灵补全、斜杠菜单、批注。
  - `SidebarState`：选中项、展开的文件夹、筛选、改名。
  - `AgentState`：会话、模型列表、待审阅的改动。
  - `Preferences`：字体、打字机模式、淡化等设置。
  - 每个视图只拿自己需要的那一个，不再传整个 `AppModel`。
- 2.2 **赋值前先比较**。给常被重复赋值的属性加“值不同才赋值”的写法，首先是终端会话的 `alive`、`running`（P6），以及 `applyTerminalScan` 里其他的赋值。
- 2.3 **去掉 `tick` 触发的整块重建**（P5）。状态栏的“字/分”改用只包住那一小段文字的 `TimelineView`；设置页、空间页需要定时刷新的数据，改为数据自己更新，不再 `.id(tick)`。
- 2.4 **图表只更新数据**（P8）。去掉 `.id(model.dataVersion)`，图表的数据源改成可观察的数组。
- 2.5 **界面刷新时不读磁盘**（P4）。`contextInSync` 改成缓存值，打开库时和文件监听报告 `CLAUDE.md`、`AGENTS.md` 变化时才重算。顺带全局排查视图 `body` 里调用到的计算属性，凡是碰磁盘或遍历全库的都改成缓存。
- 2.6 **去掉 `DispatchQueue.main.sync`**（P7）。在主线程先把需要的会话数据复制好，再交给后台线程。
- 2.7 **打开笔记异步化**（P15）。`open()` 先切换选中状态，读文件、可读性检查、超长行检查、加载批注放到后台，读完再一次性交给编辑器。同一时间连续点多篇时，只加载最后一篇。
- 验收：切换笔记中位数 ≤ 30ms；用 Instruments 的 SwiftUI 模板确认切换笔记时侧栏不再整体重算；空闲时 1 分钟内没有界面刷新。

### 阶段 3：编辑器

- 3.1 `center()` 只排版光标附近（P9）。用 `ensureLayout(forBoundingRect:)` 覆盖可见区域加上光标所在段落，不再从文首排到光标处。
- 3.2 批注卡片增量更新（P10）。只重新定位受本次改动影响的卡片（改动位置之后的卡片整体平移即可），卡片高度按“内容和宽度”缓存，内容没变就不重新布局。
- 3.3 淡化只处理可见部分（P11）。淡化改在绘制阶段完成：在 `TwainLayoutManager` 里按行调整绘制透明度，不再修改文字属性。这样聚焦或失焦都不用重设样式。
- 3.4 编辑器的 `updateNSView` 不再依赖 `editorText`。正文由编辑器自己持有，模型层只在保存、审阅、agent 读取时取；每按一个键不再触发 SwiftUI 更新。
- 3.5 复查整篇替换的路径：替换后第一屏立即排版，其余部分空闲时再排。
- 验收：按键 p95 ≤ 8ms（含 20 条批注的笔记）；长笔记末尾移动光标与开头一样快。

### 阶段 4：动画与渲染

- 4.1 栏宽动画期间冻结编辑器排版（P13）。动画或拖动栏宽时只移动文字，不重算边距、批注栏和排版；动画结束后算一次。
- 4.2 展开侧栏不重建文件树（P12）。文件树的数据在库变化时预先算好，行视图保持轻量，保证 SwiftUI 能复用行视图；Agent 会话记录改为 `LazyVStack`，只生成可见的部分。
- 4.3 整理玻璃效果（P14）。同一区域的玻璃放进同一个 `GlassEffectContainer`；正文、会话记录等内容区不叠玻璃；列出每一处玻璃并说明保留理由。
- 4.4 用 Instruments 的 Animation Hitches 模板逐个检查动画：侧栏、Agent 面板、专注模式、命令面板、提示条、批注卡片、审阅视图。
- 验收：`stress` 场景里所有开关动画零掉帧；120Hz 下滚动长笔记不掉帧。

### 阶段 5：设计规范收拢（为视觉升级打基础，界面不变）

- 5.1 颜色、字号、间距、圆角全部收进 `Theme` 和 `Metrics`，各文件不再直接写颜色值或系统色。
- 5.2 建立“外观方案”接口：`Theme` 通过一个 `Appearance` 值取色，这个阶段只有一个方案“经典”，取值与现在完全一致。
- 验收：浅色、深色各一套截图与改动前逐像素一致（`TWAIN_SNAPSHOT` + 图像比对），证明这一阶段没有视觉变化。

## 4. 风险与对策

| 风险 | 对策 |
|---|---|
| 拆分 `AppModel` 牵动面大，容易引入回归 | 按区域一块一块拆，每拆一块跑完整测试和截图；agent 接口（`twain` 命令、HTTP）的 e2e 必须全过 |
| 异步打开笔记后，agent 读到的仍是旧笔记 | `twain context` 等接口在加载完成前返回“加载中”，或等待加载完成再回答；加 e2e 覆盖 |
| 冻结排版后动画结束时文字跳动 | 动画结束后先排可见区域，同一帧内完成；截图录屏核对 |
| 性能数字受 iCloud 下载和机器负载影响 | 固定使用本地副本，每项跑 3 次取中位数，只比较同一台机器上的前后数据 |
| 另一个会话的改动与重构冲突 | 开始前先处理工作区里未提交的改动（见第 0 节） |

## 5. 实施记录（2026-09-29）

按代码分析得出的 8 个改进方向执行，本计划的阶段 0–4 都包含在内（阶段 5 设计规范收拢没有做，见 5.6）。另外按用户要求加了动画连贯性。

### 5.1 回退方式

| 项 | 做法 |
|---|---|
| 基准 | tag `refactor-baseline` = `ca1ca2a`（`feat/ai-native` 当时的 HEAD，含渲染引擎和插件代码块） |
| 分支 | 全部改动在 `perf/refactor`，放在独立工作区 `markdown 笔记-refactor`；`feat/ai-native` 没有任何改动 |
| 阶段 tag | `refactor-d0`（测量工具）、`refactor-d8`、`refactor-d7`、`refactor-d2`、`refactor-d1`、`refactor-d3`、`refactor-d4`、`refactor-d5`、`refactor-d6`、`refactor-motion`（按完成顺序） |
| 合并 | 用户试用确认后：`git switch feat/ai-native && git merge --no-ff perf/refactor`；合并后要撤销：`git revert -m 1 <合并提交>` |
| 不要了 | 不合并即可；或 `git worktree remove "../markdown 笔记-refactor" && git branch -D perf/refactor` |
| 数据兼容 | 偏好设置的键名、`.twain/` 下的文件格式都没变，新旧版本可以对同一个库来回切换 |

### 5.2 测量方法

`scripts/perf.sh <库> [标签]`：优化构建（保留调试场景），复制库到临时目录，跑 `TWAIN_SCENARIO=stress`，结果追加到 [`perf-log.md`](perf-log.md)。库是真实库的副本（397 篇笔记、10866 个文件，附件为空文件）。窗口在后台运行，已关闭 App Nap。每次按键的对比另用 `bench` 场景（每轮 runloop 一个键）。

### 5.3 结果（真实库副本，同一台机器）

| 指标 | 重构前 | 重构后 | 主要原因 |
|---|---|---|---|
| 空闲时主线程最长卡顿（打开空间 / 打开笔记，11 秒内） | 69 / 49 ms，每 11 秒 4–6 次 >16 ms | 1.2 / 1.3 ms，0 次 | 去掉 5 秒 tick；空间卡片不在 body 里读文件；观察集合只在真的变化时改 |
| 收起 / 展开侧栏时最长一帧 | 40 / 64 ms | 16.7 / 16.7 ms（一帧），0 掉帧 | 同上，外加每次打开笔记不再重建整棵侧栏树 |
| 收起 / 展开 Agent 面板最长一帧 | 41 / 36 ms | 26 / 33 ms | 同上 |
| 80 KB 笔记每键（bench 中位数） | 10 ms | 1.1 ms | 按键不再拷贝、比较全文，不再触发 SwiftUI 更新；行表增量更新 |
| 56 万字笔记每键（bench 中位数） | 15.5 ms | 10.4 ms | 同上；剩下的与行数成正比 |
| 段落聚焦开启时聚焦 / 失焦（80 KB） | 55 ms | 22–24 ms | 淡化改在绘制时做 |
| 连续打开 44 篇笔记（中位数） | 68 ms | 61–63 ms | 见 5.5 |
| 内存（整轮压测后） | 174 MB | 151 MB | 图片缓存有上限 |
| 单元测试 | 91 | 117 | Vault、行表、归属判断、缓存清理等进了 Core |

### 5.4 对原计划判断的更正

- **P6 的前提不成立**：在当前工具链上，给 `@Observable` 属性赋相同的值**不会**通知界面（实验验证）。真正每 3 秒刷新界面的，是对可观察数组做原地修改（`sessions.removeAll {…}`）——原地修改即使什么都没删也会通知。同理，每次打开笔记都对 `openFolders` 调 `insert`，让整棵侧栏重建。这两处才是空闲卡顿和切换笔记重建侧栏的原因。
- **P9（`center()` 从文首排版）实测不慢**：非连续排版下，长笔记末尾移动光标 0.1–0.2 ms，与开头一样，没有改。
- **P2（换文时重设样式）**：代码里已有 `swapping` 保护，压测未复现排版异常；**P1（窗口布局死循环）**：已被 `ce51c11`、`b855b54` 修复，本轮未复现。
- **打开笔记的时间主要不在我们的代码里**：模型更新 0.7 ms，编辑器换文与首屏样式约 6 ms，其余是 SwiftUI 视图图更新、布局和绘制，并按帧量化（约 30 ms 或 45 ms 两档）。

### 5.5 仍然存在的已知开销

| 项 | 现状 | 为什么没改 |
|---|---|---|
| 切换笔记约 60 ms | 侧栏 `List(selection:)` 在选中项变化时逐行比对整棵树，约占 8–10 ms；其余是 SwiftUI 布局和绘制 | 换掉原生 List 会失去系统侧栏的选择、键盘导航和外观，风险大于收益 |
| 大笔记每键约 10 ms | `MarkdownStyler.restyle` 的两轮按行遍历与行数成正比 | 需要把块状态也做成增量，改动面大，留待下一轮 |
| 打字时的绘制 | 采样里最大的一块是 AppKit 局部重绘时回贴整块图层 | 属于 AppKit 的图层机制，需要单独研究 |

### 5.6 各方向做了什么

| 方向 | 提交 | 内容 |
|---|---|---|
| 0 测量 | `5ee511c` | `stress` 场景、`scripts/perf.sh`、`perf-log.md` |
| 8 小修 | `6ec93aa` | HTTP 令牌缓存并常量时间比较；图片缓存上限（160 张 / 320 MB）；渲染磁盘缓存清理；删掉 Plume 迁移代码 |
| 1 性能 | `15d8de8` `67cd501` `cea4875` `f9df6dc` `72e458e` | 终端扫描不再 `main.sync`、增量读会话记录、`JSONLines.drain` 从 O(n²) 改为线性；规则状态缓存；去掉 5 秒 tick；空间卡片后台加载；观察集合只在变化时改；iCloud 未下载的笔记后台下载；详情栏拆成各自只读所需状态的视图；段落聚焦改在绘制时 |
| 2 库服务 | `c5d093d` | `Vault` 进 Core；`VaultListing` 一次遍历供侧栏、索引、快照共用；`VaultService` 在后台队列刷新并合并请求；agent 查询不再在主线程遍历库；自己的新建、改名、移动直接更新列表 |
| 3 拆分 AppModel | `ef736ad` `ef9b042` | `AppModel` 等标为 `@MainActor`；状态拆成 `Preferences`、`ChromeState`、`EditorState`、`AgentState` |
| 4 编辑器 | `f5a5952` | 正文按键时留在编辑器里，用到时才取；行表 `LineTable` 进 Core 并增量更新 |
| 5 进程封装 | `85c807b` | `CLIRunner` 统一启动 `claude -p`；删掉 `ModelCall` |
| 6 测试 | `92e0fe1` | `NoteFile`、`WriteAttribution`、`CacheFolder` 进 Core；测试 91 → 117 |
| 7 Swift 6 | `ff6a772` | Core、CLI、测试目标切到 Swift 6 严格并发；App 目标仍是 Swift 5 模式 |
| 动画 | `fa385b2` | `Motion` 统一曲线并尊重“减弱动态效果”；面板、文件夹、斜杠菜单、切换笔记、对话、卡片、批注、空间模块的过渡 |

阶段 5（设计规范收拢）没有做：它为已经撤销的视觉升级服务，本轮不需要。
