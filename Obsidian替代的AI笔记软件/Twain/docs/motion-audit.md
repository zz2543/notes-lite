# 共笔动效盘点

> 2026-09-29 · 分支 `ui/motion-more`（起点 tag `motion-more-baseline`），建在 `ui/motion-modes` 之上
> 用户在 设置 → 编辑器 → 动效 里选 **简洁 / 克制 / 活泼**，另有“完成时播放音效”。所有动画都按这三档取参数，系统开启“减弱动态效果”时一律退成 0.15 秒淡入淡出。曲线和规则集中在 `Sources/Twain/Motion.swift`。

## 怎么用这份表

- **角色**：`Motion` 里的曲线名。standard 是面板和页面，quick 是小控件，pop 是从一点冒出的东西，content 是数据变化，overlay 是提示条和命令面板。
- **简洁**：几乎都不动；只有提示条和命令面板保留原来就有的淡入。
- **克制**：快起慢停、不回弹。
- **活泼**：先蓄力、冲过头再落回；完成类的时刻有彩屑、触控板轻震和可选音效。

## 已经有过渡的地方

| 区域 | 变化 | 角色 | 活泼档额外的 | 实现 |
|---|---|---|---|---|
| 窗口 | Agent 面板、专注模式开关 | standard | — | `toggleAgent`、`toggleZen` |
| 窗口 | 提示条、命令面板出现 | overlay | 弹簧过冲 | `MainWindow` |
| 侧栏 | 文件夹展开、收起 | standard | — | `FolderRow` |
| 侧栏 | 新建、改名、移动、删除笔记和文件夹；新增、删除问库问题 | standard | — | 列表改动放进动画事务 |
| 侧栏 | 笔记行的“待审阅”圆点、“正在写入”转圈 | pop | — | `NoteRow` |
| 正文 | 切换笔记 | —（Core Animation） | 从下方 10pt 弹上来 | `EditorView.fadeIn` |
| 正文 | 勾选待办 | — | 蓄力、过冲、彩点、轻震、音效 | `EditorEffects.taskChecked` |
| 正文 | 公式、图表渲染完成；图片加载完成；callout 折叠展开；Tab 续写出现 | — | 时长稍长 | `EditorEffects.fadeNextDraw`：只截可见区域叠在上面淡出 |
| 正文 | 斜杠菜单出现；菜单里的选中高亮 | quick | — | `SlashLayer`、`slidingHighlight` |
| 正文 | 审阅横幅、只读横幅、写入中横幅 | standard | — | `Banners` |
| 正文 | 状态胶囊出现；“编辑中/已保存”圆点换色 | standard / quick | — | `StatusLayer` |
| 正文 | 专注模式的“退出专注”按钮 | standard | — | `ZenExit` |
| 正文 | 批注卡片出现、随正文移动、忽略或采纳后离开 | —（AppKit） | 离开时歪一下被甩出去；补位略过冲 | `AnnotationRail` |
| 页面 | 笔记 ⇄ 空间 ⇄ 问库 ⇄ 审阅 之间切换 | standard | — | `NoteDetail` |
| 审阅 | 接受一处改动 | pop | 卡片鼓起再回弹，对勾弹跳 | `HunkCard` |
| 审阅 | 拒绝后出现“原因”输入框；展开折叠的上下文 | quick | — | `HunkCard`、`ReviewView` |
| Agent 面板 | 切换会话；第一条回复替换空状态 | standard | — | `AgentInspector` |
| Agent 面板 | 新消息和步骤进入对话；步骤从转圈变成图标 | standard / pop | — | `transcript`、`ItemView` |
| Agent 面板 | “停止”按钮出现和消失 | pop | — | `sessionBar` |
| Agent 面板 | 回答提问后选项收进答案；审阅意见“已发回” | standard | 答案图标弹跳 | `QuestionCard`、`FeedbackCard` |
| Agent 面板 | 选择 Claude / Codex | quick | — | `AgentBar`（原来就有） |
| 流水线 | 步骤图标变化；下方关口切换 | pop | — | `PipelineCard` |
| 问库 | 新卡片到达；钉住、划掉、恢复；追问框和追问出现 | pop / quick / standard | — | `ResearchDeskView`、`CardView` |
| 空间 | 打卡 | — | 图标弹跳、整卡彩屑、轻震、音效 | `HabitsModule`、`ConfettiBurst` |
| 空间 | 数字、图表的新数据；“连续 N 天” | content | 连续天数图标弹跳 | `Loaded` |
| 空间 | 编辑模式切换；模块增删移动 | quick / standard | — | `SpaceView` |
| 空间 | 待办打勾后离开列表；“最近的笔记”重新排序 | standard | — | `TasksModule`、`QueryModule` |
| 命令面板 | 选中高亮 | quick | — | `slidingHighlight` |
| 设置 | 选择附件保存位置后出现的文件夹输入框 | standard | — | `AttachmentSettings` |
| 新手引导 | 翻页 | standard | — | `Onboarding`（原来就有） |
| 声音与震动 | 勾选待办、打卡、接受改动或批注、agent 运行结束 | — | 触控板轻震 | `Motion.feedback`，音效需在设置里打开 |

