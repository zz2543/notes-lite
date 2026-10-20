# 16: 排版设置与内置字体

**What to build:** 在设置的排版页调整字体、字号、行距、段距、版心宽度、标题比例与中英文间距，右侧用当前笔记实时预览；内置思源宋体与 Source Serif 4。

**Blocked by:** 08, 15

**Status:** ready-for-agent

**Progress:** completed

- [x] 正文、标题字体可选预设与系统已安装字体
- [x] 字号、行距、段距、版心宽度、标题比例使用滑块，预览带动效同步变化
- [x] 中英文自动间距只影响显示，不改文件
- [x] 随应用分发思源宋体（常规、半粗）与 Source Serif 4，附 OFL 许可
- [ ] 默认值与设计规范一致，空间主页通过样式变量使用同样的字体字号（默认值已达成；空间主页部分见下，留给任务 20）

## Comments

### 2026-10-20 实施记录（分支 `ticket/16-typography-settings`）

实现：
- 模型 `src/shared/typography.ts`：字段、设计规范的范围与滑块步长、默认值，`readTypography` 容错读取（越界夹到范围并对齐步长，未知字体或错误类型取当前值），`typographyVariables` 把排版换成 CSS 变量（`--body-font`、`--heading-font`、`--code-font`、`--body-size`、`--body-leading`、`--para-gap`、`--measure`、`--heading-ratio`、`--text-autospace`）。`Preferences.typography` 存于 `settings.json`，修改时可只带变的字段。
- 页面 `useTypography` 把变量写在根元素上，编辑器、预览立即跟随。设置面板新增“排版”页（`TypographySettings.tsx`）：字体（预设卡片以各自字体显示“永 Aa”，下方是系统已安装字体菜单）、版式五个滑块、中英文自动间距开关；右侧预览是当前笔记（取编辑器中尚未保存的文字；没开笔记时用示例），用与编辑器相同的 `typesetView` 只读排版，缩小一半绘制以便看出版心；字号、行距、段距、版心与标题字号以“滑移”弹簧的 CSS 过渡变化，减弱动态效果时不过渡。
- 字体预设：系统、思源宋体、Source Serif（Source Serif 4 + 思源宋体）、等宽；代码字体为平台等宽或已安装字体。已安装字体由 Chromium Local Font Access（`queryLocalFonts`）在第一次打开菜单时列出，存为 `installed:<family>`，后接该角色的默认字体。
- 中英文自动间距用 CSS `text-autospace`（Electron 44 的 Chromium 支持），只影响显示；Markdown 源码视图始终不加间距。
- 内置字体：`@fontsource/noto-serif-sc@5.3.0`（400、600；思源宋体的 Google 构建，字形相同）与 `@fontsource-variable/source-serif-4@5.3.0`（字重与光学尺寸可变，含斜体），均为 OFL-1.1，按 Unicode 分片、用到才读。`electron.vite.config.ts` 的 `woff2Only` 插件去掉 WOFF 备份（渲染产物约 8 MB）。许可原文复制到 `resources/licenses/fonts/`（附 README 说明来源与版本），`electron-builder.yml` 的 `extraResources` 随应用分发。
- 控件库的滑块与开关此前没有样式，本任务补上（`settings.css`）。

验证（macOS）：`npm run typecheck`；`npm test` 147 个通过（新增 `tests/core/typography.test.ts` 5 个、`font-licenses.test.ts` 2 个）；`npm run test:e2e` 合并前 70 个全部通过，合并 `feat/notes-desktop`（含任务 19）后重跑 typecheck、`npm test` 与 typography/settings/space-page/markdown 四个 e2e 文件 21 个通过。新增 `tests/e2e/typography.spec.ts`（3 个）：滑块默认值与设计规范一致、预览为当前笔记并声明过渡、调整后预览与编辑器的最终字号/标题字号/版心/行距、重启保留、笔记库与文件不变；内置字体可加载（思源宋体 400/600、Source Serif 4）、预设切换正文与标题字体、已安装字体菜单列出并应用；关闭自动间距后“了3”变窄且文件不变。`settings.spec.ts` 分类改为 通用、排版、笔记列表、动画。

决定：
- 界面写“思源宋体”，实际字体名 Noto Serif SC（同一设计，OFL 保留名 “Source” 不用于改动过的版本）。
- 新增设计规范未列出的变量：`--font-mono/-songti/-serif`、`--slider-*`、`--switch-*`、`--typography-*`、`--typeset-preview-scale`、`--font-sample-size`（`tokens.css`），任务 23 核对。

留给后续：
- 空间主页使用同样的字体字号 → 任务 20（样式变量与组件）：目前空间页没有样式变量。可在 `main/spacePages.ts` 里用 `typographyVariables(preferences.typography)`（shared，Node 可用）生成变量，`--lb-font`/`--lb-mono` 指向 `--body-font`/`--code-font`，排版改动时推送给已打开的空间页。
- Windows 上 `queryLocalFonts` 与 `text-autospace` 的表现 → 任务 22 走查。

### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 CI 两平台通过：https://github.com/zz2543/notes-lite/actions/runs/39386345223 。合并后修过的 CI 问题：慢机器上的撤销分组与助手栏宽度过渡用例、字体许可证在 Windows 检出时被改成 CRLF（加 `.gitattributes`）。
