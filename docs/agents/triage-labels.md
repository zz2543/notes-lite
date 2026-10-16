# Triage labels

使用默认五个分诊角色；本地任务的 `Status` 字段使用下表中的标签字符串。

| 技能角色 | 本地标签 | 含义 |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | 等待维护者评估 |
| `needs-info` | `needs-info` | 等待补充信息 |
| `ready-for-agent` | `ready-for-agent` | 描述完整，可由代理实施；仍须满足阻塞关系 |
| `ready-for-human` | `ready-for-human` | 需要人工实施 |
| `wontfix` | `wontfix` | 不予处理 |

标签不表示任务已经实施或验收通过。执行进度及完成证据按 [问题跟踪约定](issue-tracker.md) 单独记录。
