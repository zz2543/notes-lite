# 15: 设置面板：层级清晰与可视化控件

**What to build:** 设置是一张浮起的玻璃面板，层级清晰、分组明确；数值项都用滑块等可视化控件调整并立即生效。提供外观、强调色、笔记列表详细程度、动效强度等设置。

**Blocked by:** 03

**Status:** ready-for-agent

**Progress:** completed

- [x] 左侧分类、右侧分组，每组有标题与简短说明，项目对齐、间距一致
- [x] 控件库：带实时数值的滑块、分段控件、色板、开关、带预览的选项；不使用纯文本输入数值
- [x] 外观（跟随系统/浅色/深色）、强调色（跟随系统与预设色）、笔记列表详细程度（简洁/标准/详细，列表“…”菜单同步）、动效强度（轻/标准/强，默认强）
- [x] ⌘, / Ctrl+, 打开，Esc 关闭，“浮现”入场
- [x] 设置持久保存在应用中，不写入笔记库

## Comments

### 2026-10-20 实施记录

分支 `ticket/15-settings-panel`，7 个功能提交（`a1fc6d5` 面板与快捷键、`be54bf0` 外观与设置存储、`f76c04d` 强调色、`dc129db` 动效强度、`6fe4b16` 摘要、`23ef5b0` 列表详细程度、`dd907c1` 浮现入场）。

本地验证（macOS）：`npm run typecheck` 通过；`npm test` 81 个用例通过；`npm run test:e2e` 37 个用例通过。新增：

- `tests/e2e/settings.spec.ts`（6 个）：快捷键打开、Esc 关闭、分类与分组；浮现入场逐帧（起始缩放 < 0.95 且有模糊，强档回弹越过 1，最终缩放 1、无模糊）；外观固定浅/深色并在重启后保留、笔记库内文件不变；强调色预设与运行中跟随系统强调色变化；列表三档与“…”菜单、设置面板互相同步；动效强度默认强、改为轻后弹簧变短并在重启后保留。
- `tests/core/settings.test.ts`：快速连续写入设置不丢失；未知或缺失的设置值读作默认值。
- `tests/core/markdown.test.ts`、`library.test.ts`：摘要（移植旧版 `NotePreview`）与按文件夹读取摘要。
- `tests/core/motion.test.ts`：浮层进入/退出的幅度按三档取值。

实施中的决定：

- 设置模型在 `src/shared/preferences.ts`（字段、可选值、默认值、`readPreferences` 容错读取），存于 `settings.json` 的 `preferences`。主进程启动时读入内存，预加载脚本同步取一次，首帧即是用户的设置；修改经 `setPreferences` 写盘（写入排队，避免并发写坏文件）。
- 外观由主进程 `nativeTheme.themeSource` 实现，页面与窗口材质一起切换。Playwright 默认把页面固定为浅色，测试里用 `emulateMedia({ colorScheme: null })` 解除。
- 强调色：`useAccent` 写 `--accent`（预设为 `var(--accent-<name>)`）；主进程监听 `accent-color-changed`（Windows）与 `AppleColorPreferencesChangedNotification`（macOS），运行中把新系统强调色推给页面。`applyAppearance` 不再写强调色。
- 列表详细程度：标准显示弱化日期（今天显示时间，今年显示“M月D日”，更早显示完整日期）；详细另读摘要（`readSummaries` 只读每篇前 8 KB，仅在详细档才请求）。“…”菜单复用整理功能的 `ContextMenu`，新增 `menuitemradio` 选项。
- 浮层进入/退出幅度加入 `motion.ts` 的 `overlay`（标准值 × amplitude），对话框等其他浮层可直接取用。
- macOS 应用菜单加入“设置…”，Windows 放在“文件”菜单；快捷键由页面处理，欢迎页也能打开。

扩展点与留给后续任务：

- 新设置：在 `shared/preferences.ts` 加字段与默认值，在 `SettingsPanel.tsx` 的 `pages` 加页面（任务 16 排版页）或往已有页面加 `SettingsGroup`（任务 17 导航模式放“通用”）。
- 控件库 `controls.tsx` 中的滑块（带实时数值）与开关已实现但本任务没有使用者，接缝 B 覆盖分别留给任务 16（排版滑块）与任务 10/11（光标动画、输入动画开关，放在“动画”页）。
- 面板内间距、色板与预览条尺寸为设计规范未列出的新变量（`tokens.css` 中 `--settings-*`、`--swatch-*`、`--preview-bar*`），任务 23 动效与观感审查时一并核对。

### 2026-10-20 完成

合并后 macOS CI 有依赖帧率的用例不稳，修复后（4be26c5 顺带修了输入法延后保存与冲突的一个真实问题；23b3750、8dce2db 改测试）CI 两平台通过：https://github.com/zz2543/notes-lite/actions/runs/39357929607 。合并 15 后 macOS CI 虚拟机冷启动由约 1.1 s 升到约 1.7–1.9 s（本机 M4 不变，约 0.46 s）；按用户要求启动优化放到所有功能完成后。
