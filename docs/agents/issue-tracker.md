# Issue tracker: Local Markdown

本仓库使用本地 Markdown 作为问题跟踪工具，无需远程仓库。

## Conventions

- 每个功能使用 `.scratch/<feature-slug>/` 目录。
- 每个任务独立保存为 `issues/<NN>-<slug>.md`，从 `01` 起按依赖顺序编号，不使用合并任务文件。
- 规格已有正式文档时保留原位，在功能目录的 `spec.md` 提供引用，不维护两份规格正文。
- 当前功能为 `notes-lite`，沿用已有 14 个任务及 2026-10-19 新增的 15–18（[规格](../../notes-desktop/docs/specs/list-exit-caret-spec.md)）；规格入口为 `.scratch/notes-lite/spec.md`。
- 功能 `notes-lite-spaces`（留白「空间」）：规格入口为 `.scratch/notes-lite-spaces/spec.md`，9 个任务见该目录 `README.md`；01、02 无阻塞。
- 跨平台重写（代号 `notes-desktop`，[ADR 0004](../../notes-desktop/docs/adr/0004-cross-platform-desktop-rewrite.md)）：功能目录为 `.scratch/notes-desktop/`，规格入口为 `.scratch/notes-desktop/spec.md`（含界面与动效、助手栏两份配套规格），30 个任务见该目录 `README.md`；01 无阻塞。旧版 `NotesLite/` 起只修严重 bug，不再新增功能。
- 任务使用 `Status` 字段记录分诊状态，标签含义参见 [triage-labels.md](triage-labels.md)。已有 `**Status:**` 格式同样有效。
- `Blocked by` 字段记录阻塞项；`ready-for-agent` 表示描述已就绪，阻塞项全部完成后才能开始。
- 分诊状态与执行进度分开。尚未记录执行进度视为未开始；开始后记录 `Progress: in-progress`，全部验收通过后才记录 `Progress: completed`，并附验证证据。不能仅凭 `ready-for-agent` 判断阻塞项完成。
- 评论和后续讨论追加到任务的 `## Comments` 部分，不覆盖已有验收标准和历史记录。

## When a skill says "publish to the issue tracker"

在功能目录创建或更新相应本地文件即完成发布；已有任务继续沿用，不创建重复副本。任务拆分和修改仍遵守相应技能的确认要求。不创建远程 issue。

## When a skill says "fetch the relevant ticket"

读取用户给出的任务文件；只给出编号时，从对应功能的任务目录定位。读取完整内容及评论，并核查阻塞项的实际完成证据。

## Frontier

按编号选择未完成且阻塞项均已完成的任务。没有完成记录的阻塞项仍视为未完成。当前 14 个任务尚未实施，只有 01 无阻塞。
