# 03: 设计规范落地：材质、颜色与动效预设

**What to build:** 窗口呈现原生材质版的观感：系统材质、浮起的正文卡片、深浅色、强调色；所有交互使用四种动效预设与默认“强”档。

**Blocked by:** 01

**Status:** ready-for-agent

**Progress:** completed

- [ ] macOS vibrancy、Windows 11 Mica；Windows 10 退回不透明底色
- [x] 设计规范中的颜色、尺寸、阴影、圆角以变量形式定义，组件只引用变量
- [x] 深浅色跟随系统，深色为单独一套取值
- [x] 轻弹、滑移、展开、浮现四种预设与轻/标准/强三档换算集中定义；高频预设回弹不随强度放大；模糊单独缓动
- [x] 选中底板滑移、悬停底色、按压回弹按设计规范实现
- [x] 系统开启减弱动态效果时只保留不透明度变化

## Comments

### 2026-10-20 实施记录

分支 `ticket/03-design-system`。提交：`9c85d5e` 动效预设、`82b472f` 窗口材质（设计变量移入 `tokens.css`）、`8ccb4b9` 全部颜色尺寸阴影变量、`8f48355` 系统强调色、`f4fa26a` 选中底板滑移、`caa91cc` 悬停与按压、减弱动态效果用例，以及合并 `feat/notes-desktop` 的 `22fdfa5`。

本地验证（macOS，Apple Silicon）：`npm run typecheck` 通过；接缝 A `npm test` 53 个用例通过，接缝 B `npm run test:e2e` 18 个用例通过。新增：

- `tests/core/motion.test.ts`：三档下四种预设与“专注”的取值逐项对照设计规范表格；模糊单独缓动；幅度系数；减弱动态效果下只剩不透明度变化。
- `tests/core/window-material.test.ts`：材质判定与窗口参数。
- `tests/e2e/design-system.spec.ts`：窗口材质与兜底底色；系统强调色；全部变量在浅色与深色下解析为设计规范的值，组件引用变量；选中底板逐帧经过中间位置滑到新行；悬停只加底色不浮起；按压以弹簧缩到 0.97 再回弹；减弱动态效果下底板直接跳转、按压不缩放、无模糊。

实施中的决定：

- 预设集中在 `src/renderer/src/motion.ts`（纯函数 `motionPresets(intensity, { reduced })`，默认“强”）；`MotionProvider` 提供给组件，并实时跟随系统“减弱动态效果”。CSS 过渡用的 `--spring-*` 由同一组预设经 Motion `spring()` 生成 `linear()` 曲线写到根元素。模糊按各预设的 `filter` 单独缓动。减弱动态效果下位移、缩放、模糊、布局立即到位，不透明度按预设时长淡变（无回弹）。
- 幅度表只落了按压缩放（`--press-scale` 0.97，图标按钮 0.89；属高频，不随强度放大）和幅度系数 `amplitude`。切换笔记、浮层、空间卡片等的具体距离，由实现这些转场的任务按“标准值 × amplitude”加进 `motion.ts`。
- 材质判定是纯函数 `src/main/material.ts`：macOS 用 `vibrancy: "sidebar"`，页面透明；Windows 11 22H2（build 22621）起且窗口无边框时用 Mica；其余为不透明 `--win-fallback`。有材质时不设 `backgroundColor`，Electron 默认透明。真实窗口没有材质时一律不透明，所以 `--win-fallback` 取不透明值（设计规范里的 rgba 版本只适用于原型的模拟壁纸）。
- 强调色：每个新窗口读一次系统强调色（macOS、Windows），读不到用 `#0a84ff`；预设色定义为 `--accent-*` 变量。
- 合并时把任务 04（`organize.css`）与 06 的局部变量并入 `tokens.css`，改用设计规范的名称（`--float-*` → `--overlay-*`，`--segment-*` → `--segmented-*`）；搜索结果也用滑移底板。

留给后续任务：

- Windows 11 Mica：Electron 只在无边框窗口下把 Mica 延伸到页面下方（有边框时页面区域会是黑色）。当前 Windows 窗口仍带系统边框，所以暂用不透明底色；任务 22 做自绘标题栏时把 `frameless` 改为 true 即可启用，并在 Windows 11 真机上人工核对观感。第一项验收因此保持未勾选。
- 运行中跟随系统强调色变化、在设置中选择预设色与动效强度：任务 15。
- 分段控件（就地搜索范围）的选中底板仍是静态样式，未接滑移：任务 23 动效审查时统一。
- 本机运行时，真实鼠标停在窗口上会干扰悬停/按压用例，偶尔失败；CI 上没有真实鼠标。

### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 在 macOS 与 Windows 均通过：https://github.com/zz2543/notes-lite/actions/runs/39291544784 。CI 上两个依赖帧时序的用例改为检查正在运行的过渡与 1px 内的位置（提交 979f5b4、bae9c12）。

### 2026-10-20 里程碑代码审查

`.primary` 文字改用 `--on-accent`，箭头宽度与图标间距改为变量，设计规范写明 @ 提及列表算作菜单：`dd74676`。
