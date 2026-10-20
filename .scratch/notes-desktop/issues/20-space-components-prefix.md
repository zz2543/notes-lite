# 20: 空间组件、样式包与新接口前缀

**What to build:** 空间主页可使用与品牌无关的新接口、组件与样式变量；旧版 Agent 写的空间主页不用改就能运行；编写说明附类型声明。

**Blocked by:** 19

**Status:** ready-for-agent

**Progress:** completed

- [x] 统计、图表、日历、快速录入、记录列表五个组件，入场使用动效预设，字体跟随排版设置
- [x] 样式变量跟随深浅色与外观
- [x] 新前缀的接口、组件、变量与 meta；`lb` 系列作为永久兼容别名
- [x] 编写说明更新为新路径与新名称，附 TypeScript 类型声明
- [x] 用一份旧版空间主页样例验证原样运行

## Comments

### 2026-10-20 实现（分支 `ticket/20-space-components`）

提交：65f7990（meta 新名与别名）、a687142（样式包、组件、`space` 接口）、0900310（e2e）、54cc8fa（编写说明 v3 与类型声明）。

- **新前缀 `space`**：接口对象 `space`、组件 `space-stat/-chart/-calendar/-quick-add/-records`、变量 `--space-*`、class `.space-*`、meta `space-scope`/`space-icon`、页面 `body.space-page`。`lb` 对象（与 `space` 同一个对象）、`lb-*` 组件（子类别名）、`--lb-*` 变量、`.lb-*` class、`lb-scope`/`lb-icon` meta 永久保留。文件同时有两种 meta 时以 `space-*` 为准；编辑旧空间时沿用文件原来的 meta 名，不会出现第二个范围。新建空间写 `space-*`。
- **样式包**（`src/main/spaceKit/style.css`）：页面先注入应用自己的 `tokens.css`，`--space-*` 都取设计规范的变量（卡片色、`--line`、`--card-radius`、强调色预设、正文排版），因此跟随外观、深浅色（`nativeTheme`）与以后的“大胆高饱和”。页面设置（`spaceKit.ts` 的 `spacePageSettings`：排版变量、强调色、四种弹簧预设按动效强度生成 CSS `linear()`、卡片入场幅度）放在 `style#space-settings`，设置或系统强调色改变时经空间页 preload 推送替换，不重载页面。
- **组件**（`src/main/spaceKit/components.js`）：移植旧版 components.js；字号改为 em（随排版字号），图表/日历入场用“展开”，数字变化与记录新增用“滑移”，按压用“轻弹”；卡片入场为“浮现”+幅度（强：28px、0.92、模糊 6px、间隔 0.06s，模糊单独缓动），`fill: backwards` 结束后不留样式；减弱动态效果只淡入。动效预设从 `renderer/src/motion.ts` 移到 `shared/motion.ts`（渲染端重新导出），主进程因此打包了 motion 的 `spring`（启动预算测试仍通过）。
- **编写说明 v3**：新名称、动效/排版变量、“旧名称”对照表、`space.d.ts` 类型声明（`spaceTypes`）。
- 证据：`npm run typecheck`；`npm test` 152 通过 / 1 跳过（新增 `tests/core/spaceGuide.test.ts` 3 个，其中类型声明连同页面脚本交给 tsc 编译，误用必须报错；`spaces.test.ts` +2、`spaceNoteWrites.test.ts` 别名下的 writePage）；`npm run test:e2e` 78 通过，新增 `tests/e2e/space-components.spec.ts` 4 个：旧版样例（`tests/e2e/samples/legacy-homepage.html`，即 `NotesLite/evidence/spaces/agent-homepage.html` 原样）组件出数据、快速录入写入磁盘；新名称下五个组件与自写脚本；卡片入场声明的预设、延迟、最终状态与“轻”档、减弱动态效果；排版/强调色/深色改变后页面跟随。

决定与留给后续：
- 空间页里的“思源宋体/Source Serif”：字体栈正确，但内置字体文件只在应用页加载，空间页里回落到系统宋体（macOS 为 Songti SC）。如需一致，可由 `notes-space://` 协议提供 `@fontsource` 文件 → 任务 22 走查时决定。
- 组件报错目前只写 console；错误条与“复制错误给 agent”、组件在 `space.on("change")` 推送后重绘（快速录入后统计、记录列表刷新）→ 任务 21。
- 设计规范未列出的新变量：`--space-*` 全部、`--space-card`（卡片上的卡片，页面色混 2.5% 文字色）、`--space-chart-6`（蓝绿混色）→ 任务 23 核对。
- 任务 16 未勾的“空间主页通过样式变量使用同样的字体字号”由本任务完成（16 的勾选由编排者处理）。

### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 两平台通过（macOS 首轮一个助手栏安装指引用例偶发失败，重跑通过）：https://github.com/zz2543/notes-lite/actions/runs/39388082390
