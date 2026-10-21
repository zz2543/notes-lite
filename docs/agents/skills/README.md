# Skill 副本

这些文件是维护者本机 `~/.claude/skills/` 中同名 skill 的副本，供不能访问本机、只能读 GitHub 的代理（如 Notion AI）使用。本机版本为准；本机 skill 更新后需重新复制。

没有 Skill 工具的代理：把“call the Skill tool with "X"”理解为“阅读 `docs/agents/skills/X/SKILL.md` 并照做”。需要子代理的步骤（如 `code-review` 的两路并行审查）可以由同一代理分两遍依次完成，两遍的结论分开汇报。

| Skill | 用途 |
| --- | --- |
| [mp-4-implement](mp-4-implement/SKILL.md) | 主流程第 4 步：按任务实现，在约定接缝处用 tdd，完成后用 code-review 收尾 |
| [tdd](tdd/SKILL.md) | 红 → 绿循环；附 [tests.md](tdd/tests.md)、[mocking.md](tdd/mocking.md) |
| [code-review](code-review/SKILL.md) | 规范与规格两个维度的审查 |
| [codebase-design](codebase-design/SKILL.md) | 深模块、接口、接缝等词汇，tdd 会引用 |
| [mp-3-to-tickets](mp-3-to-tickets/SKILL.md) | 主流程第 3 步：拆任务（只在需要新增任务时参考） |

notes-desktop 的测试接缝已经与用户确认（[规格](../../../notes-desktop/docs/specs/desktop-rewrite-spec.md) 的接缝 A 核心库 / 接缝 B 运行中的应用，助手栏见 [assistant-spec.md](../../../notes-desktop/docs/specs/assistant-spec.md)），tdd 要求的“先确认接缝”无须再问。
