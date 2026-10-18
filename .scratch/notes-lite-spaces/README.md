# 留白「空间」任务索引

日期：2026-10-18。9 项任务的粒度和阻塞关系已获用户确认。规格来源：[留白「空间」规格](../../design/notes-lite/spaces-spec.md)。适用产品为留白（`NotesLite/`），不涉及原产品共笔。

`ready-for-agent` 表示任务描述可供执行，不表示阻塞项已完成。

| 任务 | 阻塞项 |
| --- | --- |
| [01：持续文件监听：外部修改即时可见](issues/01-file-watching.md) | 无 |
| [02：新建空间并在空间模式里浏览](issues/02-create-and-browse-spaces.md) | 无 |
| [03：空间主页渲染：只读的 lb 接口与实时刷新](issues/03-render-space-page-read-only.md) | 01、02 |
| [04：写入记录与操作记录](issues/04-write-records-and-operation-log.md) | 03 |
| [05：页面管理笔记，以及重写自身空间文件](issues/05-manage-notes-from-space-page.md) | 04 |
| [06：只读组件：lb-stat、lb-chart、lb-calendar、lb-records](issues/06-read-only-widgets.md) | 03 |
| [07：快捷录入组件 lb-quick-add](issues/07-quick-add-widget.md) | 04 |
| [08：空间管理与路径同步](issues/08-manage-spaces-and-sync-paths.md) | 02 |
| [09：完整编写说明与端到端验收](issues/09-authoring-guide-and-acceptance.md) | 05、06、07、08 |
