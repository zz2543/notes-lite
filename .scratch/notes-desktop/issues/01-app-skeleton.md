# 01: 应用骨架与打开笔记库

**What to build:** 打开应用后可以选择一个本地文件夹作为笔记库，下次启动自动打开；双栏导航显示文件夹树与当前目录内容；点击笔记能看到它的原文。项目在 macOS 与 Windows 上都能构建并通过冒烟测试。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

**Progress:** completed（2026-10-19，证据见 Comments）

- [x] Electron + TypeScript + React 应用位于自包含的 `notes-desktop/` 目录，不依赖仓库其他目录
- [x] 首次启动选择笔记库，之后记住并自动打开；可以切换笔记库
- [x] 双栏导航：文件夹树与当前目录内容（直属子文件夹在前、直属笔记在后，不汇总后代）
- [x] 选中笔记显示其 Markdown 原文（只读即可）
- [x] 核心库与界面分离：核心库只依赖 Node 文件系统能力，有一个对临时笔记库的 Vitest 用例
- [x] 一个 Playwright 驱动 Electron 打开临时笔记库的冒烟用例
- [x] CI 在 macOS 与 Windows 上构建、运行两类测试并产出安装包（不签名）

## Comments

### 2026-10-19 实施记录

提交：`3778ecd`（原型移出工作分支，保留在分支 `prototype/notes-desktop-ui`）、`ec7ff6f` 核心库、`9d83fda` 应用骨架、`90225be` Playwright 冒烟、`1886769` CI，以及其后的审查修复提交。

本地验证（macOS，Apple Silicon，Node 22，Electron 44.5.1）：

- `npm run typecheck` 无错误。
- 接缝 A `npm test`：7 个 Vitest 用例通过（当前目录内容的顺序与不含后代、隐藏项、按修改时间排序、可展开标记、原文逐字保真含 CRLF、库外与隐藏路径及链接越界被拒绝、打开非文件夹报错）。
- 接缝 B `npm run test:e2e`：2 个 Playwright 用例通过（首次启动选择笔记库并浏览、文件夹再次点击收起、原文逐字显示；重启后记住、切换笔记库、记住的笔记库丢失时欢迎页说明原因）。
- `npm run dist` 产出 `notes-desktop-0.1.0-arm64.dmg`；app.asar 672K（界面依赖已打进包，不再附带 node_modules）；ad-hoc 签名通过 `codesign --verify --deep --strict`；用 Playwright 启动打包后的应用能打开笔记库并读出原文。

未验证：CI 工作流 `.github/workflows/notes-desktop.yml` 尚未运行（分支未推送），Windows 上的构建、两类测试与 NSIS 安装包均未实际验证，最后一条验收标准保持未勾选。

实施中的决定：

- 笔记库根目录作为文件夹树第一行（以文件夹名显示），默认选中并展开，使根目录下的笔记可达，满足“默认选中一个文件夹”。
- 当前目录内容按旧版 `NotesCore`：子文件夹按拼音/自然顺序，笔记按修改时间新到旧；笔记只显示标题（列表详细程度默认“简洁”）。
- 文件夹点击（选中并展开、再次点击收起）已一并实现并有测试，任务 04 对应验收项可直接核对。
- 侧栏底部“笔记库名 ⇅”按钮用于切换笔记库，沿用原型；菜单“文件 › 打开笔记库…”（⌘O / Ctrl+O）同样可切换。
- 颜色与尺寸已按设计规范变量命名，窗口暂用不透明 `--win-fallback`；原生材质与动效留给任务 03。
- macOS 用 ad-hoc 签名（无需证书），下载的安装包首次打开需右键“打开”或在系统设置中允许，不会被报“已损坏”。

留给后续任务：Windows 下为红绿灯预留的 52px 拖拽条会在侧栏顶部留出空白，窗口边框与窗口内菜单按钮由任务 22 处理；渲染进程包未压缩（约 670 KB），由任务 07 按启动耗时实测决定是否处理。

### 2026-10-19 CI 验证

分支推送后，GitHub Actions 运行 [39220263723](https://github.com/zz2543/notes-lite/actions/runs/39220263723)（提交 `98bc4d7`）在 `macos-latest` 与 `windows-latest` 上全部通过：类型检查、接缝 A、接缝 B、electron-builder 打包；产物 `notes-desktop-macOS`（dmg，约 120 MB）与 `notes-desktop-Windows`（NSIS exe，约 106 MB）。Windows 安装包尚未人工安装走查，留给任务 22。全部验收标准已满足，记为 completed。

