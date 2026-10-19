# Domain docs

## Layout

当前新笔记软件按 **single-context** 管理，不新增多上下文映射。2026-10-19 起，术语表、架构决定和规格随跨平台重写（[ADR 0004](../../notes-desktop/docs/adr/0004-cross-platform-desktop-rewrite.md)）移入自包含的 `notes-desktop/docs/`，旧版 `NotesLite/` 与 `notes-desktop/` 共用这一份，不维护两份。`design/notes-lite/` 只保留旧版的讨论记录、视觉打磨记录和网页原型。

## Before exploring, read these

- [独立笔记软件术语表](../../notes-desktop/docs/GLOSSARY.md)。
- [独立笔记软件架构决定](../../notes-desktop/docs/adr/) 中与当前任务相关的决定。
- [独立笔记软件规格](../../notes-desktop/docs/specs/spec.md)。

缺失的领域文档不作为停止工作的理由；不要求预先补全。术语和决定在设计讨论澄清后再记录。

## Use the glossary's vocabulary

任务标题、规格、设计与实现统一使用术语表中的名称，不漂移到其明确排除的近义词。发现实际概念缺口时，在相关讨论中指出并按领域建模流程处理。

## Flag ADR conflicts

发现与既有架构决定冲突时明确指出，不静默覆盖，不将待定工程细节描述为用户已确认的决定。

## Original product

原产品的术语和架构文档保留，不与新软件混用。只有涉及原产品时才读取其对应文档。新软件是独立产品，不覆盖原产品、其资料或已有未提交修改。