## 有意不加动画的地方

| 地方 | 为什么 |
|---|---|
| 打字、删除、粘贴 | 跟手最重要；任何过渡都会让字“慢半拍” |
| 光标、选中文字 | 光标已有自己的滑动和拖尾；选区跟随鼠标 |
| 侧栏搜索、命令面板随输入变化的结果 | 每个键都在变，动画只会让列表闪 |
| 侧栏选中高亮 | 由系统列表绘制，没有开放动画接口；强行替换会失去系统侧栏的外观和键盘导航 |
| 按钮按压 | 液态玻璃按钮自带按压反馈，再叠一层会打架 |
| 弹出框、菜单、sheet、设置窗口切页 | 系统自带动画 |
| 字数 | 数字在玻璃胶囊里滚动，连续切换 44 篇笔记后多占约 140MB 渲染缓存 |

## 性能核对（真实库副本，`scripts/perf.sh`）

| 档位 | 开关侧栏最长一帧 | 空闲卡顿 | 打字中位数 | 压测后内存 |
|---|---|---|---|---|
| 简洁 | 16.7 ms，不掉帧 | 无 | 1.0 ms | 153 MB |
| 克制 | 16.7 ms，不掉帧 | 无 | 0.9 ms | 144 MB |
| 活泼 | 16.7 ms，不掉帧 | 无 | 0.9 ms | 148 MB |

这一轮踩到并修掉的两个问题：

- 正文内容淡入最初用 `CATransition`，它会把整篇（很高的）正文图层栅格化，压测后多占约 22MB。改成只截可见区域的一张图叠在上面淡出后，内存回到原来的水平。
- Agent 面板切换会话最初带了一点位移，结果输入框背后的区域露空。去掉位移、只保留淡入后，截图与改动前逐像素一致。

## Inspora 一轮（2026-10-01～02，分支 `ui/motion-inspora`，tag `motion-inspora-baseline` → `-1` → `-2` → `-3a`…）

设计语言取自 inspora.design 展示的作品：**同一个物体原地变形**（胶囊长成面板、卡片折成一行）、**状态靠滚动换字**、**完成的东西收成一行**、**成组的东西叠放、悬停展开**、**一个字符的环境字形指示进行中**、**依次到达**。重的、好玩的效果只在“活泼”档。新增的 `Motion.morph / stagger / ambient` 在 `Motion.swift`，构件在 `MotionViews.swift`。

| 区域 | 变化 | 实现 |
|---|---|---|
| 提示条 | 多条提示叠成一摞，悬停展开；出错的带红色并在活泼档抖一下 | `ToastStack` |
| Agent 面板 | 单字符字形代替转圈（思考/搜索/读取/写入/运行各有花样）；状态文字滚动替换；输入框占位语轮换；改动完成后折成一行 | `GlyphSpinner`、`RollingText`、`RotatingPrompt`、`ChangeItem` |
| 审阅 | 处理过的改动卡折成一行，可“查看/收起” | `HunkCard` |
| 流水线 | 分段进度轨：完成实、运行中流动、等待你时呼吸（活泼档涟漪） | `PipelineTrack` |
| 侧栏 | “＋”原地长成菜单面板，选完缩回；新建、agent 状态行换字 | `NewBar`、`AgentStatusRow` |
| 正文 | 长笔记（≥3 个标题）左侧出现目录，钩子线随阅读位置滑动；点击滑到该处。滚动停稳 0.12 秒后才计算，打字不受影响 | `OutlineRail`、`Markdown.outline` |
| 正文 | agent 工作且面板关着时，状态胶囊上方出现一颗小胶囊：字形 + 滚动的“正在写入…”，结束变对勾后收起；点击打开面板 | `AgentIsland` |
| 正文 | 伴写气泡从右上角长出来 | `CompanionLayer` |
| 设置 | “拷贝”按钮原地变成“已拷贝 ✓” | `ConfirmButton` |
| 空间、新手引导 | 卡片/内容块依次升起 | `.arrive(i)` |

有意不做：状态胶囊里的“编辑中/已保存”不滚动（每次切换约多 1 ms，打字 p90 会涨）；目录不在每次滚动时计算（曾使打字 p90 从 9.6 涨到 12.9 ms）。

性能（`scripts/perf.sh`，活泼档）：打字 p90 约 9.5–10 ms（基线 9.6），压测后内存 148–152 MB（基线 147–148），侧栏开关不掉帧。回退：`git switch ui/motion-more`，或回到某个 tag。

## 第四轮：外观与动效的整体语言（2026-10-02，tag `motion-inspora-4a` … `-4j`）

这一轮不加功能，只统一“东西长什么样、怎么动”。

