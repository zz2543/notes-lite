# 留白「空间」实测记录

日期：2026-10-18。机器：Apple M4，macOS 27.0.1。工具链：Swift 6.2（`swift test`）。规格：[空间规格](../../../notes-desktop/docs/specs/spaces-spec.md)；任务：[任务索引](../../../.scratch/notes-lite-spaces/README.md)。

## 自动化测试

完整结果见 [test-results.txt](test-results.txt)：68 个测试通过，1 个失败。

- **失败的那个是原有问题，不是本次引入的。** `EditorWorkflowTests.testCaretGeometryNavigationCompositionAndListExit`（插入光标几何像素断言，例如期望 101、实际 102）在本次开始前未修改的代码上以完全相同的数值失败。和空间功能无关，没有处理。
- 主接缝（lb 请求处理，JSON 进 / JSON 出，临时笔记库）：`SpaceAPITests`、`SpaceRecordWriteTests`、`SpaceNoteWriteTests`，覆盖：
  - 记录表定位、占位符、类型推断、过滤排序；
  - 范围拒绝（`..`、符号链接、隐藏目录、`.留白/`、其他空间文件、修改自身 `lb-scope`、范围外笔记链接到被改名的笔记）；
  - 写记录与写笔记；
  - 逐条撤销、重开后撤销、30 天清理、撤销冲突。
- 空间库：`SpaceLibraryTests`，覆盖：
  - 空间文件与 meta；
  - 提示词里的记录表（排除代码块和范围外的表）；
  - 编写说明覆盖更新；
  - 顺序持久化；
  - 删除不动笔记；
  - 改名或移动后同步路径（包括不写 `.md` 的 source）。
- 文件监听：`FileWatchingTests`，覆盖外部新建、修改、删除，干净笔记跟随磁盘，有未保存输入时报告冲突，隐藏目录的变化只通知订阅者。
- 真实窗口端到端：`SpaceWorkflowTests`，用真实的 `NoteWindow` 加 `WKWebView` 和临时库，不用 mock，覆盖：
  - 组件渲染；
  - `lb-quick-add` 写进磁盘、日期默认今天、进入操作记录、出现写入提示；
  - 页面自己写入和外部修改都能实时刷新；
  - 撤销；
  - 新表保持字段顺序；
  - 错误条以及错误行号指向空间文件；
  - agent 重写空间文件后自动重载；
  - iframe 里拿不到 `lb`，页面不能用脚本跳走；
  - 打开笔记进入编辑器，点「主页」回到同一个页面。

## 性能

- **文件监听延迟**：从外部写入到笔记列表出现，每档各 10 次，release 构建。
  - 50 篇笔记：中位数 19 ms，p90 21 ms；
  - 2000 篇笔记（每篇约 300 行）：中位数 75 ms，p90 76 ms。
  - 扫描在后台执行，不阻塞主线程。
- **笔记库扫描**：2000 篇，release 构建。
  - 首次完整扫描 268 ms，应用打开笔记库时改为在后台执行（`open(_:scanInBackground:)`），扫描完成后打开第一篇笔记；
  - 之后的增量刷新 85 ms，正文和摘要都复用缓存。
  - 剩下的时间主要花在目录遍历上。
  - 测试里调用的同步 `open(_:)` 和保存后的 `refresh()` 仍在调用它的线程上执行。
- `lb` 请求在每个空间主页自己的串行队列上执行，不在主线程上。
- 没有用户确认过的性能门槛，以上只是记录实测结果。

## 原生应用实测截图（深色为系统外观，浅色通过 `-NSRequiresAquaSystemAppearance YES` 启动）

| 截图 | 内容 |
|---|---|
| [empty-home.jpg](empty-home.jpg) | 空间模式：左栏空间列表，中栏范围树（顶部「主页」），右栏「让 agent 生成主页」 |
| [live-refresh-and-scope-error.jpg](live-refresh-and-scope-error.jpg) | 外部追加一行后页面自动刷新；页面读范围外笔记被拒绝，显示错误条和「复制错误给 agent」 |
| [widgets-dark.jpg](widgets-dark.jpg) | `lb-calendar`、`lb-records`、`lb-stat` |
| [quick-add-dark.jpg](quick-add-dark.jpg) | `lb-quick-add` 按表头和字段类型生成输入框 |
| [agent-homepage-dark.jpg](agent-homepage-dark.jpg)、[agent-homepage-light.jpg](agent-homepage-light.jpg) | 按新建提示词生成的健身空间主页，深色和浅色；浅色图底部是从 CDN 加载的 Chart.js 环形图 |
| [write-notice-and-error-bar.jpg](write-notice-and-error-bar.jpg) | 页面脚本自己写入 3 条记录后的「主页刚修改了 3 条记录 · 查看」，以及未捕获错误的错误条 |

## 按提示词生成主页

- 先用留白的新建流程（`SpaceLibrary.create` 和 `prompt(for:)`）生成空间文件和提示词，见 [new-space-prompt.txt](new-space-prompt.txt)，路径已替换成 `<笔记库>`。
- 主页由本次实现所用的外部 agent（Claude Code）按提示词和自动生成的编写说明写成，见 [agent-homepage.html](agent-homepage.html)。
- 主页同时用了组件、自写脚本（连续训练天数）和网络库（Chart.js）。
- 首次启动时 CDN 加载较慢，期间后面的内联脚本暂时不运行。编写说明已补充提醒：先用组件显示数据，再检查外部库是否已加载。

## 没有覆盖或需要注意的地方

- **以下界面没有在原生应用里手动点击验证**，交互由测试或代码保证：
  - 操作记录面板（「查看差异」、撤销按钮）；
  - 拖动排序的落点指示；
  - 空间右键菜单；
  - 删除确认。
  - 测试环境无法驱动原生菜单和拖放。
- **文件夹改名或移动后的路径同步**，逻辑已经实现并测试，但留白目前没有改文件夹名的功能，`lb.rename`/`lb.move` 也只针对笔记，所以目前只会在测试里触发。
- 在 Finder 或外部 agent 里直接改名或移动笔记时，空间文件里的路径不会自动同步，只有在留白里或通过 `lb` 操作时才会同步。
- 空间改名后，它的 localStorage 界面偏好不会跟着迁移；删除空间时会一并清除。
- 术语：新建空间时复制给 agent 的那段文字，规格（D6）和代码都叫「提示词」，但术语表把「提示词」列为「编写说明」的避免用词。这是术语表缺一个概念，需要用户决定怎么命名。
