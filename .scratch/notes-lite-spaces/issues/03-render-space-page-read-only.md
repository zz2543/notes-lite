# 03: 空间主页渲染：只读的 lb 接口与实时刷新

**What to build:** 打开一个空间时，右栏渲染其空间主页；页面能通过 `lb` 读取范围内的记录表和笔记，记录表变化时自动刷新，页面出错时显示错误条。手写一段调用 `lb.query` 的空间主页即可看到真实数据。

**Blocked by:** 01：持续文件监听；02：新建空间并在空间模式里浏览

**Status:** ready-for-agent

**Progress:** completed

- [x] 空间主页使用独立的 WKWebView 配置：不拦截网络、每个空间各自隔离的持久化数据存储；公式渲染沙盒的行为不变。
- [x] 注入样式包（CSS 变量和 `.lb-card` 等 class），跟随深色模式。
- [x] NotesCore 中的 lb 请求处理：输入结构化 JSON 请求、输出 JSON 结果或结构化错误；页面端 `lb` 仅是转发。
- [x] 支持 `lb.query(source, {filter, sort, limit})`、`lb.notes`、`lb.read`、`lb.scope`；记录表按「路径#标题」定位，不写标题取第一张表；占位符展开；字段类型推断（数字/`YYYY-MM-DD` 日期/文字）。
- [x] 范围校验：拒绝范围外路径、`..`、符号链接逃逸、隐藏目录和 `.留白/`（本任务内只读），返回结构化错误。
- [x] `lb.on("change")`：无论是编辑器保存、外部修改还是其他来源，范围内记录表变化后，打开着的空间主页都会收到通知；外部 Agent 修改空间文件后页面自动重新加载，不审阅。
- [x] JS 报错和加载失败时，右栏顶部显示错误条，附「复制错误给 agent」按钮。
- [x] 在 lb 请求处理接缝上测试定位、占位符、类型推断和范围拒绝（临时笔记库）。

## Comments

2026-10-18：已实现。`SpaceAPITests`、`SpaceWorkflowTests`（实时刷新、错误条、行号、iframe 与跳转限制）与截图。完整记录见 [实测记录](../../../NotesLite/evidence/spaces/verification.md)。