**表面。** 共笔自己画的东西一律是实色纸面：窗口底色、0.5pt 细边、柔和阴影（`SurfaceFill`、`.surface`、`.capsuleSurface`，按钮 `.soft` / `.solid`）。玻璃只留给浮在正文上、你一边写一边看的那一层：状态胶囊、Agent 小岛、命令面板（`.hoverGlass`），系统工具栏和侧栏保留系统材质。可点击的表面在指针下浮起一点（`hoverLift`）。

**从哪来，回哪去。** 弹出的东西从点它的地方长出来，关掉时缩回去（`GrowPanel`）：笔记名片、模型列表、新建空间；命令面板点放大镜时从右上角长出，⌘K 时从顶部。页面从它“住”的地方进来：空间和问库从侧栏一侧，审阅从笔记上方的横幅（`.page(from:)`）；正文页只淡入（缩放或模糊会把整篇栅格化）。

**变的是字，不是整块。** 数量和状态行滚动到新值（`numericText`、`RollingText`）：横幅、工具栏和审阅页的改动数、问库卡片数、流水线关口、会话栏。

**一直在动的东西交给 Core Animation。** 字形加载符、流水线分段、Agent 状态球都是图层动画或预先画好的循环帧，主线程每帧不做事。教训：SwiftUI 里每帧变化的视图（`TimelineView` 换字、永远循环的 `phaseAnimator`）会让整个窗口每帧重新布局，Agent 面板开着时 CPU 28–38%；改成图层动画后 3–4%，和空闲一样。状态球同理，逐帧绘制约 5%，预渲染循环约 0.6%。

| 新东西 | 在哪 | 实现 |
|---|---|---|
| Agent 状态球：待命是实心点，思考/搜索/读取/写入/运行各有点阵流动，等你时外圈呼吸，出错变红 | Agent 输入框左侧 | `AgentOrb.swift` |
| 侧栏树线：每个展开的文件夹下一条细竖线 | 侧栏 | `TreeGuides`（行不读选中状态，切换笔记不重画整棵树） |
| 目录、字数统计的修复：Windows 换行的标题、切换笔记时旧统计覆盖新笔记、点击后钩子弹回 | 正文 | `Markdown.outline`、`recountWords`、`scrollToLine` |

| 跑完的流水线、审阅过的改动：同一张卡片像抽屉一样合成一行，下面的对话跟着收拢 | Agent 面板 | `PipelineCard`、`ChangeItem`（状态变化放在动画事务里） |
| 深色模式下高度用亮度表达：表面比页面亮一点，长出的面板更亮 | 全局 | `SurfaceFill(raised:)` |
| 活泼：删除正在看的笔记，页面揉成纸团甩向角落 | 正文 | `EditorEffects.crumple` |
| 活泼：打开空间，封面以侧栏为书脊翻开 | 页面 | `SpaceCover`、`chrome.spaceCover` |
| 输入框背后探出一条标签：Agent 会看到哪篇笔记、选中了几行；变化时缩回再滑出 | Agent 面板 | `ContextTab`、`editor.selectedLines` |
| 设置里的动效风格自己演示：「+」长成面板、卡片折成一行 | 设置 | `MotionPreview` |

这一轮顺带修掉的问题：`Group` 上的修饰符会复制到每个分支（页面容器、折叠卡片改用 `ZStack`）；长出的面板、命令面板、「+」菜单点外面（包括 Agent 面板上）都会关；收起 Agent 面板会关掉模型列表；切换笔记会关掉笔记名片（否则「保存」会把上一篇的摘要写到这一篇）；删除未保存的当前笔记不会再被写回；移到废纸篓失败会提示。场景 `clicktest` 用真实点击事件走一遍这些交互。

调试：`TWAIN_SLOWMO=10` 把所有 SwiftUI 过渡放慢十倍，截图能拍到动画中途；场景 `later:<秒>:<场景>`、`noteinfo`、`newspace`、`tree:<笔记>`。显示器睡眠时帧数为 0、截不到图，先 `caffeinate -u`。

性能（`scripts/perf.sh`）：打开笔记中位数 52–57 ms（3c 时 61 ms），打字 p90 1.3–1.9 ms，压测后内存 139–143 MB（3c 时 152 MB），侧栏和 Agent 面板开关偶有 1 帧掉帧，与之前相同。

## 回退

| 想要 | 做法 |
|---|---|
| 去掉第四轮（实色表面、长出的面板、状态球…） | `git switch -c 某个新分支名 motion-inspora-3c`（原分支保留），或从某个 `motion-inspora-4x` tag 开分支 |
| 去掉这一轮盘点补的动效 | `git switch ui/motion-modes`（或删除分支 `ui/motion-more`） |
| 去掉整个动效设置 | `git switch perf/refactor` |
| 回到重构之前 | 主分支 `feat/ai-native` 从未改动；或 tag `refactor-baseline` |
