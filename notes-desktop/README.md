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
npm test             # 接缝 A：核心库对临时笔记库的 Vitest 用例
npm run test:e2e     # 接缝 B：构建后用 Playwright 驱动 Electron
npm run dist         # 产出不签名的安装包到 dist/
```

Electron 本体在第一次运行时下载；国内网络可先设置 `ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/`。

源码分层：

- `src/core`：核心库，只依赖 Node 文件系统能力，不依赖 Electron 和界面。
- `src/main`：主进程，窗口、菜单、设置存储，把核心库通过进程间接口交给界面，不含业务逻辑。
- `src/preload`、`src/shared`：进程间接口（`window.notes`）及其类型。
- `src/renderer`：界面（React）。界面用到的库都打进渲染进程的包里，因此放在 `devDependencies`，安装包不再附带它们。

测试用 `NOTES_DESKTOP_USER_DATA` 环境变量把应用设置放到临时目录，与日常使用的设置隔开。
