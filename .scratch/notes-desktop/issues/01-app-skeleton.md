# 01: 应用骨架与打开笔记库

**What to build:** 打开应用后可以选择一个本地文件夹作为笔记库，下次启动自动打开；双栏导航显示文件夹树与当前目录内容；点击笔记能看到它的原文。项目在 macOS 与 Windows 上都能构建并通过冒烟测试。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Electron + TypeScript + React 应用位于自包含的 `notes-desktop/` 目录，不依赖仓库其他目录
- [ ] 首次启动选择笔记库，之后记住并自动打开；可以切换笔记库
- [ ] 双栏导航：文件夹树与当前目录内容（直属子文件夹在前、直属笔记在后，不汇总后代）
- [ ] 选中笔记显示其 Markdown 原文（只读即可）
- [ ] 核心库与界面分离：核心库只依赖 Node 文件系统能力，有一个对临时笔记库的 Vitest 用例
- [ ] 一个 Playwright 驱动 Electron 打开临时笔记库的冒烟用例
- [ ] CI 在 macOS 与 Windows 上构建、运行两类测试并产出安装包（不签名）

## Comments
