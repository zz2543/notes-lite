# notes-desktop

笔记软件跨平台桌面版的开发代号，产品新名称待定。以 Electron 单一代码库重写，取代 macOS 原生旧版 `NotesLite/`，决定见 [ADR 0004](docs/adr/0004-cross-platform-desktop-rewrite.md)。

本目录自包含，可整体移出仓库成为独立项目（唯一的例外是 CI：GitHub 要求工作流放在仓库根目录的 `.github/workflows/notes-desktop.yml`，移出时一并带走并去掉其中的 `notes-desktop` 路径前缀）。

- [术语表](docs/GLOSSARY.md)
- [架构决定](docs/adr/)
- [设计规范](docs/design-system.md)：颜色、材质、尺寸、排版与动效预设的定稿取值。
- [重写规格](docs/specs/desktop-rewrite-spec.md)；其余[规格](docs/specs/)是本次重写的验收基线。

## 开发

```bash
npm install
npm run dev          # 带热更新运行
npm run typecheck
npm test             # Vitest：接缝 A（tests/core，核心库对临时笔记库）与纯逻辑单元测试（tests/unit）
npm run test:e2e     # 接缝 B：构建后用 Playwright 驱动 Electron
npm run dist         # 产出不签名的安装包到 dist/
```

Electron 本体在第一次运行时下载；国内网络可先设置 `ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/`。

源码分层：

- `src/core`：核心库，只依赖 Node 文件系统能力，不依赖 Electron 和界面。可以引用 `src/shared`。
- `src/shared`：不含 Node 的纯模块，主进程和界面共用：进程间接口（`window.notes`）的类型与通道，以及界面也要跑的规则，如 Markdown 结构（`markdown.ts`）、代码着色（`codeHighlight.ts`）、列表编辑（`lists.ts`）、Agent 种类（`agentKinds.ts`）和对话的折叠（`conversation.ts`）。
- `src/main`：主进程，窗口、菜单、设置存储，把核心库通过进程间接口交给界面，不含业务逻辑。
- `src/preload`：把进程间接口交给界面。
- `src/renderer`：界面（React）。运行时代码只引用 `src/shared`；`src/core` 只能用 `import type` 引用类型（编译后不留痕迹）。界面用到的库都打进渲染进程的包里，因此放在 `devDependencies`，安装包不再附带它们。

安装包不签名：macOS 版只有 ad-hoc 签名，第一次打开需在 Finder 中右键选“打开”，或在“系统设置 › 隐私与安全性”中允许；Windows 版安装时 SmartScreen 会提示，选“仍要运行”。

测试分三处：`tests/core` 是接缝 A，用 Vitest 对真实的临时笔记库调用核心库的公开接口；`tests/unit` 是不碰磁盘的纯逻辑单元测试（`src/shared` 的规则、界面的模型等）；`tests/e2e` 是接缝 B，用 Playwright 驱动构建好的应用，按角色和无障碍名称找界面元素。

测试用 `NOTES_DESKTOP_USER_DATA` 环境变量把应用设置放到临时目录，与日常使用的设置隔开。
