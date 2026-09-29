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

## 回退

| 想要 | 做法 |
|---|---|
| 去掉这一轮盘点补的动效 | `git switch ui/motion-modes`（或删除分支 `ui/motion-more`） |
| 去掉整个动效设置 | `git switch perf/refactor` |
| 回到重构之前 | 主分支 `feat/ai-native` 从未改动；或 tag `refactor-baseline` |
